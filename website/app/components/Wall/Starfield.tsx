"use client";

import { useEffect, useRef } from "react";
import { STARS } from "./stars";
import type { UseViewport } from "@/app/wall/useViewport";

// Tunables exposed by the on-screen star panel so the look can be compared live.
export interface StarfieldConfig {
  /** Real B-V stellar colour (blue-white → yellow → orange-red) vs flat white. */
  color: boolean;
  /** Diffuse glow along the galactic plane (the Milky Way band). */
  milkyWay: boolean;
  /** Magnitude curve contrast. 1 = linear; >1 makes bright stars pop, dims faint ones. */
  gamma: number;
  /** Fraction of the catalogue drawn, 0..1 (1 = all ~28k; lower = brighter stars only). */
  density: number;
}

export const DEFAULT_STAR_CONFIG: StarfieldConfig = { color: true, milkyWay: false, gamma: 0.8, density: 1 };

const CI_MIN = -0.4;
const CI_MAX = 2.0;
const CI_STEPS = 63;

// B-V colour index → RGB. Realistic stellar hues but gently saturated (real stars read
// near-white with a faint tint). One string per quantised index, built once.
function buildPalette(): string[] {
  const stops: [number, number, number, number][] = [
    [-0.4, 162, 192, 255], // hot O/B — blue-white
    [0.0, 202, 220, 255], // A — white with a blue cast
    [0.3, 240, 243, 255], // F — white
    [0.58, 255, 247, 240], // G (sun-like) — warm white
    [0.81, 255, 232, 205], // early K — pale gold
    [1.2, 255, 210, 168], // K — orange
    [1.6, 255, 192, 148], // M — orange-red
    [2.0, 255, 174, 132], // coolest — red
  ];
  const out: string[] = [];
  for (let i = 0; i <= CI_STEPS; i++) {
    const bv = CI_MIN + (i / CI_STEPS) * (CI_MAX - CI_MIN);
    let s = 0;
    while (s < stops.length - 2 && bv > stops[s + 1][0]) s++;
    const [b0, r0, g0, bl0] = stops[s];
    const [b1, r1, g1, bl1] = stops[s + 1];
    const f = Math.max(0, Math.min(1, (bv - b0) / (b1 - b0)));
    out.push(
      `rgb(${Math.round(r0 + (r1 - r0) * f)},${Math.round(g0 + (g1 - g0) * f)},${Math.round(bl0 + (bl1 - bl0) * f)})`,
    );
  }
  return out;
}

