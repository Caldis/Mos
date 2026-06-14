"use client";

import {
  AnimatePresence,
  motion,
  useMotionValue,
  useSpring,
  useTransform,
  useVelocity,
} from "framer-motion";
import { useCallback, useEffect, useRef, useState } from "react";
import { StickyNote } from "@/app/components/Wall/StickyNote";
import { Minimap } from "@/app/components/Wall/Minimap";
import { Starfield } from "@/app/components/Wall/Starfield";
import { WallReview } from "@/app/components/Wall/WallReview";
import { WALL_TURNSTILE_ENABLED } from "@/app/components/Wall/TurnstileWidget";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";
import { useWallAdmin } from "@/app/hooks/useWallAdmin";
import { useI18n } from "@/app/i18n/context";
import { format } from "@/app/i18n/format";
import { notesBounds, useViewport, type Viewport } from "@/app/wall/useViewport";
import {
  FIT_MAX_SCALE,
  NOTE_COLOR_KEYS,
  NOTE_COLORS,
  NOTE_SIZE,
  WORLD_H,
  WORLD_NOTE_SIZE,
  WORLD_W,
  clampToWorld,
  deleteNote,
  hideAllFlagged,
  postNote,
  restoreNote,
  rotFromId,
  sparsestSpot,
  useAdminNotes,
  useWallNotes,
  worldBounds,
  type NoteColor,
  type SafeArea,
} from "@/app/services/wall";

interface Draft {
  id: string;
  name: string;
  body: string;
  color: NoteColor;
  // World coords (0..1 of WORLD_W/H), like a placed note.
  x: number;
  y: number;
  rot: number;
  createdAt: number;
  mine: boolean;
}

const HALF = NOTE_SIZE / 2;
function randRot(): number {
  return Math.round((Math.random() * 8 - 4) * 10) / 10;
}

// Chrome that overlaps the viewport edges, kept clear when fitting/placing so a
// note never lands hidden under the header or tray.
const FIT_INSETS = { top: 76, right: 28, bottom: 128, left: 28 };
// Don't fit below this — keeps note text legible; a sprawling board overflows and
// is explored by panning / the minimap instead of being shrunk to mush.
const FIT_MIN_READABLE = 0.75;
// When a draft is placed, lean in to at least this zoom so it's comfortably
// editable even if the board was zoomed way out.
const DRAFT_FOCUS_SCALE = 0.95;

