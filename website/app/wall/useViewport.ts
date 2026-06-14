"use client";

import { animate, useMotionValue, type AnimationPlaybackControls, type MotionValue } from "framer-motion";
import { useCallback, useEffect, useMemo, useRef } from "react";
import { WORLD_H, WORLD_W, ZOOM_MAX, ZOOM_MIN, FIT_MAX_SCALE } from "@/app/services/wall";

export interface Viewport {
  tx: number;
  ty: number;
  scale: number;
}

export interface WorldRect {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

export interface Insets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const EASE: [number, number, number, number] = [0.22, 1, 0.36, 1];
// Mouse-wheel zoom eases toward a target instead of snapping, reusing Mos' scroll
// transition math (Interpolator.lerp on the remaining gap): each frame closes this
// fraction of the gap, dt-corrected so 60/120Hz feel identical. Higher = snappier.
const ZOOM_SMOOTH = 0.2;
// Parallax depth of the starfield backdrop — it follows the camera at this fraction.
const STAR_DEPTH = 0.12;

// The viewport is a window onto the fixed world (WORLD_W × WORLD_H). It is
// described by a single affine transform `translate(tx,ty) scale(scale)` with
// origin 0,0 applied to the world layer; the screen is an overflow-hidden frame.
//
//   screen = world · scale + t        world = (screen − t) / scale
//
// tx/ty/scale are MotionValues so panning and zooming mutate one transform on
// the GPU without re-rendering the (potentially hundreds of) note components.
export interface UseViewport {
  containerRef: React.RefObject<HTMLDivElement | null>;
  tx: MotionValue<number>;
  ty: MotionValue<number>;
  scale: MotionValue<number>;
  /** Is a left-drag / one-finger pan in progress (1/0) — drives the grab cursor. */
  panning: MotionValue<number>;
  /** Starfield backdrop layer transform (screen-space tiled plane). The Starfield
   *  canvas reads these; they follow the camera attenuated by a far parallax depth. */
  starScale: MotionValue<number>;
  starOffX: MotionValue<number>;
  starOffY: MotionValue<number>;
  /** Container-local screen px → world px. */
  screenToWorld: (sx: number, sy: number) => { x: number; y: number };
  /** World px → container-local screen px. */
  worldToScreen: (wx: number, wy: number) => { x: number; y: number };
  /** The world rectangle currently visible in the viewport (world px). */
  visibleWorldRect: () => WorldRect;
  /** Snap (no animation) to a viewport. */
  setViewport: (v: Viewport) => void;
  /** Ease to a viewport (the "leap"). Returns when started. */
  animateTo: (v: Viewport, opts?: { duration?: number }) => void;
  /** Frame a world rectangle: center it and scale to fit, capped at maxScale and
   *  floored at minReadable (overflow-and-pan rather than shrink text too small). */
  fitToBounds: (b: WorldRect, opts?: { animate?: boolean; insets?: Partial<Insets>; maxScale?: number; padding?: number; minReadable?: number; duration?: number }) => void;
  /** Smoothly zoom by `factor` around the viewport centre (for +/− buttons). */
  zoomBy: (factor: number) => void;
  /** Read the current viewport synchronously. */
  get: () => Viewport;
}

export function useViewport(opts?: {
  /** Called (throttled by rAF) whenever the viewport changes, for URL sync etc. */
  onChange?: (v: Viewport) => void;
  /** Called when the USER moves the camera (wheel / drag-pan / pinch) — NOT on
   *  programmatic moves (animateTo/fit). Lets callers know the camera was touched. */
  onUserInteract?: () => void;
}): UseViewport {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const tx = useMotionValue(0);
  const ty = useMotionValue(0);
  const scale = useMotionValue(1);
  const panning = useMotionValue(0);

  // Starfield backdrop layer — a screen-space tiled plane the canvas Starfield reads.
  // It is its own little camera that follows the notes camera but attenuated by
  // STAR_DEPTH: zoom is anchored at the SAME cursor (so it never slides toward a
  // corner) and pan uses the REAL clamped delta (so when the board can't move, nor
  // can the sky). starOffX/Y are in screen px, starScale multiplies the base tile.
  const starScale = useMotionValue(1);
  const starOffX = useMotionValue(0);
  const starOffY = useMotionValue(0);
  // Zoom the backdrop about (cx,cy) by an attenuated factor, keeping the star under
  // the cursor fixed — identical zoom-about-a-point math as the notes layer.
  const applyStarZoom = useCallback((cx: number, cy: number, f: number) => {
    const fs = 1 + (f - 1) * STAR_DEPTH;
    starScale.set(starScale.get() * fs);
    starOffX.set(cx - (cx - starOffX.get()) * fs);
    starOffY.set(cy - (cy - starOffY.get()) * fs);
  }, [starScale, starOffX, starOffY]);

  const onUserInteractRef = useRef(opts?.onUserInteract);
  useEffect(() => {
    onUserInteractRef.current = opts?.onUserInteract;
  }, [opts?.onUserInteract]);

  const onChangeRef = useRef(opts?.onChange);
  useEffect(() => {
    onChangeRef.current = opts?.onChange;
  }, [opts?.onChange]);

  // In-flight ease controls so a fresh gesture can interrupt the animation.
  const animsRef = useRef<AnimationPlaybackControls[]>([]);
  const stopAnims = useCallback(() => {
    for (const a of animsRef.current) a.stop();
    animsRef.current = [];
  }, []);

  // Mouse-wheel zoom smoother: a target scale the current scale eases toward, a
  // cursor anchor held for the glide, and its rAF handle.
  const zoomTargetRef = useRef<number | null>(null);
  const zoomAnchorRef = useRef({ x: 0, y: 0 });
  const zoomRafRef = useRef(0);
  const zoomLastRef = useRef(0);
  const stopZoom = useCallback(() => {
    zoomTargetRef.current = null;
    if (zoomRafRef.current) {
      cancelAnimationFrame(zoomRafRef.current);
      zoomRafRef.current = 0;
    }
  }, []);

  const size = useCallback(() => {
    const el = containerRef.current;
    return { w: el?.clientWidth ?? 0, h: el?.clientHeight ?? 0 };
  }, []);

  // Pan clamp: a large world may pan until its far edge is `over` past the
  // matching viewport edge; a world smaller than the viewport (zoomed out) is
  // kept loosely centered. Prevents losing the board into empty space.
  // Keep the viewport strictly inside the world: a viewport edge never passes the
  // matching world edge, so the void outside the board is never revealed. With
  // minScale ensuring the world always covers the viewport, the board fully fills
  // the frame at every zoom level.
  const clampPan = useCallback((nx: number, ny: number, s: number) => {
    const { w, h } = size();
    const axis = (t: number, worldLen: number, viewLen: number) => {
      if (!viewLen) return t;
      const gap = viewLen - worldLen; // ≤ 0 once the world covers the viewport
      return clamp(t, Math.min(0, gap), Math.max(0, gap));
    };
    return { x: axis(nx, WORLD_W * s, w), y: axis(ny, WORLD_H * s, h) };
  }, [size]);

  // Floor on zoom so the world always covers the viewport (can't reveal the void
  // around the board). ZOOM_MIN is just an absolute fallback for the unmeasured case.
  const minScale = useCallback(() => {
    const { w, h } = size();
    return w && h ? Math.max(ZOOM_MIN, w / WORLD_W, h / WORLD_H) : ZOOM_MIN;
  }, [size]);

  const notify = useCallback(() => {
    onChangeRef.current?.({ tx: tx.get(), ty: ty.get(), scale: scale.get() });
  }, [tx, ty, scale]);

  const applyPan = useCallback((nx: number, ny: number, s: number) => {
    const c = clampPan(nx, ny, s);
    tx.set(c.x);
    ty.set(c.y);
  }, [clampPan, tx, ty]);

  const panBy = useCallback((dx: number, dy: number) => {
    const x0 = tx.get();
    const y0 = ty.get();
    applyPan(x0 + dx, y0 + dy, scale.get());
    // Drive the backdrop by the REAL (post-clamp) delta, so a pan the board refuses
    // (e.g. at min zoom, world already pinned to the edge) moves the sky by 0 too.
    starOffX.set(starOffX.get() + (tx.get() - x0) * STAR_DEPTH);
    starOffY.set(starOffY.get() + (ty.get() - y0) * STAR_DEPTH);
    notify();
  }, [applyPan, tx, ty, scale, notify, starOffX, starOffY]);

  // Zoom by `factor` keeping the world point under (cx,cy) — container-local px —
  // fixed on screen.
  const zoomAt = useCallback((cx: number, cy: number, factor: number) => {
    const s0 = scale.get();
    const s1 = clamp(s0 * factor, minScale(), ZOOM_MAX);
    const f = s1 / s0;
    if (f === 1) return;
    const nx = cx - (cx - tx.get()) * f;
    const ny = cy - (cy - ty.get()) * f;
    scale.set(s1);
    applyPan(nx, ny, s1);
    applyStarZoom(cx, cy, f);
    notify();
  }, [scale, tx, ty, applyPan, notify, minScale, applyStarZoom]);

  const screenToWorld = useCallback((sx: number, sy: number) => {
    const s = scale.get();
    return { x: (sx - tx.get()) / s, y: (sy - ty.get()) / s };
  }, [scale, tx, ty]);

  const worldToScreen = useCallback((wx: number, wy: number) => {
    const s = scale.get();
    return { x: wx * s + tx.get(), y: wy * s + ty.get() };
  }, [scale, tx, ty]);

  const visibleWorldRect = useCallback((): WorldRect => {
    const { w, h } = size();
    const tl = screenToWorld(0, 0);
    const br = screenToWorld(w, h);
    return { minX: tl.x, minY: tl.y, maxX: br.x, maxY: br.y };
  }, [size, screenToWorld]);

  const get = useCallback((): Viewport => ({ tx: tx.get(), ty: ty.get(), scale: scale.get() }), [tx, ty, scale]);

  // Map an ABSOLUTE notes target (tx1,ty1,s1) to the backdrop's matching target.
  // Programmatic moves (fit / draft-focus / minimap / URL restore) have no cursor,
  // so we model the change as a zoom about the SCREEN CENTRE plus a residual pan —
  // both attenuated by STAR_DEPTH — mirroring the incremental interaction math so the
  // two paths stay consistent. Reads the CURRENT camera as the start, so it must be
  // called BEFORE mutating tx/ty/scale.
  const starTargetFor = useCallback((tx1: number, ty1: number, s1: number) => {
    const { w, h } = size();
    const cx = w / 2;
    const cy = h / 2;
    const s0 = scale.get();
    const f = s0 ? s1 / s0 : 1;
    const fs = 1 + (f - 1) * STAR_DEPTH;
    // 1) zoom the backdrop about the centre to track the scale change…
    const offXmid = cx - (cx - starOffX.get()) * fs;
    const offYmid = cy - (cy - starOffY.get()) * fs;
    // 2) …then attenuated pan for the translation left over after that centre-zoom.
    const txMid = cx - (cx - tx.get()) * f;
    const tyMid = cy - (cy - ty.get()) * f;
    return {
      scale: starScale.get() * fs,
      offX: offXmid + (tx1 - txMid) * STAR_DEPTH,
      offY: offYmid + (ty1 - tyMid) * STAR_DEPTH,
    };
  }, [size, scale, tx, ty, starScale, starOffX, starOffY]);

  const setViewport = useCallback((v: Viewport) => {
    stopAnims();
    stopZoom();
    const s = clamp(v.scale, minScale(), ZOOM_MAX);
    const c = clampPan(v.tx, v.ty, s);
    const st = starTargetFor(c.x, c.y, s); // before mutating the camera
    scale.set(s);
    tx.set(c.x);
    ty.set(c.y);
    starScale.set(st.scale);
    starOffX.set(st.offX);
    starOffY.set(st.offY);
    notify();
  }, [stopAnims, stopZoom, minScale, clampPan, scale, tx, ty, starScale, starOffX, starOffY, starTargetFor, notify]);

  const animateTo = useCallback((v: Viewport, animOpts?: { duration?: number }) => {
    stopAnims();
    stopZoom();
    const s = clamp(v.scale, minScale(), ZOOM_MAX);
    const c = clampPan(v.tx, v.ty, s);
    const st = starTargetFor(c.x, c.y, s); // before the animations start mutating scale
    const duration = animOpts?.duration ?? 0.6;
    animsRef.current = [
      animate(tx, c.x, { duration, ease: EASE }),
      animate(ty, c.y, { duration, ease: EASE }),
      animate(scale, s, { duration, ease: EASE, onUpdate: notify }),
      // Backdrop eases in lockstep so a fit / draft-focus / minimap leap carries the sky too.
      animate(starScale, st.scale, { duration, ease: EASE }),
      animate(starOffX, st.offX, { duration, ease: EASE }),
      animate(starOffY, st.offY, { duration, ease: EASE }),
    ];
  }, [stopAnims, stopZoom, minScale, clampPan, tx, ty, scale, starScale, starOffX, starOffY, starTargetFor, notify]);

  const fitToBounds = useCallback((b: WorldRect, fitOpts?: { animate?: boolean; insets?: Partial<Insets>; maxScale?: number; padding?: number; minReadable?: number; duration?: number }) => {
    const { w, h } = size();
    if (!w || !h) return;
    const ins = { top: 0, right: 0, bottom: 0, left: 0, ...fitOpts?.insets };
    const pad = fitOpts?.padding ?? 80;
    const availW = Math.max(1, w - ins.left - ins.right - 2 * pad);
    const availH = Math.max(1, h - ins.top - ins.bottom - 2 * pad);
    const bw = Math.max(1, b.maxX - b.minX);
    const bh = Math.max(1, b.maxY - b.minY);
    const maxScale = fitOpts?.maxScale ?? FIT_MAX_SCALE;
    // Never fit below a readable floor: better to overflow a sprawling board and let
    // the user pan/use the minimap than to shrink the text to an illegible size.
    const floor = Math.max(minScale(), fitOpts?.minReadable ?? 0);
    const s = clamp(Math.min(availW / bw, availH / bh), floor, Math.max(floor, maxScale));
    // Center the bounds within the inset-adjusted viewport.
    const cx = (b.minX + b.maxX) / 2;
    const cy = (b.minY + b.maxY) / 2;
    const viewCx = ins.left + (w - ins.left - ins.right) / 2;
    const viewCy = ins.top + (h - ins.top - ins.bottom) / 2;
    const targetTx = viewCx - cx * s;
    const targetTy = viewCy - cy * s;
    if (fitOpts?.animate === false) setViewport({ tx: targetTx, ty: targetTy, scale: s });
    else animateTo({ tx: targetTx, ty: targetTy, scale: s }, { duration: fitOpts?.duration });
  }, [size, minScale, setViewport, animateTo]);

  // Smooth zoom step around the viewport centre, for the on-screen +/− buttons.
  const zoomBy = useCallback((factor: number) => {
    const { w, h } = size();
    if (!w || !h) return;
    stopAnims();
    stopZoom();
    const s0 = scale.get();
    const s1 = clamp(s0 * factor, minScale(), ZOOM_MAX);
    const f = s1 / s0;
    if (f === 1) return;
    const cx = w / 2;
    const cy = h / 2;
    const nx = cx - (cx - tx.get()) * f;
    const ny = cy - (cy - ty.get()) * f;
    const c = clampPan(nx, ny, s1);
    // Ease the backdrop in lockstep (attenuated, anchored at the same centre).
    const fs = 1 + (f - 1) * STAR_DEPTH;
    const sOffX = cx - (cx - starOffX.get()) * fs;
    const sOffY = cy - (cy - starOffY.get()) * fs;
    animsRef.current = [
      animate(scale, s1, { duration: 0.25, ease: EASE, onUpdate: notify }),
      animate(tx, c.x, { duration: 0.25, ease: EASE }),
      animate(ty, c.y, { duration: 0.25, ease: EASE }),
      animate(starScale, starScale.get() * fs, { duration: 0.25, ease: EASE }),
      animate(starOffX, sOffX, { duration: 0.25, ease: EASE }),
      animate(starOffY, sOffY, { duration: 0.25, ease: EASE }),
    ];
  }, [size, stopAnims, stopZoom, minScale, scale, tx, ty, clampPan, notify, starScale, starOffX, starOffY]);

  // --- Input: wheel (pan / pinch-zoom) + pointer (drag-pan / two-finger pinch).
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    // Mouse-wheel zoom smoother — local to this effect so its recursive rAF doesn't
    // trip the hooks ref rule. Eases scale toward zoomTargetRef each frame, anchored
    // at the cursor (mirrors Mos' ScrollPoster.processing on the remaining gap).
    const zoomFrame = (now: number) => {
      const dt = clamp((now - zoomLastRef.current) / 1000, 0, 0.05);
      zoomLastRef.current = now;
      const target = zoomTargetRef.current;
      if (target === null) {
        zoomRafRef.current = 0;
        return;
      }
      const cur = scale.get();
      const transDt = 1 - Math.pow(1 - ZOOM_SMOOTH, dt * 60);
      let next = cur + (target - cur) * transDt;
      if (Math.abs(target - next) <= target * 0.0008) {
        next = target;
        zoomTargetRef.current = null;
      }
      const f = next / cur;
      const a = zoomAnchorRef.current;
      scale.set(next);
      applyPan(a.x - (a.x - tx.get()) * f, a.y - (a.y - ty.get()) * f, next);
      applyStarZoom(a.x, a.y, f);
      notify();
      zoomRafRef.current = zoomTargetRef.current !== null ? requestAnimationFrame(zoomFrame) : 0;
    };
    const zoomWheelSmooth = (cx: number, cy: number, factor: number) => {
      const base = zoomTargetRef.current ?? scale.get();
      zoomTargetRef.current = clamp(base * factor, minScale(), ZOOM_MAX);
      zoomAnchorRef.current = { x: cx, y: cy };
      if (!zoomRafRef.current) {
        zoomLastRef.current = performance.now();
        zoomRafRef.current = requestAnimationFrame(zoomFrame);
      }
    };

    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      stopAnims();
      onUserInteractRef.current?.();
      const rect = el.getBoundingClientRect();
      const cx = e.clientX - rect.left;
      const cy = e.clientY - rect.top;
      // Trackpad pinch arrives as ctrl/⌘+wheel → zoom. A plain mouse wheel (no
      // modifier, purely vertical, chunky deltas) also zooms — per product choice,
      // no ctrl needed. A trackpad two-finger scroll (has an x-component or fine
      // pixel deltas) pans, keeping the Figma-style trackpad feel.
      const pinch = e.ctrlKey || e.metaKey;
      const mouseWheel = !pinch && e.deltaX === 0 && (e.deltaMode !== 0 || Math.abs(e.deltaY) >= 30);
      if (pinch) {
        // Trackpad pinch is continuous — track it directly, no inertia smoothing.
        stopZoom();
        zoomAt(cx, cy, Math.exp(-e.deltaY * 0.0125));
      } else if (mouseWheel) {
        // Mouse wheel eases toward an accumulating target for a smooth glide.
        const step = e.deltaMode !== 0 ? e.deltaY * 16 : e.deltaY; // normalize line→px
        zoomWheelSmooth(cx, cy, Math.exp(-step * 0.0018));
      } else {
        stopZoom();
        panBy(-e.deltaX, -e.deltaY);
      }
    };

