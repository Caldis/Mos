/**
 * Wall wheel-input classifier — the single source of truth for "is this wheel event a
 * mouse-wheel zoom, a trackpad pan, or a pinch?", plus every tunable that shapes the
 * wheel → camera mapping. Pure and side-effect-free: useViewport.ts calls
 * nextWheelMode() and reads the rate constants, but owns no classification logic of its
 * own. Tests: scripts/verify-wheel-gesture.mjs  (run: `npm run check:wheel`).
 *
 * ── WHY THIS IS HARD ────────────────────────────────────────────────────────────────
 * The browser exposes no device type. A physical mouse wheel and a trackpad two-finger
 * scroll arrive as byte-identical `wheel` events — no field says which. (W3C has debated
 * adding one since 2018; still unresolved — see SOURCES.) So we must guess from event
 * shape. Pinch is the one freebie: browsers fake `ctrlKey: true` on a trackpad pinch, an
 * industry-wide convention since IE10.
 *
 * ── HOW THE INDUSTRY SPLITS ─────────────────────────────────────────────────────────
 *   • Figma / tldraw / Excalidraw → AVOID it: bare wheel = pan, modifier = zoom, so they
 *     never need to tell mouse from trackpad. (tldraw closed the "zoom with mouse, pan
 *     with trackpad" request as not-planned — "they send the same events".)
 *   • Google Maps / Mapbox        → SOLVE it with a multi-signal heuristic: tick-grid
 *     step, |timeDelta × delta| product, deltaX presence, and per-gesture device memory.
 *     Better than any single threshold, still not 100%.
 * Wall keeps bare-wheel = zoom (it's a glance-and-go board, not a daily-driver tool),
 * so we follow the Google/Mapbox path and discriminate instead of avoiding.
 *
 * ── HOW WE DISCRIMINATE (per GESTURE, not per event) ────────────────────────────────
 * Events spaced under WHEEL_GESTURE_GAP_MS are one gesture. Within it, the first
 * "mouse-wheel signal" LOCKS the gesture to zoom (an absorbing state) so the rest of the
 * stream can't flip it back to pan. A mouse-wheel signal is: purely vertical
 * (deltaX === 0) AND one of —
 *   1. line-mode      (deltaMode ≠ 0, old mice);
 *   2. a chunky step  (|deltaY| ≥ WHEEL_ZOOM_PX);
 *   3. a tick multiple (deltaY is an exact WHEEL_TICK multiple — Apple devices, any size).
 * Everything else is pan (trackpad swipe / diagonal scroll).
 *
 * ── RESEARCH LOG (why the numbers are what they are) ────────────────────────────────
 *   1. macOS applies scroll-acceleration + momentum: one wheel notch fans out into a
 *      stream whose deltaY spikes then decays. A PER-EVENT threshold zoomed the spike and
 *      PANNED the decaying tail → one flick both zoomed and drifted. Fix: classify per
 *      gesture and lock to zoom (absorbing). [Pavel Fatin; mappedin]
 *   2. A SLOW tick-by-tick scroll keeps every step under the original 30px bar → the
 *      whole gesture read as pan. Fix: drop the bar to 6px (WHEEL_ZOOM_PX).
 *   3. Real device trace on the target mouse: deltaY is INTEGER (3,8,11,…,43 peak), NOT
 *      on Apple's 4.000244 tick grid — so signal #3 never fires for it; the 6px bar is
 *      what rescues its slow scroll. The trackpad trace never exceeds 3px and sprinkles
 *      in deltaX. Event frequency (dt 6–15ms) was identical for both, so timing alone
 *      can't separate them on this hardware — magnitude does:
 *        mouse    ⊂ { deltaX 0, ramps past 8px, peaks high }
 *        trackpad ⊂ { ≤3px, occasional deltaX }
 *
 * ── TUNABLES (all of them, defined just below) ──────────────────────────────────────
 *   WHEEL_GESTURE_GAP_MS  120     gesture boundary; raise to bridge slower streams.
 *   WHEEL_ZOOM_PX         6       mouse/trackpad split; sits in the empty 4–7px gap of
 *                                 the trace. Lower if a slow scroll still pans (mind the
 *                                 trackpad's ~3px ceiling); raise if a hard trackpad
 *                                 swipe gets mistaken for zoom.
 *   WHEEL_TICK            4.000244…  Apple wheel/trackpad-mouse tick step (Mapbox's const).
 *   WHEEL_ZOOM_RATE       0.0018  mouse-wheel zoom sensitivity, factor = exp(-stepPx*rate).
 *   WHEEL_PINCH_RATE      0.0125  trackpad-pinch zoom sensitivity, factor = exp(-deltaY*rate).
 *   WHEEL_LINE_TO_PX      16      deltaMode line → px normalisation.
 *
 * ── KNOWN LIMIT ─────────────────────────────────────────────────────────────────────
 * If a mouse's slow scroll has NO spike (a steady ≤5px creep) it overlaps the trackpad
 * band and is indistinguishable on this device — the magnitude split needs the wheel's
 * characteristic "kick". That ambiguity is the exact reason Figma chose the modifier
 * route. A hard trackpad swipe exceeding WHEEL_ZOOM_PX would also misread as zoom (not
 * seen in the trace; its deltaX usually trips the pan default first).
 *
 * ── SOURCES ─────────────────────────────────────────────────────────────────────────
 *   Mapbox scroll_zoom.js   https://github.com/mapbox/mapbox-gl-js/blob/v1.13.0/src/ui/handler/scroll_zoom.js
 *   mappedin "…can't be perfect"  https://www.mappedin.com/resources/blog/why-panning-and-zooming-in-a-web-app-cant-be-perfect/
 *   W3C uievents #337 (no device API)  https://github.com/w3c/uievents/issues/337
 *   Pavel Fatin "Scrolling with pleasure"  https://pavelfatin.com/scrolling-with-pleasure/
 */