// Galactic-plane (b=0) sampled in equatorial coords, matching the star projection
// (x = ra/2π, y = (dec+90)/180). Carries a per-point intensity that peaks toward the
// galactic centre (l≈0, Sagittarius) and fades to the anticentre — like the real band.
function buildGalacticPlane(): { x: number; y: number; w: number }[] {
  const D2R = Math.PI / 180;
  const NGP_dec = 27.128336 * D2R;
  const NGP_ra = 192.859508 * D2R;
  const lNCP = 122.932 * D2R;
  const pts: { x: number; y: number; w: number }[] = [];
  for (let l = 0; l < 360; l += 2.5) {
    const lr = l * D2R;
    const dec = Math.asin(Math.cos(NGP_dec) * Math.cos(lNCP - lr));
    let ra = NGP_ra + Math.atan2(Math.sin(lNCP - lr), -Math.sin(NGP_dec) * Math.cos(lNCP - lr));
    ra = ((ra % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
    const intensity = 0.32 + 0.68 * Math.pow((1 + Math.cos(lr)) / 2, 1.6); // bright at centre
    pts.push({ x: ra / (2 * Math.PI), y: (dec / D2R + 90) / 180, w: intensity });
  }
  return pts;
}

export function Starfield({ vp, config = DEFAULT_STAR_CONFIG }: { vp: UseViewport; config?: StarfieldConfig }) {
  const ref = useRef<HTMLCanvasElement | null>(null);
  // Panel changes flow through this ref so toggling a setting takes effect on the next
  // frame without tearing down the rAF loop / rebuilding the twinkle tables.
  const cfgRef = useRef(config);
  useEffect(() => {
    cfgRef.current = config;
  }, [config]);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d", { desynchronized: true });
    if (!ctx) return;

    const coarse = typeof window !== "undefined" && !!window.matchMedia?.("(pointer: coarse)").matches;
    const STEP = coarse ? 2 : 1; // phones draw a subset of the (now larger) catalogue
    const dprCap = coarse ? 1.5 : 2;

    const palette = buildPalette();
    const plane = buildGalacticPlane();

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
    let prevCfg = cfgRef.current;
    const draw = (now: number) => {
      raf = requestAnimationFrame(draw);
      if (!startT) startT = now;
      const cfg = cfgRef.current;
      const sScale = vp.starScale.get();
      const offX = vp.starOffX.get();
      const offY = vp.starOffY.get();
      // 60fps while interactively panning/zooming; drop to ~30fps when still or during a
      // programmatic ease. A config change also forces a redraw so the panel feels live.
      const moving = offX !== prevOffX || offY !== prevOffY || sScale !== prevScale || cfg !== prevCfg;
      const eased = vp.animating.get() === 1;
      if ((!moving || eased) && now - lastDraw < 32) return;
      lastDraw = now;
      prevOffX = offX;
      prevOffY = offY;
      prevScale = sScale;
      prevCfg = cfg;

      const t = (now - startT) / 1000;
      const tile = baseTile * sScale;
      const useColor = cfg.color;
      const g = cfg.gamma;
      const bMin = (1 - cfg.density) * 0.28; // brightness cutoff = effective magnitude limit

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);

      // --- Milky Way: diffuse glow blobs along the galactic plane (drawn under stars) ---
      if (cfg.milkyWay) {
        const R = tile * 0.055;
        ctx.globalCompositeOperation = "lighter";
        for (let i = 0; i < plane.length; i++) {
          const p = plane[i];
          if (p.w < 0.33) continue; // skip the faint anticentre segments — cheap + realistic
          const mx = (((p.x * tile + offX) % tile) + tile) % tile;
          if (mx < -R || mx > w + R) continue;
          const my = (((p.y * tile + offY) % tile) + tile) % tile;
          if (my < -R || my > h + R) continue;
          const grad = ctx.createRadialGradient(mx, my, 0, mx, my, R);
          const al = 0.035 * p.w; // subtle — the real band is a faint wash, not a ribbon
          grad.addColorStop(0, `rgba(216,214,224,${al})`); // near-neutral, a hair cool
          grad.addColorStop(1, "rgba(216,214,224,0)");
          ctx.fillStyle = grad;
          ctx.fillRect(mx - R, my - R, R * 2, R * 2);
        }
        ctx.globalCompositeOperation = "source-over";
      }

      // --- Stars ---
      if (!useColor) ctx.fillStyle = "#ffffff";
      for (let i = 0; i < N; i += STEP) {
        const star = STARS[i];
        const b = star[2]; // brightness 0..1
        if (b < bMin) continue; // density cutoff (cheap, before the position/twinkle work)
        // Position-cull next (cheap mod): ~75% of stars wrap off-screen each frame.
        const px = (((star[0] * tile + offX) % tile) + tile) % tile;
        if (px > w + 3) continue;
        const py = (((star[1] * tile + offY) % tile) + tile) % tile;
        if (py > h + 3) continue;
        const tw = 0.5 + 0.5 * Math.sin(t * speed[i] + phase[i]); // 0..1
        const bAdj = g === 1 ? b : Math.pow(b, g); // magnitude curve
        const a = Math.min(1, (0.22 + bAdj * 1.05) * tw);
        if (a < 0.04) continue;
        const size = 0.7 + bAdj * 2.6; // continuous: bright → larger
        if (useColor) ctx.fillStyle = palette[star[3]];
        ctx.globalAlpha = a;
        if (bAdj > 0.6) {
          // Bright stars: sharp core + a small glow (tinted to the star in colour mode).
          ctx.shadowColor = useColor ? palette[star[3]] : "rgba(170,205,255,0.95)";
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

  return <canvas ref={ref} className="wall-stars-in pointer-events-none absolute inset-0 h-full w-full" aria-hidden />;
}
