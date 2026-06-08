"use client";

import {
  AnimatePresence,
  motion,
  useMotionValue,
  useSpring,
  useTransform,
  useVelocity,
} from "framer-motion";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { StickyNote } from "@/app/components/Wall/StickyNote";
import { WALL_TURNSTILE_ENABLED } from "@/app/components/Wall/TurnstileWidget";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";
import { useWallAdmin } from "@/app/hooks/useWallAdmin";
import { useI18n } from "@/app/i18n/context";
import { format } from "@/app/i18n/format";
import {
  NOTE_COLOR_KEYS,
  NOTE_COLORS,
  NOTE_SIZE,
  canvasPadFor,
  clampToSafeArea,
  deleteNote,
  noteSizeFor,
  postNote,
  safeArea,
  sparsestSpot,
  useWallNotes,
  type NoteColor,
} from "@/app/services/wall";

interface Draft {
  id: string;
  name: string;
  body: string;
  color: NoteColor;
  x: number;
  y: number;
  // Display-only tilt for the compose preview. NOT sent to the server — placed
  // notes derive their rotation from their id (rotFromId).
  rot: number;
  createdAt: number;
  // Always false for a draft; present only so a Draft satisfies WallNote when
  // passed to <StickyNote note=…>. (`mine` matters only for placed notes.)
  mine: boolean;
}

