"use client";

import { useEffect, useRef, useState } from "react";
import { DEFAULT_CONFIG, type FlowFieldConfig } from "./config";
import { FlowFieldControls } from "./FlowFieldControls";

type FlowFieldProps = {
  className?: string;
};

type Particle = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  seed: number;
  color: 0 | 1 | 2;
};

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function rand(seed: number) {
  // Deterministic-ish hash to avoid needing a PRNG package.
  const x = Math.sin(seed) * 10000;
  return x - Math.floor(x);
}

const IS_DEV = process.env.NODE_ENV === "development";

export function FlowField({ className = "" }: FlowFieldProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const rafRef = useRef<number | null>(null);

  // Live-tunable config. The animation loop reads it through a ref so panel
  // edits apply on the next frame without restarting the effect.
  const [config, setConfig] = useState<FlowFieldConfig>(DEFAULT_CONFIG);
  const configRef = useRef<FlowFieldConfig>(config);
  useEffect(() => {
    configRef.current = config;
  }, [config]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const reduced =
      window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;
    type NetworkInformation = { saveData?: boolean };
    type NavigatorWithConnection = Navigator & { connection?: NetworkInformation };
    const saveData = (navigator as NavigatorWithConnection).connection?.saveData ?? false;
    if (reduced || saveData) return;

    const ctx = canvas.getContext("2d", { alpha: true });
    if (!ctx) return;

    const pointer = { x: -10_000, y: -10_000, active: false };

    let cssW = 1;
    let cssH = 1;
    let particles: Particle[] = [];

    const makeParticle = (i: number): Particle => {
      const s = i * 12.345;
      return {
        x: rand(s) * cssW,
        y: rand(s + 1) * cssH,
        vx: 0,
        vy: 0,
        seed: rand(s + 2) * 1000,
        color: (i % 3) as 0 | 1 | 2,
      };
    };

    const targetCount = () => {
      const cfg = configRef.current;
      const coarse = window.matchMedia?.("(pointer: coarse)")?.matches ?? false;
      const density = coarse ? cfg.densityCoarse : cfg.densityDesktop;
      const lo = Math.min(cfg.countMin, cfg.countMax);
      const hi = Math.max(cfg.countMin, cfg.countMax);
      return clamp(Math.floor(((cssW * cssH) / 5000) * density), lo, hi);
    };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      cssW = Math.max(1, Math.floor(rect.width));
      cssH = Math.max(1, Math.floor(rect.height));

      const dpr = Math.max(1, window.devicePixelRatio || 1);
      canvas.width = Math.floor(cssW * dpr);
      canvas.height = Math.floor(cssH * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      particles = Array.from({ length: targetCount() }, (_, i) => makeParticle(i));

      ctx.clearRect(0, 0, cssW, cssH);
    };

    const onPointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointer.x = event.clientX - rect.left;
      pointer.y = event.clientY - rect.top;
      pointer.active = true;
    };
    const onBlur = () => {
      pointer.active = false;
      pointer.x = -10_000;
      pointer.y = -10_000;
    };

    // Canvas is pointer-events:none (so it never blocks UI), so we track pointer globally.
    window.addEventListener("pointermove", onPointerMove, { passive: true });
    window.addEventListener("blur", onBlur);
    window.addEventListener("resize", resize, { passive: true });
    resize();

    let t0 = performance.now();
    let running = true;

    const tick = (now: number) => {
      if (!running) return;
      const cfg = configRef.current;
      const dt = clamp(now - t0, 6, 28);
      t0 = now;

      // Keep the particle count in sync with live config / canvas size by
      // growing or shrinking the pool in place (no full reseed mid-flight).
      const target = targetCount();
      if (particles.length < target) {
        for (let i = particles.length; i < target; i++) particles.push(makeParticle(i));
      } else if (particles.length > target) {
        particles.length = target;
      }

      const scrollMax = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      const scroll = clamp(window.scrollY / scrollMax, 0, 1);

      // Fade previous frames by *erasing* alpha (destination-out) instead of
      // painting black. Trails decay to fully transparent — the gradient behind
      // shows through cleanly, with no dark box or permanent residue building up.
      // Each particle still leaves a short fading tail (its own afterimage).
      const fade = clamp(cfg.fade + scroll * cfg.fadeScroll, 0, 1);
      if (fade > 0) {
        ctx.save();
        ctx.globalCompositeOperation = "destination-out";
        ctx.fillStyle = `rgba(0,0,0,${fade})`;
        ctx.fillRect(0, 0, cssW, cssH);
        ctx.restore();
      }

      const fieldAngle = (x: number, y: number, t: number, seed: number) => {
        // Cheap "flowy" field: 3 trig layers blended.
        const n1 = Math.sin(x * cfg.fieldScaleX + (t + seed) * cfg.timeX);
        const n2 = Math.cos(y * cfg.fieldScaleY - (t - seed) * cfg.timeY);
        const n3 = Math.sin((x + y) * cfg.fieldScaleXY + (t + seed) * cfg.timeXY);
        const n = (n1 + n2 + n3) / 3;
        return n * Math.PI * cfg.angleMul;
      };

      const colors = [
        `rgba(255,255,255,${cfg.opacityA})`,
        `rgba(255,255,255,${cfg.opacityB})`,
        `rgba(255,255,255,${cfg.opacityC})`,
      ] as const;

      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      ctx.lineWidth = cfg.lineWidth;

      const speed = cfg.speedBase + scroll * cfg.speedScroll;
      // Clamp below 1: at >=1 the velocity integrator stops converging and
      // particles accelerate without bound.
      const damping = clamp(cfg.damping + scroll * cfg.dampingScroll, 0, 0.99);
      const influenceR = cfg.influenceR;

      for (const p of particles) {
        const px = p.x;
        const py = p.y;

        const a = fieldAngle(px, py, now, p.seed);
        const ax = Math.cos(a) * cfg.accel;
        const ay = Math.sin(a) * cfg.accel;

        p.vx = p.vx * damping + ax;
        p.vy = p.vy * damping + ay;

        if (pointer.active && influenceR > 0) {
          const dx = px - pointer.x;
          const dy = py - pointer.y;
          const d = Math.sqrt(dx * dx + dy * dy) || 1;
          if (d < influenceR) {
            const f = (1 - d / influenceR) * cfg.swirl;
            // Swirl around pointer for "alive" feel.
            p.vx += (-dy / d) * f;
            p.vy += (dx / d) * f;
          }
        }

        const nx = px + p.vx * speed * (dt / 16);
        const ny = py + p.vy * speed * (dt / 16);

        p.x = nx;
        p.y = ny;

        ctx.strokeStyle = colors[p.color];
        ctx.beginPath();
        ctx.moveTo(px, py);
        ctx.lineTo(nx, ny);
        ctx.stroke();

        const margin = 40;
        if (nx < -margin || nx > cssW + margin || ny < -margin || ny > cssH + margin) {
          const s = p.seed + now * 0.001;
          p.x = rand(s) * cssW;
          p.y = rand(s + 1) * cssH;
          p.vx = 0;
          p.vy = 0;
        }
      }

      ctx.restore();
      if (!running) return;
      rafRef.current = window.requestAnimationFrame(tick);
    };

    rafRef.current = window.requestAnimationFrame(tick);

    const onVisibilityChange = () => {
      if (document.hidden) {
        running = false;
        if (rafRef.current) window.cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
        return;
      }
      if (!running) {
        running = true;
        t0 = performance.now();
        rafRef.current = window.requestAnimationFrame(tick);
      }
    };
    document.addEventListener("visibilitychange", onVisibilityChange);

    return () => {
      if (rafRef.current) window.cancelAnimationFrame(rafRef.current);
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("blur", onBlur);
      window.removeEventListener("resize", resize);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, []);

  return (
    <>
      <canvas
        ref={canvasRef}
        className={`block w-full h-full pointer-events-none ${className}`}
        aria-hidden="true"
      />
      {IS_DEV && (
        <FlowFieldControls
          config={config}
          onChange={(key, value) => setConfig((prev) => ({ ...prev, [key]: value }))}
          onReset={() => setConfig(DEFAULT_CONFIG)}
        />
      )}
    </>
  );
}
