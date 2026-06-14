"use client";

import { useEffect, useRef } from "react";
import { STARS } from "./stars";

// Screen-fixed canvas starfield drawn from the real Yale Bright Star Catalog.
// Each star sits at its catalog position (equirectangular RA/Dec) and twinkles on
// its own random phase/speed — replacing the old dot grid as the wall's backdrop.
export function Starfield() {
  const ref = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const N = STARS.length;
    // Deterministic per-star twinkle params (no Math.random → stable across mounts).
    const phase = new Float32Array(N);
    const speed = new Float32Array(N);
    for (let i = 0; i < N; i++) {
      const frac = (n: number) => {
        const v = Math.sin(n) * 43758.5453;
        return v - Math.floor(v);
      };
      phase[i] = frac(i * 12.9898 + STARS[i][0] * 78.233) * Math.PI * 2;
      speed[i] = 0.5 + frac(i * 4.1414) * 1.9; // 0.5–2.4 rad/s
    }

    let w = 0;
    let h = 0;
    let dpr = 1;
    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = canvas.clientWidth;
      h = canvas.clientHeight;
      canvas.width = Math.max(1, Math.round(w * dpr));
      canvas.height = Math.max(1, Math.round(h * dpr));
    };
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);
    resize();

    let raf = 0;
    let start = 0;
    const draw = (now: number) => {
      if (!start) start = now;
      const t = (now - start) / 1000;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = "#ffffff";
      for (let i = 0; i < N; i++) {
        const s = STARS[i];
        const b = s[2]; // brightness 0..1
        const tw = 0.6 + 0.4 * Math.sin(t * speed[i] + phase[i]); // 0.2..1
        const a = Math.min(1, (0.1 + b * 0.85) * tw);
        if (a < 0.02) continue;
        const px = s[0] * w;
        const py = (1 - s[1]) * h; // flip so northern declinations sit up top
        const size = b > 0.62 ? 1.8 : b > 0.38 ? 1.2 : 0.85;
        ctx.globalAlpha = a;
        ctx.fillRect(px - size / 2, py - size / 2, size, size);
      }
      ctx.globalAlpha = 1;
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
    };
  }, []);

  return <canvas ref={ref} className="pointer-events-none absolute inset-0 h-full w-full" aria-hidden />;
}
