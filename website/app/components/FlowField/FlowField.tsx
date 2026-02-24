"use client";

import { useEffect, useRef } from "react";

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

export function FlowField({ className = "" }: FlowFieldProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const rafRef = useRef<number | null>(null);

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
    const colors = [
      "rgba(255,255,255,0.12)",
      "rgba(255,255,255,0.08)",
      "rgba(255,255,255,0.05)",
    ] as const;

    let cssW = 1;
    let cssH = 1;
    let particles: Particle[] = [];

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      cssW = Math.max(1, Math.floor(rect.width));
      cssH = Math.max(1, Math.floor(rect.height));

      const dpr = Math.max(1, window.devicePixelRatio || 1);
      canvas.width = Math.floor(cssW * dpr);
      canvas.height = Math.floor(cssH * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      const coarse = window.matchMedia?.("(pointer: coarse)")?.matches ?? false;
      const density = coarse ? 0.35 : 0.7;
      const count = clamp(Math.floor((cssW * cssH) / 5000 * density), 140, 620);

      particles = Array.from({ length: count }, (_, i) => {
        const s = i * 12.345;
        return {
          x: rand(s) * cssW,
          y: rand(s + 1) * cssH,
          vx: 0,
          vy: 0,
          seed: rand(s + 2) * 1000,
          color: (i % 3) as 0 | 1 | 2,
        };
      });

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

    const fieldAngle = (x: number, y: number, t: number, seed: number) => {
      // Cheap “flowy” field: 3 trig layers blended.
      const n1 = Math.sin(x * 0.0022 + (t + seed) * 0.00065);
      const n2 = Math.cos(y * 0.0020 - (t - seed) * 0.00055);
      const n3 = Math.sin((x + y) * 0.0014 + (t + seed) * 0.00032);
      const n = (n1 + n2 + n3) / 3;
      return n * Math.PI * 2.2;
    };

    const tick = (now: number) => {
      if (!running) return;
      const dt = clamp(now - t0, 6, 28);
      t0 = now;

      const scrollMax = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
      const scroll = clamp(window.scrollY / scrollMax, 0, 1);

      // Persistent trails.
      ctx.fillStyle = `rgba(0, 0, 0, ${0.08 + scroll * 0.05})`;
      ctx.fillRect(0, 0, cssW, cssH);

      ctx.save();
      ctx.globalCompositeOperation = "lighter";
      ctx.lineWidth = 1;

      const speed = 0.8 + scroll * 1.4;
      const influenceR = 180;

      for (const p of particles) {
        const px = p.x;
        const py = p.y;

        const a = fieldAngle(px, py, now, p.seed);
        const ax = Math.cos(a) * 0.55;
        const ay = Math.sin(a) * 0.55;

        p.vx = p.vx * 0.84 + ax;
        p.vy = p.vy * 0.84 + ay;

        if (pointer.active) {
          const dx = px - pointer.x;
          const dy = py - pointer.y;
          const d = Math.sqrt(dx * dx + dy * dy) || 1;
          if (d < influenceR) {
            const f = (1 - d / influenceR) * 1.15;
            // Swirl around pointer for “alive” feel.
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
    <canvas
      ref={canvasRef}
      className={`block w-full h-full pointer-events-none ${className}`}
      aria-hidden="true"
    />
  );
}
