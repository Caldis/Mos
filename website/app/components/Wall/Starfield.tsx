"use client";

import { useEffect, useRef } from "react";
import { STARS } from "./stars";
import type { UseViewport } from "@/app/wall/useViewport";

// Stars track the viewport's WORLD centre (not its raw transform), so panning
// drifts them slowly (parallax depth) while zooming — which keeps the same world
// centre under the cursor — does NOT slide them. Zoom only makes the field
// breathe a touch (subtle zoom parallax), never pan.
const PARALLAX_PAN = 0.15; // stars drift at 15% of the camera's world motion
const ZOOM_PARALLAX = 0.12; // star spacing scales at 12% of the zoom change

export function Starfield({ vp }: { vp: UseViewport }) {
  const ref = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const N = STARS.length;
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
    let baseTile = 1;
    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = canvas.clientWidth;
      h = canvas.clientHeight;
      canvas.width = Math.max(1, Math.round(w * dpr));
      canvas.height = Math.max(1, Math.round(h * dpr));
      baseTile = Math.max(w, h) * 1.6; // tiled star field; wraps for an endless sky
    };
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);
    resize();

    let raf = 0;
    let startT = 0;
    const draw = (now: number) => {
      if (!startT) startT = now;
      const t = (now - startT) / 1000;
      const s = vp.scale.get();
      // World point at the viewport centre — moves with pan, stays put under a
      // cursor-anchored zoom.
      const wcx = (w / 2 - vp.tx.get()) / s;
      const wcy = (h / 2 - vp.ty.get()) / s;
      const offX = -wcx * PARALLAX_PAN;
      const offY = -wcy * PARALLAX_PAN;
      const tile = baseTile * (1 + (s - 1) * ZOOM_PARALLAX);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = "#ffffff";
      for (let i = 0; i < N; i++) {
        const star = STARS[i];
        const b = star[2]; // brightness 0..1
        const tw = 0.5 + 0.5 * Math.sin(t * speed[i] + phase[i]); // 0..1
        const a = Math.min(1, (0.3 + b * 0.95) * tw);
        if (a < 0.04) continue;
        const px = (((star[0] * tile + offX) % tile) + tile) % tile;
        const py = ((((1 - star[1]) * tile + offY) % tile) + tile) % tile; // flip dec → north up
        if (px > w + 3 || py > h + 3) continue;
        const size = b > 0.62 ? 2.4 : b > 0.36 ? 1.6 : 1;
        ctx.globalAlpha = a;
        if (b > 0.64) {
          // Bright stars: sharp core + a small cool glow for crispness.
          ctx.shadowColor = "rgba(170,205,255,0.95)";
          ctx.shadowBlur = 4;
          ctx.fillRect(px - size / 2, py - size / 2, size, size);
          ctx.shadowBlur = 0;
        } else {
          ctx.fillRect(px - size / 2, py - size / 2, size, size);
        }
      }
      ctx.globalAlpha = 1;
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);

    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
    };
  }, [vp]);

  return <canvas ref={ref} className="pointer-events-none absolute inset-0 h-full w-full" aria-hidden />;
}
