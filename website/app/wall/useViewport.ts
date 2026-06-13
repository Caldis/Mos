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
  /** Frame a world rectangle: center it and scale to fit, capped at maxScale. */
  fitToBounds: (b: WorldRect, opts?: { animate?: boolean; insets?: Partial<Insets>; maxScale?: number; padding?: number }) => void;
  /** Smoothly zoom by `factor` around the viewport centre (for +/− buttons). */
  zoomBy: (factor: number) => void;
  /** Read the current viewport synchronously. */
  get: () => Viewport;
}

export function useViewport(opts?: {
  /** Called (throttled by rAF) whenever the viewport changes, for URL sync etc. */
  onChange?: (v: Viewport) => void;
}): UseViewport {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const tx = useMotionValue(0);
  const ty = useMotionValue(0);
  const scale = useMotionValue(1);
  const panning = useMotionValue(0);

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

  const size = useCallback(() => {
    const el = containerRef.current;
    return { w: el?.clientWidth ?? 0, h: el?.clientHeight ?? 0 };
  }, []);

  // Pan clamp: a large world may pan until its far edge is `over` past the
  // matching viewport edge; a world smaller than the viewport (zoomed out) is
  // kept loosely centered. Prevents losing the board into empty space.
  const clampPan = useCallback((nx: number, ny: number, s: number) => {
    const { w, h } = size();
    const axis = (t: number, worldLen: number, viewLen: number) => {
      if (!viewLen) return t;
      const over = 0.4 * viewLen;
      const a = over; // world's near edge may sit `over` past the viewport's near edge
      const b = viewLen - worldLen - over; // world's far edge, `over` past the far edge
      return clamp(t, Math.min(a, b), Math.max(a, b));
    };
    return { x: axis(nx, WORLD_W * s, w), y: axis(ny, WORLD_H * s, h) };
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
    applyPan(tx.get() + dx, ty.get() + dy, scale.get());
    notify();
  }, [applyPan, tx, ty, scale, notify]);

  // Zoom by `factor` keeping the world point under (cx,cy) — container-local px —
  // fixed on screen.
  const zoomAt = useCallback((cx: number, cy: number, factor: number) => {
    const s0 = scale.get();
    const s1 = clamp(s0 * factor, ZOOM_MIN, ZOOM_MAX);
    const f = s1 / s0;
    if (f === 1) return;
    const nx = cx - (cx - tx.get()) * f;
    const ny = cy - (cy - ty.get()) * f;
    scale.set(s1);
    applyPan(nx, ny, s1);
    notify();
  }, [scale, tx, ty, applyPan, notify]);

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

  const setViewport = useCallback((v: Viewport) => {
    stopAnims();
    const s = clamp(v.scale, ZOOM_MIN, ZOOM_MAX);
    scale.set(s);
    applyPan(v.tx, v.ty, s);
    notify();
  }, [stopAnims, scale, applyPan, notify]);

  const animateTo = useCallback((v: Viewport, animOpts?: { duration?: number }) => {
    stopAnims();
    const s = clamp(v.scale, ZOOM_MIN, ZOOM_MAX);
    const c = clampPan(v.tx, v.ty, s);
    const duration = animOpts?.duration ?? 0.6;
    animsRef.current = [
      animate(tx, c.x, { duration, ease: EASE }),
      animate(ty, c.y, { duration, ease: EASE }),
      animate(scale, s, { duration, ease: EASE, onUpdate: notify }),
    ];
  }, [stopAnims, clampPan, tx, ty, scale, notify]);

  const fitToBounds = useCallback((b: WorldRect, fitOpts?: { animate?: boolean; insets?: Partial<Insets>; maxScale?: number; padding?: number }) => {
    const { w, h } = size();
    if (!w || !h) return;
    const ins = { top: 0, right: 0, bottom: 0, left: 0, ...fitOpts?.insets };
    const pad = fitOpts?.padding ?? 80;
    const availW = Math.max(1, w - ins.left - ins.right - 2 * pad);
    const availH = Math.max(1, h - ins.top - ins.bottom - 2 * pad);
    const bw = Math.max(1, b.maxX - b.minX);
    const bh = Math.max(1, b.maxY - b.minY);
    const maxScale = fitOpts?.maxScale ?? FIT_MAX_SCALE;
    const s = clamp(Math.min(availW / bw, availH / bh), ZOOM_MIN, maxScale);
    // Center the bounds within the inset-adjusted viewport.
    const cx = (b.minX + b.maxX) / 2;
    const cy = (b.minY + b.maxY) / 2;
    const viewCx = ins.left + (w - ins.left - ins.right) / 2;
    const viewCy = ins.top + (h - ins.top - ins.bottom) / 2;
    const targetTx = viewCx - cx * s;
    const targetTy = viewCy - cy * s;
    if (fitOpts?.animate === false) setViewport({ tx: targetTx, ty: targetTy, scale: s });
    else animateTo({ tx: targetTx, ty: targetTy, scale: s });
  }, [size, setViewport, animateTo]);

  // Smooth zoom step around the viewport centre, for the on-screen +/− buttons.
  const zoomBy = useCallback((factor: number) => {
    const { w, h } = size();
    if (!w || !h) return;
    stopAnims();
    const s0 = scale.get();
    const s1 = clamp(s0 * factor, ZOOM_MIN, ZOOM_MAX);
    const f = s1 / s0;
    if (f === 1) return;
    const cx = w / 2;
    const cy = h / 2;
    const nx = cx - (cx - tx.get()) * f;
    const ny = cy - (cy - ty.get()) * f;
    const c = clampPan(nx, ny, s1);
    animsRef.current = [
      animate(scale, s1, { duration: 0.25, ease: EASE, onUpdate: notify }),
      animate(tx, c.x, { duration: 0.25, ease: EASE }),
      animate(ty, c.y, { duration: 0.25, ease: EASE }),
    ];
  }, [size, stopAnims, scale, tx, ty, clampPan, notify]);

  // --- Input: wheel (pan / pinch-zoom) + pointer (drag-pan / two-finger pinch).
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      stopAnims();
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
        zoomAt(cx, cy, Math.exp(-e.deltaY * 0.0125));
      } else if (mouseWheel) {
        const step = e.deltaMode !== 0 ? e.deltaY * 16 : e.deltaY; // normalize line→px
        zoomAt(cx, cy, Math.exp(-step * 0.0018));
      } else {
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
    };
  }, [stopAnims, zoomAt, panBy, panning]);

  return useMemo(
    () => ({
      containerRef,
      tx,
      ty,
      scale,
      panning,
      screenToWorld,
      worldToScreen,
      visibleWorldRect,
      setViewport,
      animateTo,
      fitToBounds,
      zoomBy,
      get,
    }),
    [tx, ty, scale, panning, screenToWorld, worldToScreen, visibleWorldRect, setViewport, animateTo, fitToBounds, zoomBy, get],
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
