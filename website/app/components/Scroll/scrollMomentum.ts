"use client";

import { useEffect, useRef } from "react";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";

/**
 * A single shared rAF loop that measures the *velocity* of the page scroll
 * (how hard you flick the wheel) rather than its position, and lets it decay
 * along an ease-out curve once you stop — exactly the behaviour Mos gives a
 * mouse wheel, surfaced as the website's signature motion.
 *
 * One loop, many subscribers: consumers paint directly to the DOM/SVG inside
 * the listener instead of triggering a React render 60×/second.
 */

export type Momentum = {
  /** 0..1 — how energetic the current scroll is (rises fast, settles slowly). */
  momentum: number;
  /** -1..1 — signed direction/intensity, for "which way + how hard". */
  velocity: number;
};

// Saturation point: a px/frame delta at/above this reads as a full-energy flick.
const FLICK = 52;
// Per-frame multiplicative decay of momentum (~0.6s settle to rest at 60fps).
const DECAY = 0.94;

const state: Momentum = { momentum: 0, velocity: 0 };
const listeners = new Set<() => void>();

let lastY = 0;
let raf: number | null = null;
let started = false;

// The rAF loop only *decays* the energy and repaints — the energy itself is
// injected from the scroll event, where consecutive deltas are always real
// (so even a single flick from rest registers immediately).
function frame() {
  for (const l of listeners) l();

  state.momentum *= DECAY;
  state.velocity *= 0.85;
  if (state.momentum < 0.001) state.momentum = 0;
  if (Math.abs(state.velocity) < 0.0008) state.velocity = 0;

  if (state.momentum > 0 || state.velocity !== 0) {
    raf = window.requestAnimationFrame(frame);
  } else {
    raf = null;
    for (const l of listeners) l(); // settle to an exact rest pose
  }
}

function kick() {
  if (raf == null && !document.hidden) {
    raf = window.requestAnimationFrame(frame);
  }
}

function onScroll() {
  const y = window.scrollY;
  const dy = y - lastY;
  lastY = y;

  const instant = Math.min(1, Math.abs(dy) / FLICK);
  state.momentum = Math.max(state.momentum, instant);
  // Signed direction/intensity — used to "whip" the dividers as you flick.
  state.velocity = clamp(state.velocity * 0.5 + (dy / FLICK) * 0.5, -1, 1);

  kick();
}

function ensureStarted() {
  if (started) return;
  started = true;
  lastY = window.scrollY;
  window.addEventListener("scroll", onScroll, { passive: true });
}

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

/**
 * Subscribe to the shared momentum loop. `onFrame` is called every animation
 * frame with the latest momentum — read it and paint imperatively. When the
 * user prefers reduced motion the engine never starts and `onFrame` is called
 * once with a frozen resting value so the UI can render a static pose.
 */
export function useScrollMomentumFrame(onFrame: (m: Momentum) => void) {
  const cb = useRef(onFrame);
  // Keep the latest callback without touching the ref during render.
  useEffect(() => {
    cb.current = onFrame;
  });
  const reduced = useHydratedReducedMotion();

  useEffect(() => {
    if (reduced) {
      cb.current({ momentum: 0, velocity: 0 });
      return;
    }

    ensureStarted();
    const listener = () => cb.current(state);
    listeners.add(listener);
    // Paint an initial frame so the instrument isn't blank before first scroll.
    listener();

    return () => {
      listeners.delete(listener);
    };
  }, [reduced]);
}
