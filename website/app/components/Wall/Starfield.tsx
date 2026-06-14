"use client";

import { useEffect, useRef } from "react";
import { STARS } from "./stars";
import type { UseViewport } from "@/app/wall/useViewport";

// The starfield is a single far plane behind the notes, driven by the SAME camera
// (tx/ty/scale) but at a great distance, so its motion and zoom are attenuated by
// DEPTH. Because it reads the real, already-clamped transform, when the board
// can't pan or zoom (e.g. at min zoom the world fills the viewport and tx/ty are
// pinned) the sky can't either — no special cases, no accumulators.
const DEPTH = 0.12; // backdrop follows the camera at 12% (a far parallax layer)

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
      // Far-plane camera = notes camera, attenuated by DEPTH. Reads the REAL
      // (clamped) transform, so pan/zoom that the notes can't do, the sky can't either.
      const s = vp.scale.get();
      const starScale = 1 + (s - 1) * DEPTH; // zoom attenuated
      const offX = vp.tx.get() * DEPTH; // pan attenuated
      const offY = vp.ty.get() * DEPTH;
      const tile = baseTile * starScale;
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
