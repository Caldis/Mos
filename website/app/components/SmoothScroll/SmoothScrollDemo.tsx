"use client";

import { useEffect, useRef, useState, useSyncExternalStore, type ReactNode, type RefObject } from "react";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";
import { useI18n } from "@/app/i18n/context";

/* ------------------------------------------------------------------ *
 * A live, minimal port of Mos' scroll-smoothing core. Scroll the left
 * panel and it snaps line-by-line (raw wheel). Scroll the right and the
 * same input runs Mos' real algorithm. When idle, both auto-scroll so
 * the difference plays on its own — smooth glide vs stepped jumps.
 *
 * Ported from Mos/ScrollCore/{ScrollPoster,Interpolator,ScrollFilter}.swift
 * and Mos/Utils/Constants.swift. Two refinements over a naive port, for
 * smoothness:
 *   • drive an inner GPU transform (translate3d) on a float accumulator,
 *     never element.scrollTop (which repaints and integer-snaps);
 *   • make the per-frame lerp dt-correct so 60/120Hz feel identical.
 * ------------------------------------------------------------------ */

const RAW_STEP = 48; // one row — the raw wheel's coarse, unsmoothed jump
const IDLE_MS = 1600; // pause auto-scroll this long after the user scrolls
const AUTO_SPEED = 64; // idle auto-scroll velocity, px/s

// Web-tuned starting values (calmer than the macOS app's 33.6 / 2.70 / 4.35,
// which feels a touch fast in a browser). Slider RANGES still match Mos exactly.
const DEFAULT_STEP = 10;
const DEFAULT_SPEED = 1.0;
const DEFAULT_DURATION = 3.75;

const ROWS = Array.from({ length: 40 }, (_, i) => ({ i, w: 38 + ((i * 37) % 52) }));

// Top/bottom fade so rows dissolve at the viewport edges.
const MASK_STYLE = {
  WebkitMaskImage: "linear-gradient(to bottom, transparent, #000 10%, #000 90%, transparent)",
  maskImage: "linear-gradient(to bottom, transparent, #000 10%, #000 90%, transparent)",
} as const;

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function round3(n: number) {
  return Math.round(n * 1000) / 1000;
}

// Constants.swift -> generateDurationTransition(with:)
function durationTransition(duration: number) {
  const upperLimit = 5.0 + 0.2;
  return round3(1 - Math.sqrt(clamp(duration, 0, 5) / upperLimit));
}

// Hydration-safe coarse-pointer check (same shape as useHydratedReducedMotion):
// SSR assumes a fine pointer, so the wheel-driven path renders first and we only
// switch to native scrolling after mount if the device is actually touch.
function useCoarsePointer() {
  return useSyncExternalStore(
    (cb) => {
      const mq = window.matchMedia("(pointer: coarse)");
      mq.addEventListener?.("change", cb);
      return () => mq.removeEventListener?.("change", cb);
    },
    () => window.matchMedia("(pointer: coarse)").matches,
    () => false
  );
}

type Params = { step: number; speed: number; trans: number };

