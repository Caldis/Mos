"use client";

import { useEffect, useRef } from "react";
import { STARS } from "./stars";
import type { UseViewport } from "@/app/wall/useViewport";

// The starfield is a far backdrop with its OWN little camera, maintained in
// useViewport as (starScale, starOffX, starOffY). That camera follows the notes
// camera but attenuated by a far parallax depth — zoom anchored at the same cursor,
// pan using the real clamped delta — so we just paint a tiled plane through it:
//
//   px = (star_base · tile + starOffX)  mod  tile ,   tile = baseTile · starScale
//
// It is the page's heaviest per-frame cost, so on phones (where WebKit enforces a
// tight GPU/CPU budget and will kill the tab if a page pegs it) we sample fewer
// stars, render at a lower backing resolution, drop to ~30fps when the camera is
// still, and stop entirely while the page is hidden.
export function Starfield({ vp }: { vp: UseViewport }) {
  const ref = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    // `desynchronized` opts into the low-latency canvas path: the backdrop is
    // decoupled from DOM compositing so its rAF doesn't wait on a frame sync. Any
    // tearing is imperceptible on a twinkling starfield, and unsupported browsers
    // (Safari) silently ignore the hint. `alpha` stays true (black sky shows through).
    const ctx = canvas.getContext("2d", { desynchronized: true });
    if (!ctx) return;

    const coarse = typeof window !== "undefined" && !!window.matchMedia?.("(pointer: coarse)").matches;
    const STEP = coarse ? 3 : 1; // phones draw ~1/3 of the catalogue (still ~3000 stars)
    const dprCap = coarse ? 1.5 : 2;

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
    let baseTile = 1; // screen-space tile at starScale 1 (wraps for an endless sky)
    const resize = () => {
      dpr = Math.min(window.devicePixelRatio || 1, dprCap);
      w = canvas.clientWidth;
      h = canvas.clientHeight;
      canvas.width = Math.max(1, Math.round(w * dpr));
      canvas.height = Math.max(1, Math.round(h * dpr));
      baseTile = Math.max(w, h) * 1.6; // > viewport, so each star shows at most once
    };
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);
    resize();

    let raf = 0;
    let startT = 0;
    let lastDraw = 0;
    let prevOffX = NaN;
    let prevOffY = NaN;
    let prevScale = NaN;
    const draw = (now: number) => {
      raf = requestAnimationFrame(draw);
      if (!startT) startT = now;
      const sScale = vp.starScale.get();
      const offX = vp.starOffX.get();
      const offY = vp.starOffY.get();
      // 60fps while the user is interactively panning/zooming (parallax must track the
      // hand); but a still field only twinkles, AND during a programmatic ease (fit /
      // focus / cancel-return) the user is watching the notes, not the backdrop — both
      // those cases halve to ~30fps to free the main thread. At min zoom the sky has the
      // most visible stars, so this is exactly where the eased re-draws were janking.
      const moving = offX !== prevOffX || offY !== prevOffY || sScale !== prevScale;
      const eased = vp.animating.get() === 1;
      if ((!moving || eased) && now - lastDraw < 32) return;
      lastDraw = now;
      prevOffX = offX;
      prevOffY = offY;
      prevScale = sScale;
      const t = (now - startT) / 1000;
      const tile = baseTile * sScale;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      ctx.fillStyle = "#ffffff";
      for (let i = 0; i < N; i += STEP) {
        const star = STARS[i];
        // Position-cull FIRST (cheap mod). Each frame ~75% of stars wrap off-screen;
        // culling them before the twinkle sin() below skips thousands of sin() calls
        // per frame — pure CPU saving, byte-identical pixels.
        const px = (((star[0] * tile + offX) % tile) + tile) % tile;
        if (px > w + 3) continue; // [w,tile) wraps off-screen
        const py = (((star[1] * tile + offY) % tile) + tile) % tile;
        if (py > h + 3) continue;
        const b = star[2]; // brightness 0..1
        const tw = 0.5 + 0.5 * Math.sin(t * speed[i] + phase[i]); // 0..1
        const a = Math.min(1, (0.3 + b * 0.95) * tw);
        if (a < 0.04) continue;
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
    };
    raf = requestAnimationFrame(draw);

    // Stop the loop entirely when the tab/page is hidden — no point spending the
    // (mobile) GPU/CPU budget or battery on an invisible canvas.
    const onVisibility = () => {
      if (document.hidden) {
        if (raf) {
          cancelAnimationFrame(raf);
          raf = 0;
        }
      } else if (!raf) {
        lastDraw = 0;
        raf = requestAnimationFrame(draw);
      }
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      if (raf) cancelAnimationFrame(raf);
      document.removeEventListener("visibilitychange", onVisibility);
      ro.disconnect();
    };
  }, [vp]);

  return <canvas ref={ref} className="pointer-events-none absolute inset-0 h-full w-full" aria-hidden />;
}
