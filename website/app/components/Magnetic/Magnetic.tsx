"use client";

import { ReactNode, useEffect, useRef } from "react";

export function Magnetic({
  children,
  strength = 16,
  className = "",
}: {
  children: ReactNode;
  strength?: number;
  className?: string;
}) {
  const rootRef = useRef<HTMLDivElement | null>(null);
  const innerRef = useRef<HTMLDivElement | null>(null);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const root = rootRef.current;
    const inner = innerRef.current;
    if (!root || !inner) return;

    const fine = window.matchMedia?.("(any-pointer: fine)")?.matches ?? false;
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;
    if (!fine || reduced) return;

    let x = 0;
    let y = 0;
    let tx = 0;
    let ty = 0;

    const clamp = (n: number, min: number, max: number) => Math.min(max, Math.max(min, n));

    // The rAF loop only runs while the offset is actually settling — an idle
    // magnet (pointer elsewhere, x/y at rest) costs nothing. It used to run
    // unconditionally, which meant a style write + recalc every frame, forever,
    // for every Magnetic on the page.
    const tick = () => {
      x += (tx - x) * 0.18;
      y += (ty - y) * 0.18;
      if (Math.abs(tx - x) < 0.05 && Math.abs(ty - y) < 0.05) {
        x = tx;
        y = ty;
        rafRef.current = null;
      } else {
        rafRef.current = window.requestAnimationFrame(tick);
      }
      inner.style.transform = `translate3d(${x}px, ${y}px, 0)`;
    };
    const wake = () => {
      if (rafRef.current === null) rafRef.current = window.requestAnimationFrame(tick);
    };

    const onMove = (event: PointerEvent) => {
      const rect = root.getBoundingClientRect();
      const dx = event.clientX - (rect.left + rect.width / 2);
      const dy = event.clientY - (rect.top + rect.height / 2);

      const nx = dx / Math.max(1, rect.width / 2);
      const ny = dy / Math.max(1, rect.height / 2);

      tx = clamp(nx, -1, 1) * strength;
      ty = clamp(ny, -1, 1) * strength;
      wake();
    };

    const onLeave = () => {
      tx = 0;
      ty = 0;
      wake();
    };

    root.addEventListener("pointermove", onMove, { passive: true });
    root.addEventListener("pointerleave", onLeave, { passive: true });

    return () => {
      if (rafRef.current) window.cancelAnimationFrame(rafRef.current);
      root.removeEventListener("pointermove", onMove);
      root.removeEventListener("pointerleave", onLeave);
      inner.style.transform = "translate3d(0, 0, 0)";
    };
  }, [strength]);

  return (
    <div ref={rootRef} className={`inline-block ${className}`}>
      <div ref={innerRef} style={{ willChange: "transform" }}>
        {children}
      </div>
    </div>
  );
}