function usePanelScroll(
  viewportRef: RefObject<HTMLDivElement | null>,
  innerRef: RefObject<HTMLDivElement | null>,
  mode: "raw" | "mos",
  paramsRef: RefObject<Params>,
  nativeScroll: boolean
) {
  useEffect(() => {
    const vp = viewportRef.current;
    const inner = innerRef.current;
    if (!vp || !inner || nativeScroll) return;

    // Infinite, looping content (two stacked copies) so there is never a scroll
    // bound to get stuck against — the wheel is always ours. `pos` is a free
    // float; the transform wraps it by one list-copy height for a seamless loop.
    let pos = 0;
    // Mos engine — `remaining` IS ScrollPoster's (buffer - current) gap, tracked
    // directly so an ever-growing `pos` can't accumulate float error.
    let remaining = 0;
    let lastDelta = 0;
    let win = [0, 0]; // ScrollFilter window
    let rawAccum = 0;
    let stepTimer = 0;

    let period = inner.offsetHeight / 2; // height of one list copy
    const ro = new ResizeObserver(() => {
      period = inner.offsetHeight / 2;
    });
    ro.observe(inner);

    let lastInput = -Infinity; // start idle so auto-scroll begins immediately
    let lastTime = performance.now();
    let raf = 0;

    // ScrollFilter.polish + value — smooths the per-frame delta to kill start jitter.
    const filter = (next: number) => {
      const first = win[1];
      const diff = next - first;
      win = [first, first + 0.23 * diff, first + 0.5 * diff, first + 0.77 * diff, next];
      return win[0];
    };
    const wrap = (p: number) => (period > 0 ? ((p % period) + period) % period : 0);
    const rawInterval = RAW_STEP / AUTO_SPEED; // seconds between stepped jumps

    const frame = (now: number) => {
      const dt = clamp((now - lastTime) / 1000, 0, 0.05);
      lastTime = now;
      const idle = now - lastInput > IDLE_MS;

      if (mode === "mos") {
        // ScrollPoster.processing — dt-corrected so 60/120Hz match.
        const transDt = 1 - Math.pow(1 - paramsRef.current.trans, dt * 60);
        const f = remaining * transDt; // Interpolator.lerp on the gap
        remaining -= f;
        pos += filter(f); // ScrollFilter.fill
        if (idle) pos += AUTO_SPEED * dt; // smooth idle drift
      } else if (idle) {
        // raw idle drift — coarse, stepped.
        stepTimer += dt;
        while (stepTimer >= rawInterval) {
          stepTimer -= rawInterval;
          pos += RAW_STEP;
        }
      }

      inner.style.transform = `translate3d(0, ${(-wrap(pos)).toFixed(2)}px, 0)`;
      raf = window.requestAnimationFrame(frame);
    };
    raf = window.requestAnimationFrame(frame);

    const onWheel = (e: WheelEvent) => {
      e.preventDefault(); // infinite content — always ours, never stuck at a bound
      lastInput = performance.now();

      if (mode === "raw") {
        rawAccum += e.deltaY;
        while (Math.abs(rawAccum) >= RAW_STEP) {
          const s = Math.sign(rawAccum);
          pos += s * RAW_STEP;
          rawAccum -= s * RAW_STEP;
        }
        return;
      }

      // Mos path: ScrollCore normalize-up-to-step + ScrollPoster.update.
      const { step, speed } = paramsRef.current;
      const y = (Math.abs(e.deltaY) < step ? (Math.sign(e.deltaY) || 1) * step : e.deltaY) * speed;
      // same direction accumulates onto the gap; a reversal resets it.
      remaining = y * lastDelta > 0 ? remaining + y : y;
      lastDelta = y;
    };

    vp.addEventListener("wheel", onWheel, { passive: false });
    return () => {
      window.cancelAnimationFrame(raf);
      vp.removeEventListener("wheel", onWheel);
      ro.disconnect();
      inner.style.transform = "";
    };
  }, [viewportRef, innerRef, mode, paramsRef, nativeScroll]);
}

function Rows() {
  return (
    <>
      {ROWS.map((r) => (
        <div key={r.i} className="flex items-center gap-3 border-b border-white/[0.06] px-4 py-3">
          <span className="w-6 shrink-0 font-mono text-[11px] tabular-nums text-white/30">
            {String(r.i + 1).padStart(2, "0")}
          </span>
          <span className="shrink-0 rounded-lg border border-white/12 bg-white/[0.07]" style={{ width: 22, height: 22 }} />
          <div className="min-w-0 flex-1 space-y-1.5">
            <span className="block h-2 rounded-full bg-white/[0.20]" style={{ width: `${r.w}%` }} />
            <span className="block h-1.5 rounded-full bg-white/[0.08]" style={{ width: `${Math.round(r.w * 0.6)}%` }} />
          </div>
        </div>
      ))}
    </>
  );
}

function Panel({
  title,
  tag,
  accent,
  viewportRef,
  innerRef,
  nativeScroll,
  scrollHint,
  controls,
  fillViewport = false,
}: {
  title: string;
  tag: string;
  accent: boolean;
  viewportRef: RefObject<HTMLDivElement | null>;
  innerRef: RefObject<HTMLDivElement | null>;
  nativeScroll: boolean;
  scrollHint: string;
  controls?: ReactNode;
  // The panel without controls fills its height to match the taller (controls)
  // panel — the controls panel keeps a fixed viewport so the row has a definite
  // height to flex against.
  fillViewport?: boolean;
}) {
  return (
    <div className="flex min-h-0 flex-col rounded-[20px] border border-white/[0.08] bg-white/[0.02] p-4 sm:p-5">
      <div className="mb-3 flex items-center justify-between">
        <span className={`font-display text-sm ${accent ? "text-white" : "text-white/55"}`}>{title}</span>
        <span
          className={`inline-flex items-center gap-1.5 font-mono text-[10px] uppercase tracking-[0.2em] ${
            accent ? "text-white/70" : "text-white/40"
          }`}
        >
          <span className={`h-1.5 w-1.5 rounded-full ${accent ? "bg-white shadow-[0_0_8px_rgba(255,255,255,0.6)]" : "bg-white/40"}`} />
          {tag}
        </span>
      </div>
      {fillViewport ? (
        // Out-of-flow viewport: contributes 0 to sizing, so the row height comes
        // only from the controls panel; this one then fills whatever it's given.
        <div className="relative min-h-[300px] flex-1">
          <div
            ref={viewportRef}
            className={`absolute inset-0 cursor-ns-resize ${nativeScroll ? "overflow-y-auto" : "overflow-hidden"}`}
            style={MASK_STYLE}
          >
            <div ref={innerRef} className={nativeScroll ? "" : "will-change-transform"}>
              <div>
                <Rows />
              </div>
              <div aria-hidden="true">
                <Rows />
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div
          ref={viewportRef}
          className={`relative h-[300px] cursor-ns-resize ${nativeScroll ? "overflow-y-auto" : "overflow-hidden"}`}
          style={MASK_STYLE}
        >
          <div ref={innerRef} className={nativeScroll ? "" : "will-change-transform"}>
            <div>
              <Rows />
            </div>
            <div aria-hidden="true">
              <Rows />
            </div>
          </div>
        </div>
      )}
      <div className="mt-3 text-center font-mono text-[10px] uppercase tracking-[0.2em] text-white/25">
        {scrollHint} ↕
      </div>
      {controls}
    </div>
  );
}