const HALF = NOTE_SIZE / 2;
function randRot(): number {
  return Math.round((Math.random() * 8 - 4) * 10) / 10;
}
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export function WallClient() {
  const { t } = useI18n();
  const { admin } = useWallAdmin();
  const { data: notes, mutate, isLoading } = useWallNotes();
  const canvasRef = useRef<HTMLDivElement | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [ghostColor, setGhostColor] = useState<NoteColor | null>(null);
  const [submitting, setSubmitting] = useState(false);
  // Turnstile token for the current draft (empty until the challenge passes).
  // When Turnstile is disabled there's no widget, so we treat the draft as
  // pre-verified to keep dev / local-seed mode working.
  const [turnstileToken, setTurnstileToken] = useState("");
  const verified = !WALL_TURNSTILE_ENABLED || turnstileToken.length > 0;
  // User-facing error surfaced near the compose buttons (cleared on retry/cancel).
  const [postError, setPostError] = useState<string | null>(null);
  const [canvasSize, setCanvasSize] = useState({ w: 0, h: 0 });
  const dragRef = useRef<{ startX: number; startY: number; color: NoteColor; moved: boolean } | null>(
    null
  );
  const ghostBaseRot = useRef(0);

  // Ghost (sticky following the pointer while dragging from the tray) shares
  // the same velocity → spring → tilt physics as a placed note.
  const ghostX = useMotionValue(0);
  const ghostY = useMotionValue(0);
  const ghostVel = useVelocity(ghostX);
  const ghostSmoothVel = useSpring(ghostVel, { stiffness: 170, damping: 40, mass: 0.7 });
  const ghostTilt = useTransform(ghostSmoothVel, [-1800, 0, 1800], [-12, 0, 12], { clamp: true });
  const ghostRotate = useTransform(ghostTilt, (t) => ghostBaseRot.current + t);

  useLayoutEffect(() => {
    const el = canvasRef.current;
    if (!el) return;
    const measure = () => setCanvasSize({ w: el.clientWidth, h: el.clientHeight });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const beginDraft = useCallback(
    (nx: number, ny: number, color: NoteColor, rot: number) => {
      const { w, h } = canvasSize;
      let x: number;
      let y: number;
      if (w && h) {
        // Snap the drop point into the shared safe area so a placed note always
        // clears the header/tray/edges, however it was placed.
        const p = clampToSafeArea(nx * w, ny * h, safeArea(w, h, canvasPadFor(w), HALF));
        x = p.x / w;
        y = p.y / h;
      } else {
        x = clamp(nx, 0.12, 0.88);
        y = clamp(ny, 0.14, 0.8);
      }
      setDraft({ id: "draft", name: "", body: "", color, x, y, rot, createdAt: Date.now(), mine: false });
    },
    [canvasSize]
  );

  const onPointerMove = useCallback(
    (e: PointerEvent) => {
      const d = dragRef.current;
      if (!d) return;
      if (!d.moved && Math.hypot(e.clientX - d.startX, e.clientY - d.startY) > 6) d.moved = true;
      if (d.moved) {
        // Pin the ghost inside the SAME safe area as the in-canvas draft drag, so
        // a note dragged out of the tray is blocked from the header/tray/edges too
        // — not just clamped on drop. Outside the canvas it simply pins to the
        // nearest edge (releasing there still cancels, via the inside check below).
        const el = canvasRef.current;
        if (el) {
          const rect = el.getBoundingClientRect();
          const a = safeArea(rect.width, rect.height, canvasPadFor(rect.width), HALF);
          // Top and side chrome are hard walls — the ghost is blocked from the
          // header and page edges exactly like the in-canvas draft drag. The
          // bottom is NOT a wall, because the ghost is dragged UP out of the tray;
          // clamping it to the tray line would yank it off the cursor at grab
          // time. It tracks the finger down to the screen edge, and the drop
          // (beginDraft) still snaps the placed note above the tray.
          const gx = clamp(e.clientX - rect.left, a.minX, a.maxX);
          const gy = clamp(e.clientY - rect.top, a.minY, rect.height - HALF);
          ghostX.set(rect.left + gx);
          ghostY.set(rect.top + gy);
        } else {
          ghostX.set(e.clientX);
          ghostY.set(e.clientY);
        }
        setGhostColor((c) => c ?? d.color);
      }
    },
    [ghostX, ghostY]
  );

  const onPointerUp = useCallback(
    (e: PointerEvent) => {
      window.removeEventListener("pointermove", onPointerMove);
      const d = dragRef.current;
      dragRef.current = null;
      setGhostColor(null);
      if (!d) return;
      const el = canvasRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      // Land at the ghost's current angle (base + release-inertia) for continuity.
      const rot = ghostBaseRot.current + ghostTilt.get();
      const inside =
        e.clientX >= rect.left &&
        e.clientX <= rect.right &&
        e.clientY >= rect.top &&
        e.clientY <= rect.bottom;
      if (d.moved) {
        if (inside) {
          beginDraft((e.clientX - rect.left) / rect.width, (e.clientY - rect.top) / rect.height, d.color, rot);
        }
      } else {
        // No drag — a plain click. Drop into the emptiest spot on the wall rather
        // than always stacking on the page center.
        const spot = sparsestSpot(notes ?? [], rect.width, rect.height, canvasPadFor(rect.width), HALF);
        beginDraft(spot.x, spot.y, d.color, ghostBaseRot.current);
      }
    },
    [beginDraft, onPointerMove, ghostTilt, notes]
  );

  const startTrayDrag = useCallback(
    (e: React.PointerEvent, color: NoteColor) => {
      if (draft) return;
      e.preventDefault();
      ghostBaseRot.current = randRot();
      ghostX.set(e.clientX);
      ghostY.set(e.clientY);
      dragRef.current = { startX: e.clientX, startY: e.clientY, color, moved: false };
      window.addEventListener("pointermove", onPointerMove);
      window.addEventListener("pointerup", onPointerUp, { once: true });
    },
    [draft, onPointerMove, onPointerUp, ghostX, ghostY]
  );

  useEffect(() => () => window.removeEventListener("pointermove", onPointerMove), [onPointerMove]);

  // Map a thrown error message (the Worker's `error` reason) → friendly copy.
  const friendlyError = useCallback(
    (message: string): string => {
      switch (message) {
        case "rate limited":
          return t.wall.errorRate;
        case "turnstile failed":
        case "missing turnstile token":
          return t.wall.errorTurnstile;
        case "no links":
          return t.wall.errorLinks;
        case "spam":
          return t.wall.errorSpam;
        default:
          return t.wall.errorGeneric;
      }
    },
    [t]
  );

  const confirmDraft = useCallback(async () => {
    if (!draft || !draft.body.trim()) return;
    setSubmitting(true);
    setPostError(null);
    try {
      const created = await postNote({
        name: draft.name.trim(),
        body: draft.body.trim(),
        color: draft.color,
        x: draft.x,
        y: draft.y,
        // Position-tilt (rot) is no longer sent — derived from id server-side.
        turnstileToken: turnstileToken || undefined,
      });
      // `created.mine` is true; the server is the source of truth for ownership.
      await mutate((cur) => [...(cur ?? []), created], { revalidate: false });
      setDraft(null);
      setTurnstileToken("");
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      setPostError(friendlyError(message));
      // The token (if any) was consumed by the failed attempt; force a re-verify.
      setTurnstileToken("");
    } finally {
      setSubmitting(false);
    }
  }, [draft, mutate, turnstileToken, friendlyError]);

  const cancelDraft = useCallback(() => {
    setDraft(null);
    setPostError(null);
    setTurnstileToken("");
  }, []);

  const moveDraft = useCallback((nx: number, ny: number) => {
    setDraft((d) => (d ? { ...d, x: nx, y: ny } : d));
  }, []);

  // Soft-delete a note (your own, or — in admin mode — any note; deleteNote
  // attaches the admin token and the Worker enforces which is allowed).
  // Optimistically drop it from the canvas; revalidate from the server on failure.
  const removeNote = useCallback(
    (id: string) => {
      mutate((cur) => (cur ?? []).filter((n) => n.id !== id), { revalidate: false });
      deleteNote(id).catch(() => mutate());
    },
    [mutate],
  );

  // Placed notes shrink to fit more on a narrow (phone) canvas; the compose draft
  // stays full size (NOTE_SIZE). Insets tighten on phones too (see canvasPadFor).
  const noteSize = noteSizeFor(canvasSize.w);
  const pad = canvasPadFor(canvasSize.w);

  return (
    <div className="relative h-full w-full select-none overflow-hidden">
      <div ref={canvasRef} className="wall-grid absolute inset-0">
        <AnimatePresence>
          {canvasSize.w > 0 &&
            // Every placed note shares one low z-index (see StickyNote), so paint
            // order is decided by DOM order. Render oldest → newest so the most
            // recently posted sticky lands on top, like freshly stuck paper —
            // regardless of the order the API returns them in.
            [...(notes ?? [])]
              .sort((a, b) => a.createdAt - b.createdAt)
              .map((n, i) => (
                <StickyNote
                  key={n.id}
                  note={n}
                  index={i}
                  mine={n.mine}
                  admin={admin}
                  size={noteSize}
                  canvasW={canvasSize.w}
                  canvasH={canvasSize.h}
                  onDelete={removeNote}
                />
              ))}
        </AnimatePresence>

        <AnimatePresence>
          {draft && (
            <StickyNote
              key="draft"
              note={draft}
              composing
              submitting={submitting}
              verified={verified}
              errorMessage={postError}
              size={NOTE_SIZE}
              pad={pad}
              canvasW={canvasSize.w}
              canvasH={canvasSize.h}
              onDraftMove={moveDraft}
              onBodyChange={(v) => setDraft((d) => (d ? { ...d, body: v } : d))}
              onNameChange={(v) => setDraft((d) => (d ? { ...d, name: v } : d))}
              onColorChange={(c) => setDraft((d) => (d ? { ...d, color: c } : d))}
              onTurnstileToken={setTurnstileToken}
              onConfirm={confirmDraft}
              onCancel={cancelDraft}
            />
          )}
        </AnimatePresence>

        {!isLoading && (notes?.length ?? 0) === 0 && !draft && (
          <div className="pointer-events-none absolute inset-0 grid place-items-center">
            <p className="font-mono text-xs uppercase tracking-[0.22em] text-white/30">
              {t.wall.empty}
            </p>
          </div>
        )}
      </div>

      {/* Sticky following the pointer while dragging from the tray */}
      <AnimatePresence>
        {ghostColor && (
          <motion.div
            key="ghost"
            className="pointer-events-none fixed left-0 top-0 z-[90]"
            style={{ x: ghostX, y: ghostY }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0, transition: { duration: 0.14 } }}
          >
            <div className="-translate-x-1/2 -translate-y-1/2">
              <motion.div
                initial={{ scale: 0.85 }}
                animate={{ scale: 1.05 }}
                style={{
                  rotate: ghostRotate,
                  width: 124,
                  height: 124,
                  background: NOTE_COLORS[ghostColor].bg,
                  borderRadius: 3,
                  boxShadow: "0 22px 46px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.25)",
                }}
              />
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      <Tray onPointerDownSticky={startTrayDrag} hidden={!!draft || ghostColor !== null} />
    </div>
  );
}

function Tray({
  onPointerDownSticky,
  hidden,
}: {
  onPointerDownSticky: (e: React.PointerEvent, color: NoteColor) => void;
  hidden: boolean;
}) {
  const { t } = useI18n();
  const reduceMotion = useHydratedReducedMotion();
  const mid = (NOTE_COLOR_KEYS.length - 1) / 2;

  // Idle "swipe": auto-play each sticky's hover left→right (0.2s apart) on a 5s
  // loop, so the tray reads as interactive. Reuses the hover transform — no new
  // visual, just an automated cursor-swipe feel. Pauses while the pointer is on
  // the tray (hover) or any drag/compose is in flight (the whole tray is `hidden`
  // then), so it never fights a real interaction. Off under reduced motion.
  const [sweep, setSweep] = useState(-1);
  const [hovering, setHovering] = useState(false);
  const paused = hidden || hovering || reduceMotion;
  // Force the wave to rest while paused via derivation, so we never setState in
  // the effect just to reset — the interval callback is the only writer of `sweep`.
  const activeSweep = paused ? -1 : sweep;
  // The very first sweep waits 3s after load so the page settles before the tray
  // draws attention; later resumes (after a hover/drag) start right away.
  const firstSweepRef = useRef(true);

  useEffect(() => {
    if (paused) return;
    const COUNT = NOTE_COLOR_KEYS.length;
    const STEP_MS = 200; // 0.2s between notes
    const CYCLE_STEPS = Math.round(5000 / STEP_MS); // 5s loop
    let step = 0;
    let intervalId = 0;
    const tick = () => {
      // The lit note travels 0→last over the first COUNT steps, then idles for the
      // rest of the cycle before repeating.
      setSweep(step < COUNT ? step : -1);
      step = (step + 1) % CYCLE_STEPS;
    };
    const startId = window.setTimeout(
      () => {
        firstSweepRef.current = false; // mark only once a sweep actually plays
        tick();
        intervalId = window.setInterval(tick, STEP_MS);
      },
      firstSweepRef.current ? 3000 : 0,
    );
    return () => {
      window.clearTimeout(startId);
      window.clearInterval(intervalId);
    };
  }, [paused]);

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-0 z-40 flex justify-center pb-6 sm:pb-8">
      <motion.div
        className="glass ring-accent pointer-events-auto flex flex-col items-center gap-3 rounded-[var(--radius-xl)] px-6 pb-4 pt-5"
        initial={false}
        animate={{ y: hidden ? 120 : 0, opacity: hidden ? 0 : 1 }}
        transition={{ type: "spring", stiffness: 260, damping: 26 }}
        onPointerEnter={() => setHovering(true)}
        onPointerLeave={() => setHovering(false)}
      >
        <div className="flex items-end gap-2.5">
          {NOTE_COLOR_KEYS.map((c, i) => (
            <motion.button
              key={c}
              type="button"
              onPointerDown={(e) => onPointerDownSticky(e, c)}
              aria-label={format(t.wall.trayDragAria, { color: c })}
              animate={{ y: activeSweep === i ? -8 : 0, scale: activeSweep === i ? 1.08 : 1 }}
              whileHover={{ y: -8, scale: 1.08 }}
              transition={{ type: "spring", stiffness: 320, damping: 17 }}
              style={{
                rotate: (i - mid) * 4,
                background: NOTE_COLORS[c].bg,
                boxShadow: "0 5px 12px rgba(0,0,0,0.42), inset 0 1px 0 rgba(255,255,255,0.3)",
                touchAction: "none",
              }}
              className="relative h-[46px] w-[46px] shrink-0 cursor-grab rounded-[4px] active:cursor-grabbing"
            >
              <span
                aria-hidden
                className="absolute -top-[5px] left-1/2 h-2.5 w-7 -translate-x-1/2 rounded-[1px]"
                style={{ background: "rgba(255,255,255,0.32)" }}
              />
            </motion.button>
          ))}
        </div>
        <div className="font-mono text-[11px] text-white/45">{t.wall.trayHint}</div>
      </motion.div>
    </div>
  );
}
