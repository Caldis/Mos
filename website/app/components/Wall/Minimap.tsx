"use client";

import { motion, useTransform } from "framer-motion";
import { useCallback, useRef } from "react";
import { NOTE_COLORS, WORLD_H, WORLD_W, type WallNote } from "@/app/services/wall";
import type { UseViewport } from "@/app/wall/useViewport";

// Thumbnail of the whole world, bottom-right. Note positions show as colored
// dots; a frame tracks the current viewport (driven by the viewport MotionValues
// via useTransform, so panning/zooming never re-renders this). Click or drag to
// jump the viewport.
const MM_W = 184;
const MM_H = Math.round((MM_W * WORLD_H) / WORLD_W); // keep world aspect ratio
const SCALE = MM_W / WORLD_W; // world px → minimap px

export function Minimap({
  vp,
  notes,
  viewportSize,
}: {
  vp: UseViewport;
  notes: WallNote[];
  viewportSize: { w: number; h: number };
}) {
  const ref = useRef<HTMLDivElement | null>(null);

  // Viewport frame in minimap px. The visible world rect is
  //   x0 = -tx/scale , width = viewportW/scale  →  ×SCALE into minimap space.
  const left = useTransform([vp.tx, vp.scale], ([t, s]: number[]) => (-t / s) * SCALE);
  const top = useTransform([vp.ty, vp.scale], ([t, s]: number[]) => (-t / s) * SCALE);
  const width = useTransform(vp.scale, (s) => (viewportSize.w / s) * SCALE);
  const height = useTransform(vp.scale, (s) => (viewportSize.h / s) * SCALE);

  const jumpTo = useCallback(
    (clientX: number, clientY: number, animate: boolean) => {
      const rect = ref.current?.getBoundingClientRect();
      if (!rect) return;
      const wx = ((clientX - rect.left) / SCALE);
      const wy = ((clientY - rect.top) / SCALE);
      const s = vp.get().scale;
      const target = { tx: viewportSize.w / 2 - wx * s, ty: viewportSize.h / 2 - wy * s, scale: s };
      if (animate) vp.animateTo(target, { duration: 0.4 });
      else vp.setViewport(target);
    },
    [vp, viewportSize.w, viewportSize.h],
  );

  const dragging = useRef(false);
  const onPointerDown = useCallback(
    (e: React.PointerEvent) => {
      e.preventDefault();
      dragging.current = true;
      try { ref.current?.setPointerCapture(e.pointerId); } catch { /* capture is best-effort */ }
      jumpTo(e.clientX, e.clientY, false);
    },
    [jumpTo],
  );
  const onPointerMove = useCallback(
    (e: React.PointerEvent) => {
      if (!dragging.current) return;
      jumpTo(e.clientX, e.clientY, false);
    },
    [jumpTo],
  );
  const onPointerUp = useCallback((e: React.PointerEvent) => {
    dragging.current = false;
    try { ref.current?.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
  }, []);

  return (
    <div className="pointer-events-none absolute bottom-6 right-5 z-40 hidden sm:block">
      <div className="glass ring-accent pointer-events-auto rounded-[14px] p-2 shadow-xl">
        <div
          ref={ref}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
          className="relative cursor-pointer overflow-hidden rounded-[8px]"
          style={{
            width: MM_W,
            height: MM_H,
            background: "radial-gradient(120% 120% at 50% 30%, rgba(255,255,255,0.05), rgba(255,255,255,0.02))",
            boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
            touchAction: "none",
          }}
        >
          {notes.map((n) => (
            <span
              key={n.id}
              aria-hidden
              className="absolute rounded-full"
              style={{
                left: n.x * MM_W,
                top: n.y * MM_H,
                width: 5,
                height: 5,
                marginLeft: -2.5,
                marginTop: -2.5,
                background: NOTE_COLORS[n.color].bg,
                boxShadow: "0 0 0 0.5px rgba(0,0,0,0.25)",
              }}
            />
          ))}

          {/* Current viewport frame */}
          <motion.div
            className="absolute rounded-[3px]"
            style={{
              left,
              top,
              width,
              height,
              border: "1.5px solid rgba(255,255,255,0.85)",
              background: "rgba(255,255,255,0.10)",
              boxShadow: "0 0 0 1px rgba(0,0,0,0.35), 0 2px 8px rgba(0,0,0,0.3)",
            }}
          />
        </div>
      </div>
    </div>
  );
}