// ── Tunables ─────────────────────────────────────────────────────────────────────────
// Full rationale, calibration trace, and sources are in the header block above.

/** Events spaced under this many ms count as one continuous gesture. */
export const WHEEL_GESTURE_GAP_MS = 120;

/** |deltaY| (px) that marks a mouse wheel and locks the gesture to zoom. Sits in the
 *  empty 4–7px gap between the trackpad's ~3px ceiling and the wheel's ~8px+ reach. */
export const WHEEL_ZOOM_PX = 6;

/** Apple devices deliver wheel deltas as exact multiples of this, so even a tiny slow
 *  step stays on the grid and reads as a wheel. Integer-delta mice never hit it and
 *  fall back to WHEEL_ZOOM_PX. */
export const WHEEL_TICK = 4.000244140625;

/** Mouse-wheel zoom sensitivity: zoom factor = exp(-stepPx * rate). */
export const WHEEL_ZOOM_RATE = 0.0018;

/** Trackpad-pinch zoom sensitivity: zoom factor = exp(-deltaY * rate). */
export const WHEEL_PINCH_RATE = 0.0125;

/** deltaMode line → px normalisation (one scrolled "line" ≈ this many px). */
export const WHEEL_LINE_TO_PX = 16;

// ── Types ────────────────────────────────────────────────────────────────────────────

export type WheelMode = "pan" | "zoom" | "pinch";

export interface WheelGestureState {
  /** Mode decided for the in-flight gesture; "idle" = not yet decided (gesture start). */
  mode: "idle" | "pan" | "zoom";
  /** Timestamp (ms) of the previous wheel event, to split gestures by a silent gap. */
  last: number;
}

/** The subset of WheelEvent the classifier reads — keeps it unit-testable in plain Node. */
export interface WheelLike {
  deltaX: number;
  deltaY: number;
  deltaMode: number;
  ctrlKey: boolean;
  metaKey: boolean;
}

// ── Pure classifier ──────────────────────────────────────────────────────────────────

export function createWheelGesture(): WheelGestureState {
  return { mode: "idle", last: 0 };
}

/**
 * Advance the gesture state machine for one wheel event and return what to do
 * ("pinch" | "zoom" | "pan"). See the header block for the full rationale.
 * `now` is a monotonic ms timestamp (performance.now()). State is mutated in place.
 */
export function nextWheelMode(g: WheelGestureState, e: WheelLike, now: number): WheelMode {
  if (e.ctrlKey || e.metaKey) {
    g.mode = "idle"; // a pinch is its own gesture — don't carry wheel state across it
    g.last = now;
    return "pinch";
  }
  if (now - g.last >= WHEEL_GESTURE_GAP_MS) g.mode = "idle";
  g.last = now;

  const zoomSignal =
    e.deltaX === 0 &&
    (e.deltaMode !== 0 || // line-mode (old mice)
      Math.abs(e.deltaY) >= WHEEL_ZOOM_PX || // chunky step (normal/fast scroll)
      (e.deltaY !== 0 && e.deltaY % WHEEL_TICK === 0)); // Apple tick multiple (any size)
  if (zoomSignal) g.mode = "zoom"; // absorbing: stays zoom until the gesture ends
  else if (g.mode === "idle") g.mode = "pan";
  return g.mode;
}
