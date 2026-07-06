// Standalone check for the wall wheel classifier (no test framework in this project).
// Run: node scripts/verify-wheel-gesture.mjs   (Node 24 strips the imported .ts types)
//
// The mouse/trackpad sequences below are REAL traces captured on the target device
// (integer-pixel wheel, peaks ~43; trackpad never exceeds ~3px and sprinkles in deltaX).
// They pin down the 4–7px gap the WHEEL_ZOOM_PX=6 threshold sits in.
import assert from "node:assert/strict";
import {
  createWheelGesture,
  nextWheelMode,
  WHEEL_GESTURE_GAP_MS,
  WHEEL_TICK,
} from "../app/wall/wheelGesture.ts";

const wheel = (deltaY, opts = {}) => ({ deltaX: 0, deltaY, deltaMode: 0, ctrlKey: false, metaKey: false, ...opts });

// REAL trace: one firm mouse flick — momentum ramps up to 43 then decays to 1.
const MOUSE_FLICK = [
  3, 8, 11, 16, 24, 33, 38, 42, 43, 43, 42, 41, 39, 37, 35, 33, 31, 29, 26, 24, 23, 21, 19, 18, 16,
  15, 13, 23, 10, 9, 9, 8, 7, 6, 6, 5, 4, 4, 3, 3, 3, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
];
// REAL trace: trackpad two-finger swipe — tiny deltas, occasional horizontal jitter.
const TRACKPAD = [
  { dy: 1 }, { dy: 1 }, { dy: 2 }, { dy: 2, dx: -2 }, { dy: 2 }, { dy: 3 }, { dy: 2, dx: -2 },
  { dy: 3 }, { dy: 1 }, { dy: 2, dx: -1 }, { dy: 3, dx: -1 }, { dy: 2, dx: -1 }, { dy: 3, dx: -1 },
  { dy: 3, dx: -1 }, { dy: 2 }, { dy: 3, dx: -1 }, { dy: 3, dx: -1 }, { dy: 3 }, { dy: 1 }, { dy: 2 },
  { dy: 3 }, { dy: 2, dx: -2 }, { dy: 2 }, { dy: 2, dx: -2 }, { dy: 2 }, { dy: 2 }, { dy: 2, dx: -2 },
  { dy: 2 }, { dy: 1 }, { dy: 1 }, { dy: 2 }, { dy: 2 }, { dy: 2 }, { dy: 2 }, { dy: 1 },
];

// OLD per-event rule (threshold 30) — to show it splits a real trace.
const legacyMode = (e) =>
  e.deltaX === 0 && (e.deltaMode !== 0 || Math.abs(e.deltaY) >= 30) ? "zoom" : "pan";

let pass = 0;
let fail = 0;
const check = (name, cond) => {
  if (cond) pass++;
  else {
    fail++;
    console.error("  FAIL:", name);
  }
};

const run = (events, gap = 10) => {
  const g = createWheelGesture();
  let t = 1000;
  return events.map((ev) => {
    const m = nextWheelMode(g, typeof ev === "number" ? wheel(ev) : wheel(ev.dy, { deltaX: ev.dx ?? 0 }), t);
    t += gap;
    return m;
  });
};

// 0) BUG repro: the OLD threshold splits even a real flick — head/tail (<30) judged pan
//    while the body (>=30) zooms. The slow scroll lives entirely under 30 → all pan.
{
  const modes = MOUSE_FLICK.map((d) => legacyMode(wheel(d)));
  check("old logic splits a real flick into zoom+pan", modes.includes("zoom") && modes.includes("pan"));
}

// 1) New logic on the real flick: only the first 3px event pans, then it locks to zoom.
{
  const modes = run(MOUSE_FLICK);
  check("real mouse flick locks to zoom after the first step", modes[0] === "pan" && modes.slice(1).every((m) => m === "zoom"));
}

// 2) New logic on the real trackpad swipe: every event pans (never reaches 6px).
{
  const modes = run(TRACKPAD);
  check("real trackpad swipe stays pan throughout", modes.every((m) => m === "pan"));
}

// 3) Slow tick-by-tick, IF each tick peaks at >=6px (isolated bursts, >gap apart): zoom.
{
  const g = createWheelGesture();
  let t = 0;
  const modes = [3, 8, 6, 8, 7].map((d) => { const m = nextWheelMode(g, wheel(d), t); t += 250; return m; });
  check("slow scroll peaking >=6px reads as zoom", modes.includes("zoom"));
}

// 4) Honest limit: if a slow scroll's peak stays <6 (overlaps the trackpad band), it pans.
//    Whether the real device falls here is exactly what the captured slow-scroll trace decides.
{
  const g = createWheelGesture();
  let t = 0;
  const modes = [3, 5, 4, 3].map((d) => { const m = nextWheelMode(g, wheel(d), t); t += 250; return m; });
  check("slow scroll peaking <6px still pans (documents the limit)", modes.every((m) => m === "pan"));
}

// 5) Windows mouse wheel: fixed 100px steps → zoom.
{
  check("windows wheel is zoom", run([100, 100, 100], 50).every((m) => m === "zoom"));
}

// 6) Line-mode wheel (deltaMode=1) → zoom regardless of size.
{
  const g = createWheelGesture();
  check("line-mode wheel is zoom", nextWheelMode(g, wheel(3, { deltaMode: 1 }), 0) === "zoom");
}

// 7) Apple-device tick: exact WHEEL_TICK multiples (even tiny) → zoom (kept for Magic Mouse/trackpad mice).
{
  const g = createWheelGesture();
  check("apple tick multiple is zoom", nextWheelMode(g, wheel(WHEEL_TICK), 0) === "zoom");
}

// 8) Silent gap resets the gesture; a fresh small step starts as pan.
{
  const g = createWheelGesture();
  nextWheelMode(g, wheel(40), 0);
  check("silent gap resets the gesture", nextWheelMode(g, wheel(2), WHEEL_GESTURE_GAP_MS + 10) === "pan");
}

// 9) Pinch: ctrl/⌘+wheel is pinch and ends the wheel gesture (no zoom carry-over).
{
  const g = createWheelGesture();
  nextWheelMode(g, wheel(40), 0);
  check("ctrl+wheel is pinch", nextWheelMode(g, wheel(-5, { ctrlKey: true }), 8) === "pinch");
  check("after pinch, a small delta pans", nextWheelMode(g, wheel(2), 16) === "pan");
}

assert.ok(fail === 0, `${fail} wheel-gesture check(s) failed`);
console.log(`wheel-gesture: ${pass} passed, 0 failed`);
