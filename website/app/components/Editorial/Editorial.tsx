"use client";

import Image from "next/image";
import { useRef } from "react";
import { useScrollMomentumFrame, type Momentum } from "../Scroll/scrollMomentum";

/* ------------------------------------------------------------------ *
 * Editorial primitives shared by the homepage sections: a scroll-
 * velocity-reactive divider, a numbered section marker, and a screenshot
 * framed in an ambient "light pool" so the gray app chrome doesn't meet
 * the near-black page on a hard edge.
 * ------------------------------------------------------------------ */

// Curve divider — a horizontal bezier that whips in the flick direction,
// then settles flat. Painted imperatively off the shared momentum loop.
export function CurveDivider({ label }: { label?: string }) {
  const pathRef = useRef<SVGPathElement | null>(null);
  const W = 1000;
  const H = 64;
  const mid = H / 2;
  const amp = 22;

  useScrollMomentumFrame(({ velocity }: Momentum) => {
    const off = -velocity * amp;
    pathRef.current?.setAttribute(
      "d",
      `M 0 ${mid} C ${W * 0.3} ${mid + off} ${W * 0.7} ${mid - off} ${W} ${mid}`
    );
  });

  return (
    <div className="relative my-10 sm:my-16">
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="block h-12 w-full sm:h-16" aria-hidden="true">
        <defs>
          <linearGradient id="dividerStroke" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="rgba(255,255,255,0)" />
            <stop offset="50%" stopColor="rgba(255,255,255,0.34)" />
            <stop offset="100%" stopColor="rgba(255,255,255,0)" />
          </linearGradient>
        </defs>
        <path
          ref={pathRef}
          d={`M 0 ${mid} C ${W * 0.3} ${mid} ${W * 0.7} ${mid} ${W} ${mid}`}
          fill="none"
          stroke="url(#dividerStroke)"
          strokeWidth="1.5"
          vectorEffect="non-scaling-stroke"
        />
      </svg>
      {label ? (
        <div className="pointer-events-none absolute inset-0 grid place-items-center">
          <span className="bg-black/40 px-3 font-mono text-[10px] uppercase tracking-[0.3em] text-white/40 backdrop-blur-sm">
            {label}
          </span>
        </div>
      ) : null}
    </div>
  );
}

// Editorial section marker — a number, a hairline, a keyword.
export function IndexMark({ n, label }: { n: string; label: string }) {
  return (
    <div className="mb-5 flex items-center gap-3">
      <span className="font-mono text-xs font-medium tracking-[0.3em] text-white/55">{n}</span>
      <span className="h-px w-10 bg-gradient-to-r from-white/30 to-transparent" />
      <span className="font-mono text-[10px] uppercase tracking-[0.3em] text-white/35">{label}</span>
    </div>
  );
}

type ShotName = "scrolling" | "general" | "application-settings" | "buttons-action";

const SHOT_SIZES: Record<ShotName, { width: number; height: number }> = {
  scrolling: { width: 1124, height: 1354 },
  general: { width: 1124, height: 610 },
  "application-settings": { width: 1926, height: 1276 },
  "buttons-action": { width: 1440, height: 1330 },
};

// Screenshot on a gray "light pool" that ramps black → gray so the app
// chrome never meets the page on a hard edge.
export function Shot({
  locale,
  name,
  alt,
  className = "",
}: {
  locale: "en-us" | "zh-cn";
  name: ShotName;
  alt: string;
  className?: string;
}) {
  const size = SHOT_SIZES[name];
  return (
    <div className={`relative ${className}`}>
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -inset-12 -z-10 rounded-[64px] blur-3xl"
        style={{
          background:
            "radial-gradient(55% 55% at 50% 45%, rgba(122,122,134,0.30), rgba(64,64,72,0.12) 58%, transparent 78%)",
        }}
      />
      <div
        className="rounded-[22px] border border-white/[0.10] p-3"
        style={{
          background: "linear-gradient(180deg, #2b292e, #1b1a1f)",
          boxShadow: "0 1px 0 rgba(255,255,255,0.10) inset, 0 50px 120px -34px rgba(0,0,0,0.9)",
        }}
      >
        <Image
          src={`/readme/${locale}/${name}.png`}
          alt={alt}
          width={size.width}
          height={size.height}
          sizes="(min-width: 768px) 560px, calc(100vw - 48px)"
          className="block h-auto w-full rounded-[15px] border border-white/[0.06] bg-[#302d31]"
        />
      </div>
    </div>
  );
}