    // Active pointers for pan / pinch. Mouse uses the same single-pointer path.
    const pts = new Map<number, { x: number; y: number }>();
    let pinch: { dist: number; cx: number; cy: number } | null = null;

    const isNoPan = (target: EventTarget | null) =>
      target instanceof Element && !!target.closest("[data-no-pan]");

    const onPointerDown = (e: PointerEvent) => {
      if (e.pointerType === "mouse" && e.button !== 0) return;
      if (isNoPan(e.target)) return; // tray / compose / interactive widgets handle their own drags
      stopAnims();
      stopZoom();
      onUserInteractRef.current?.();
      pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pts.size === 1) {
        panning.set(1);
        try { el.setPointerCapture(e.pointerId); } catch { /* capture is best-effort */ }
      } else if (pts.size === 2) {
        pinch = pinchState();
        panning.set(0);
      }
    };

    const pinchState = () => {
      const [a, b] = [...pts.values()];
      const rect = el.getBoundingClientRect();
      return {
        dist: Math.hypot(a.x - b.x, a.y - b.y),
        cx: (a.x + b.x) / 2 - rect.left,
        cy: (a.y + b.y) / 2 - rect.top,
      };
    };

    const onPointerMove = (e: PointerEvent) => {
      const p = pts.get(e.pointerId);
      if (!p) return;
      const dx = e.clientX - p.x;
      const dy = e.clientY - p.y;
      p.x = e.clientX;
      p.y = e.clientY;
      if (pts.size >= 2) {
        if (!pinch) return;
        const next = pinchState();
        if (pinch.dist > 0) zoomAt(next.cx, next.cy, next.dist / pinch.dist);
        // Two-finger drag also pans by the midpoint movement.
        panBy(next.cx - pinch.cx, next.cy - pinch.cy);
        pinch = next;
      } else if (pts.size === 1) {
        panBy(dx, dy);
      }
    };

    const endPointer = (e: PointerEvent) => {
      pts.delete(e.pointerId);
      try { el.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
      if (pts.size < 2) pinch = pts.size === 2 ? pinchState() : null;
      if (pts.size === 0) panning.set(0);
      else if (pts.size === 1) { pinch = null; panning.set(1); }
    };

    el.addEventListener("wheel", onWheel, { passive: false });
    el.addEventListener("pointerdown", onPointerDown);
    el.addEventListener("pointermove", onPointerMove);
    el.addEventListener("pointerup", endPointer);
    el.addEventListener("pointercancel", endPointer);
    return () => {
      el.removeEventListener("wheel", onWheel);
      el.removeEventListener("pointerdown", onPointerDown);
      el.removeEventListener("pointermove", onPointerMove);
      el.removeEventListener("pointerup", endPointer);
      el.removeEventListener("pointercancel", endPointer);
      stopZoom();
    };
  }, [stopAnims, stopZoom, zoomAt, panBy, panning, scale, tx, ty, applyPan, notify, minScale, applyStarZoom]);

  return useMemo(
    () => ({
      containerRef,
      tx,
      ty,
      scale,
      panning,
      starScale,
      starOffX,
      starOffY,
      screenToWorld,
      worldToScreen,
      visibleWorldRect,
      setViewport,
      animateTo,
      fitToBounds,
      zoomBy,
      get,
    }),
    [tx, ty, scale, panning, starScale, starOffX, starOffY, screenToWorld, worldToScreen, visibleWorldRect, setViewport, animateTo, fitToBounds, zoomBy, get],
  );
}

/** World bounding box (px) of a set of notes, or null if empty. */
export function notesBounds(notes: ReadonlyArray<{ x: number; y: number }>, noteHalf: number): WorldRect | null {
  if (!notes.length) return null;
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (const n of notes) {
    const wx = n.x * WORLD_W;
    const wy = n.y * WORLD_H;
    if (wx < minX) minX = wx;
    if (wy < minY) minY = wy;
    if (wx > maxX) maxX = wx;
    if (wy > maxY) maxY = wy;
  }
  // Pad by a note half so the framing includes the sticky bodies, not just centers.
  return { minX: minX - noteHalf, minY: minY - noteHalf, maxX: maxX + noteHalf, maxY: maxY + noteHalf };
}