export function WallClient() {
  const { t } = useI18n();
  const { admin } = useWallAdmin();
  // Debug-only: render the live production wall (read-only) instead of local seed.
  // Off by default so e2e runs never touch real notes; toggled via the dev pill.
  const isDev = process.env.NODE_ENV === "development";
  const [liveDebug, setLiveDebug] = useState(false);
  // Diagnostic: ?plain drops the starfield backdrop, to isolate its GPU/CPU cost when
  // chasing a mobile-Safari crash. Read after mount to avoid a hydration mismatch.
  const [plain, setPlain] = useState(false);
  useEffect(() => { setPlain(new URLSearchParams(window.location.search).has("plain")); }, []);
  const { data: notes, mutate, isLoading } = useWallNotes(liveDebug);
  const { data: adminNotes, mutate: mutateAdmin, isLoading: adminLoading } = useAdminNotes(admin);

  // Drop-focus undo: the viewport saved just before a place-focus, and whether the
  // user has moved the camera since (so cancelling an untouched draft glides back).
  const savedViewportRef = useRef<Viewport | null>(null);
  const cameraMovedRef = useRef(false);
  const focusTimerRef = useRef(0);

  const vp = useViewport({
    onUserInteract: () => {
      cameraMovedRef.current = true;
    },
  });
  const canvasRef = vp.containerRef;

  // Viewport pixel size, for the minimap frame + fit math.
  const [vpSize, setVpSize] = useState({ w: 0, h: 0 });
  useEffect(() => {
    const el = canvasRef.current;
    if (!el) return;
    const measure = () => setVpSize({ w: el.clientWidth, h: el.clientHeight });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [canvasRef]);

  const [draft, setDraft] = useState<Draft | null>(null);
  const [ghostColor, setGhostColor] = useState<NoteColor | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState("");
  const verified = !WALL_TURNSTILE_ENABLED || turnstileToken.length > 0;
  const [postError, setPostError] = useState<string | null>(null);
  const dragRef = useRef<{ startX: number; startY: number; color: NoteColor; moved: boolean } | null>(null);
  const ghostBaseRot = useRef(0);

  // Ghost (sticky following the pointer while dragging from the tray) shares the
  // same velocity → spring → tilt physics as a placed note. It lives in SCREEN
  // space; only the drop point is converted to the world.
  const ghostX = useMotionValue(0);
  const ghostY = useMotionValue(0);
  const ghostVel = useVelocity(ghostX);
  const ghostSmoothVel = useSpring(ghostVel, { stiffness: 170, damping: 40, mass: 0.7 });
  const ghostTilt = useTransform(ghostSmoothVel, [-1800, 0, 1800], [-12, 0, 12], { clamp: true });
  const ghostRotate = useTransform(ghostTilt, (tilt) => ghostBaseRot.current + tilt);
  // The drag preview scales with the board, so a sticky dropped while zoomed out
  // lands at the same (small) size it previewed at — matching its neighbours.
  const ghostSize = useTransform(vp.scale, (s) => Math.round(WORLD_NOTE_SIZE * s));

  // The world rectangle (px) a click-placed note may land in: the visible region,
  // inset for chrome and clamped to the board.
  const placementRect = useCallback((): SafeArea => {
    const v = vp.visibleWorldRect();
    const s = vp.get().scale || 1;
    const b = worldBounds(HALF);
    return {
      minX: Math.max(b.minX, v.minX + FIT_INSETS.left / s),
      minY: Math.max(b.minY, v.minY + FIT_INSETS.top / s),
      maxX: Math.min(b.maxX, v.maxX - FIT_INSETS.right / s),
      maxY: Math.min(b.maxY, v.maxY - FIT_INSETS.bottom / s),
    };
  }, [vp]);

  // Open a compose draft at a world position and ease the viewport to frame it at
  // a comfortable, readable scale (the editing card should never be tiny).
  const beginDraftWorld = useCallback(
    (nx: number, ny: number, color: NoteColor, rot: number) => {
      setDraft({ id: "draft", name: "", body: "", color, x: nx, y: ny, rot, createdAt: Date.now(), mine: false });
      const el = canvasRef.current;
      if (!el) return;
      const w = el.clientWidth;
      const h = el.clientHeight;
      if (!w || !h) return;
      // Remember the camera before focusing, so cancelling an untouched draft can
      // glide back here (see cancelDraft); reset the moved flag for this draft.
      savedViewportRef.current = vp.get();
      cameraMovedRef.current = false;
      // The ghost previewed at board scale (so it matched its neighbours); now lean
      // in to a readable zoom and centre the card a little above middle, so the user
      // can actually see what they're typing even if the board was zoomed way out.
      const s = Math.max(vp.get().scale, DRAFT_FOCUS_SCALE);
      const wx = nx * WORLD_W;
      const wy = ny * WORLD_H;
      // Hold a 0.3s beat so the card lands at board scale first, then lean in.
      window.clearTimeout(focusTimerRef.current);
      focusTimerRef.current = window.setTimeout(() => {
        vp.animateTo({ tx: w / 2 - wx * s, ty: h * 0.42 - wy * s, scale: s }, { duration: 0.5 });
      }, 300);
    },
    [vp, canvasRef],
  );

  // Custom drag for the compose draft: convert the pointer to world space so the
  // sticky tracks the cursor exactly at any zoom (framer drag would drift inside
  // the scaled world layer). Keeps the tape roughly under the finger (+HALF).
  const onComposeDragStart = useCallback(
    () => {
      const el = canvasRef.current;
      if (!el) return;
      const move = (ev: PointerEvent) => {
        const rect = el.getBoundingClientRect();
        const wpt = vp.screenToWorld(ev.clientX - rect.left, ev.clientY - rect.top);
        const c = clampToWorld(wpt.x, wpt.y + HALF, HALF);
        setDraft((d) => (d ? { ...d, x: c.x / WORLD_W, y: c.y / WORLD_H } : d));
      };
      const up = () => {
        window.removeEventListener("pointermove", move);
        window.removeEventListener("pointerup", up);
      };
      window.addEventListener("pointermove", move);
      window.addEventListener("pointerup", up, { once: true });
    },
    [vp, canvasRef],
  );

  const onPointerMove = useCallback(
    (e: PointerEvent) => {
      const d = dragRef.current;
      if (!d) return;
      if (!d.moved && Math.hypot(e.clientX - d.startX, e.clientY - d.startY) > 6) d.moved = true;
      if (d.moved) {
        ghostX.set(e.clientX);
        ghostY.set(e.clientY);
        setGhostColor((c) => c ?? d.color);
      }
    },
    [ghostX, ghostY],
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
      const inside =
        e.clientX >= rect.left && e.clientX <= rect.right && e.clientY >= rect.top && e.clientY <= rect.bottom;
      const rot = ghostBaseRot.current + ghostTilt.get();
      if (d.moved) {
        if (inside) {
          const wpt = vp.screenToWorld(e.clientX - rect.left, e.clientY - rect.top);
          const c = clampToWorld(wpt.x, wpt.y, HALF);
          beginDraftWorld(c.x / WORLD_W, c.y / WORLD_H, d.color, rot);
        }
      } else {
        // Plain click — drop into the emptiest spot currently in view.
        const spot = sparsestSpot(notes ?? [], placementRect());
        beginDraftWorld(spot.x, spot.y, d.color, ghostBaseRot.current);
      }
    },
    [onPointerMove, ghostTilt, vp, canvasRef, notes, beginDraftWorld, placementRect],
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
    [draft, onPointerMove, onPointerUp, ghostX, ghostY],
  );

  useEffect(() => () => window.removeEventListener("pointermove", onPointerMove), [onPointerMove]);

  // Frame the wall once per dataset: snap to frame the existing notes (or the board
  // centre when empty) on first load with a Google-Earth intro, and re-fit whenever
  // the live/seed mode flips. Keying off the MODE (not every notes change) means
  // posting a note doesn't yank the viewport. (The viewport is intentionally NOT
  // synced to the URL — every visit plays the intro instead of jumping to coords.)
  const fittedMode = useRef<"seed" | "live" | null>(null);
  useEffect(() => {
    if (isLoading || notes === undefined) return; // wait for the dataset to load
    const mode = liveDebug ? "live" : "seed";
    if (fittedMode.current === mode) return;
    let raf = 0;
    const run = () => {
      const el = canvasRef.current;
      if (!el || !el.clientWidth || !el.clientHeight) {
        raf = requestAnimationFrame(run);
        return;
      }
      const firstEver = fittedMode.current === null;
      fittedMode.current = mode;
      const b = notes.length ? notesBounds(notes, WORLD_NOTE_SIZE / 2) : null;
      const opts = { animate: !firstEver, insets: FIT_INSETS, padding: 48, maxScale: FIT_MAX_SCALE, minReadable: FIT_MIN_READABLE };
      const empty = { minX: WORLD_W / 2 - 500, minY: WORLD_H / 2 - 350, maxX: WORLD_W / 2 + 500, maxY: WORLD_H / 2 + 350 };
      const box = b ?? empty;
      if (firstEver) {
        // Google-Earth style intro: snap in close on the content's centre, then pull
        // back to the fit over ~1.4s so the wall "lands" into view.
        const cx = (box.minX + box.maxX) / 2;
        const cy = (box.minY + box.maxY) / 2;
        const intro = 1.8;
        vp.setViewport({ tx: el.clientWidth / 2 - cx * intro, ty: el.clientHeight / 2 - cy * intro, scale: intro });
        vp.fitToBounds(box, { ...opts, animate: true, duration: 1.4 });
      } else {
        vp.fitToBounds(box, opts);
      }
    };
    run();
    return () => cancelAnimationFrame(raf);
  }, [isLoading, notes, liveDebug, vp, canvasRef]);

  const toggleLive = useCallback(() => setLiveDebug((v) => !v), []);

  const fitAll = useCallback(() => {
    cameraMovedRef.current = true;
    const b = notesBounds(notes ?? [], WORLD_NOTE_SIZE / 2);
    if (b) vp.fitToBounds(b, { insets: FIT_INSETS, padding: 48, maxScale: FIT_MAX_SCALE, minReadable: FIT_MIN_READABLE });
  }, [notes, vp]);

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
    [t],
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
        turnstileToken: turnstileToken || undefined,
      });
      await mutate((cur) => [...(cur ?? []), created], { revalidate: false });
      window.clearTimeout(focusTimerRef.current);
      setDraft(null);
      setTurnstileToken("");
      savedViewportRef.current = null; // committed — stay at the focused view
    } catch (err) {
      const message = err instanceof Error ? err.message : "";
      setPostError(friendlyError(message));
      setTurnstileToken("");
    } finally {
      setSubmitting(false);
    }
  }, [draft, mutate, turnstileToken, friendlyError]);

  const cancelDraft = useCallback(() => {
    window.clearTimeout(focusTimerRef.current);
    setDraft(null);
    setPostError(null);
    setTurnstileToken("");
    // If the user never moved the camera after the auto-focus, glide back to where
    // they were — cancelling then feels like an undo of the whole place gesture.
    if (savedViewportRef.current && !cameraMovedRef.current) {
      vp.animateTo(savedViewportRef.current, { duration: 0.45 });
    }
    savedViewportRef.current = null;
  }, [vp]);

  const removeNote = useCallback(
    (id: string) => {
      mutate((cur) => (cur ?? []).filter((n) => n.id !== id), { revalidate: false });
      deleteNote(id).catch(() => mutate());
    },
    [mutate],
  );

  const hidePanelNote = useCallback(
    async (id: string) => {
      await deleteNote(id);
      mutate((cur) => (cur ?? []).filter((n) => n.id !== id), { revalidate: false });
      mutateAdmin(
        (cur) => (cur ?? []).map((n) => (n.id === id ? { ...n, hidden: true, hideReason: "admin-del" } : n)),
        { revalidate: false },
      );
    },
    [mutate, mutateAdmin],
  );

  const restorePanelNote = useCallback(
    async (id: string) => {
      await restoreNote(id);
      const note = (adminNotes ?? []).find((n) => n.id === id);
      mutateAdmin(
        (cur) => (cur ?? []).map((n) => (n.id === id ? { ...n, hidden: false, hideReason: null } : n)),
        { revalidate: false },
      );
      if (note) {
        mutate((cur) => {
          if ((cur ?? []).some((n) => n.id === id)) return cur;
          const restored = {
            id,
            name: note.name ?? "",
            body: note.body,
            color: note.color,
            x: note.x,
            y: note.y,
            rot: rotFromId(id),
            createdAt: note.createdAt,
            mine: false,
          };
          return [...(cur ?? []), restored];
        }, { revalidate: false });
      }
    },
    [adminNotes, mutate, mutateAdmin],
  );

  const hideAllAINotes = useCallback(async () => {
    const ids = new Set(
      (adminNotes ?? []).filter((n) => !n.hidden && n.hideReason === "ai-low-quality").map((n) => n.id),
    );
    if (ids.size === 0) return;
    await hideAllFlagged();
    mutate((cur) => (cur ?? []).filter((n) => !ids.has(n.id)), { revalidate: false });
    mutateAdmin(
      (cur) => (cur ?? []).map((n) => (ids.has(n.id) ? { ...n, hidden: true, hideReason: "admin-del" } : n)),
      { revalidate: false },
    );
  }, [adminNotes, mutate, mutateAdmin]);

  const hasNotes = (notes?.length ?? 0) > 0;
  // While dragging a sticky out of the tray or composing one, tuck the bottom
  // controls away (in step with the dock) so they don't crowd the placement.
  const interacting = !!draft || ghostColor !== null;

  return (
    <div className="relative h-full w-full select-none overflow-hidden">
      {/* Viewport frame — captures wheel/drag/pinch via useViewport. */}
      <div
        ref={canvasRef}
        className="absolute inset-0 cursor-grab overflow-hidden bg-black active:cursor-grabbing"
        style={{ touchAction: "none" }}
      >
        {/* Screen-fixed real-star backdrop (Yale BSC5) with per-star twinkle. */}
        {!plain && <Starfield vp={vp} />}

        {/* World layer — one transform pans/zooms every note. Intentionally has NO
            width/height or boxShadow: a 7200×4500 transformed element becomes a
            ~32 Mpx (~130MB) compositor layer that iOS must re-rasterise on every zoom
            step — the prime cause of the mobile zoom crash. Notes are absolutely
            positioned from this layer's top-left origin, so it needs no intrinsic
            size; it is purely a pan/zoom transform holder. */}
        <motion.div
          className="absolute left-0 top-0 origin-top-left"
          style={{ x: vp.tx, y: vp.ty, scale: vp.scale }}
        >
          <AnimatePresence>
            {[...(notes ?? [])]
              .sort((a, b) => a.createdAt - b.createdAt)
              .map((n, i, arr) => (
                <StickyNote
                  key={n.id}
                  note={n}
                  index={i}
                  count={arr.length}
                  mine={n.mine}
                  admin={admin}
                  size={WORLD_NOTE_SIZE}
                  canvasW={WORLD_W}
                  canvasH={WORLD_H}
                  onDelete={liveDebug ? undefined : removeNote}
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
                canvasW={WORLD_W}
                canvasH={WORLD_H}
                onComposeDragStart={onComposeDragStart}
                onBodyChange={(v) => setDraft((d) => (d ? { ...d, body: v } : d))}
                onNameChange={(v) => setDraft((d) => (d ? { ...d, name: v } : d))}
                onColorChange={(c) => setDraft((d) => (d ? { ...d, color: c } : d))}
                onTurnstileToken={setTurnstileToken}
                onConfirm={confirmDraft}
                onCancel={cancelDraft}
              />
            )}
          </AnimatePresence>
        </motion.div>

        {/* Initial load spinner (screen space). */}
        {isLoading && (
          <div className="pointer-events-none absolute inset-0 grid place-items-center">
            <motion.span
              className="h-7 w-7 rounded-full border-2 border-white/15 border-t-white/55"
              animate={{ rotate: 360 }}
              transition={{ repeat: Infinity, ease: "linear", duration: 0.8 }}
            />
          </div>
        )}

        {!isLoading && !hasNotes && !draft && (
          <div className="pointer-events-none absolute inset-0 grid place-items-center">
            <p className="font-mono text-xs uppercase tracking-[0.22em] text-white/30">{t.wall.empty}</p>
          </div>
        )}
      </div>

      {/* Sticky following the pointer while dragging from the tray (screen space). */}
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
                  width: ghostSize,
                  height: ghostSize,
                  background: NOTE_COLORS[ghostColor].bg,
                  borderRadius: 3,
                  boxShadow: "0 22px 46px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.25)",
                }}
              />
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Dock waits out the initial load so it doesn't pop up over a spinner. */}
      {!isLoading && (
        <Tray onPointerDownSticky={startTrayDrag} hidden={!!draft || ghostColor !== null || liveDebug} />
      )}

      {/* Zoom controls (bottom-left) + minimap (bottom-right). */}
      {!isLoading && <ZoomControls onFit={fitAll} hidden={interacting} />}
      {!isLoading && hasNotes && (
        <Minimap
          vp={vp}
          notes={notes ?? []}
          viewportSize={vpSize}
          hidden={interacting}
          onInteract={() => {
            cameraMovedRef.current = true;
          }}
        />
      )}

      {/* Admin-only moderation review. */}
      {admin && (
        <WallReview
          notes={adminNotes}
          loading={adminLoading}
          onHideOne={hidePanelNote}
          onRestore={restorePanelNote}
          onHideAllAI={hideAllAINotes}
        />
      )}

      {/* Dev-only: switch between local seed and the live production wall (read-only). */}
      {isDev && (
        <div className="pointer-events-none absolute inset-x-0 top-3 z-50 flex justify-center">
          <button
            type="button"
            onClick={toggleLive}
            className="wall-enter-down glass pointer-events-auto rounded-full px-3.5 py-1.5 font-mono text-[11px] tracking-wide transition hover:brightness-125"
            style={{ color: liveDebug ? "#fca5a5" : "rgba(255,255,255,0.55)" }}
          >
            {liveDebug ? "● LIVE 数据 · 只读" : "○ 用 Live 数据渲染"}
          </button>
        </div>
      )}
    </div>
  );
}