// Compact label / track / value row + a one-line description, inside the panel
// it controls. Uses the page body font (synced with the rest of the site), not
// the mono chip style.
function MiniSlider({
  label,
  hint,
  value,
  display,
  min,
  max,
  onChange,
}: {
  label: string;
  hint: string;
  value: number;
  display: string;
  min: number;
  max: number;
  onChange: (v: number) => void;
}) {
  return (
    <div>
      <div className="flex items-center gap-3">
        <span className="w-9 shrink-0 text-[12px] text-white/70">{label}</span>
        <input
          className="range flex-1"
          type="range"
          min={min}
          max={max}
          step={0.01}
          value={value}
          onChange={(e) => onChange(Number(e.target.value))}
          aria-label={label}
        />
        <span className="w-12 shrink-0 text-right text-[11px] tabular-nums text-white/55">{display}</span>
      </div>
      <p className="mt-1 pl-12 text-[11px] leading-snug text-white/40">{hint}</p>
    </div>
  );
}

export function SmoothScrollDemo() {
  const { t } = useI18n();
  const reduced = useHydratedReducedMotion();
  // Touch devices have no wheel — fall back to native scrolling so the panels
  // are never frozen. (Also covers reduced-motion.)
  const coarse = useCoarsePointer();
  const nativeScroll = reduced || coarse;

  const [step, setStep] = useState(DEFAULT_STEP);
  const [speed, setSpeed] = useState(DEFAULT_SPEED);
  const [duration, setDuration] = useState(DEFAULT_DURATION);

  const rawVp = useRef<HTMLDivElement | null>(null);
  const rawInner = useRef<HTMLDivElement | null>(null);
  const mosVp = useRef<HTMLDivElement | null>(null);
  const mosInner = useRef<HTMLDivElement | null>(null);
  const paramsRef = useRef<Params>({ step, speed, trans: durationTransition(duration) });

  useEffect(() => {
    paramsRef.current = { step, speed, trans: durationTransition(duration) };
  }, [step, speed, duration]);

  usePanelScroll(rawVp, rawInner, "raw", paramsRef, nativeScroll);
  usePanelScroll(mosVp, mosInner, "mos", paramsRef, nativeScroll);

  // The sliders live inside the "With Mos" panel — they only shape the smooth
  // side, so they belong to it, not to a detached row under both panels.
  // Labels/values use the page body font (synced with the site) and are Chinese
  // only — intentionally NOT i18n — each with a one-line note on what it does.
  const controls = (
    <div className="mt-4 space-y-3 border-t border-white/[0.07] pt-4">
      <div className="flex items-baseline justify-between">
        <span className="text-[11px] tracking-[0.06em] text-white/50">参数</span>
        <span className="text-[11px] tabular-nums text-white/35">过渡 {durationTransition(duration).toFixed(3)}</span>
      </div>
      <MiniSlider
        label="步长"
        hint="每格滚轮的基础滚动距离，越大单次跨度越大"
        value={step}
        display={step.toFixed(2)}
        min={0.01}
        max={100}
        onChange={setStep}
      />
      <MiniSlider
        label="速度"
        hint="在步长之上的整体倍率，越大滚动越快"
        value={speed}
        display={`×${speed.toFixed(2)}`}
        min={1}
        max={10}
        onChange={setSpeed}
      />
      <MiniSlider
        label="时长"
        hint="平滑缓动的持续时间，越大滑行越久、越顺滑"
        value={duration}
        display={duration.toFixed(2)}
        min={1}
        max={5}
        onChange={setDuration}
      />
    </div>
  );

  return (
    <div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Panel
          title={t.scroll.withoutMos}
          tag={t.scroll.tagRaw}
          accent={false}
          viewportRef={rawVp}
          innerRef={rawInner}
          nativeScroll={nativeScroll}
          scrollHint={t.scroll.scrollInside}
          fillViewport
        />
        <Panel
          title={t.scroll.withMos}
          tag={t.scroll.tagSmooth}
          accent
          viewportRef={mosVp}
          innerRef={mosInner}
          nativeScroll={nativeScroll}
          scrollHint={t.scroll.scrollInside}
          controls={controls}
        />
      </div>
    </div>
  );
}