function ZoomControls({ onFit, hidden }: { onFit: () => void; hidden: boolean }) {
  const { t } = useI18n();
  return (
    <div className="wall-enter-bl pointer-events-none absolute bottom-6 left-6 z-40 hidden sm:block">
      <motion.div
        animate={{ x: hidden ? -90 : 0, y: hidden ? 90 : 0, opacity: hidden ? 0 : 1 }}
        transition={{ type: "spring", stiffness: 260, damping: 26 }}
      >
        <button
          type="button"
          aria-label={t.wall.zoomFit}
          onClick={onFit}
          className="glass pointer-events-auto grid h-9 w-9 place-items-center rounded-[14px] text-white/70 transition hover:bg-white/10 hover:text-white"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="M5.5 2.5h-3v3M10.5 2.5h3v3M5.5 13.5h-3v-3M10.5 13.5h3v-3" />
          </svg>
        </button>
      </motion.div>
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

  const [sweep, setSweep] = useState(-1);
  const [hovering, setHovering] = useState(false);
  const paused = hidden || hovering || reduceMotion;
  const activeSweep = paused ? -1 : sweep;
  const firstSweepRef = useRef(true);

  useEffect(() => {
    if (paused) return;
    const COUNT = NOTE_COLOR_KEYS.length;
    const STEP_MS = 200;
    const CYCLE_STEPS = Math.round(5000 / STEP_MS);
    let step = 0;
    let intervalId = 0;
    const tick = () => {
      setSweep(step < COUNT ? step : -1);
      step = (step + 1) % CYCLE_STEPS;
    };
    const startId = window.setTimeout(
      () => {
        firstSweepRef.current = false;
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
    <div className="wall-enter-up pointer-events-none absolute inset-x-0 bottom-6 z-40 flex justify-center">
      <motion.div
        className="glass pointer-events-auto flex flex-col items-center rounded-[14px] px-5 py-4"
        data-no-pan=""
        initial={false}
        animate={{ y: hidden ? 130 : 0, opacity: hidden ? 0 : 1 }}
        // CSS (wall-enter-up on the wrapper) plays the entrance; framer only drives
        // the quick show/hide while composing.
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
      </motion.div>
    </div>
  );
}
