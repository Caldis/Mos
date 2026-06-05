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
import {
  CANVAS_PAD,
  NOTE_COLOR_KEYS,
  NOTE_COLORS,
  NOTE_SIZE,
  postNote,
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
  rot: number;
  createdAt: number;
}

const HALF = NOTE_SIZE / 2;
function randRot(): number {
  return Math.round((Math.random() * 8 - 4) * 10) / 10;
}
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export function WallClient() {
  const { data: notes, mutate, isLoading } = useWallNotes();
  const canvasRef = useRef<HTMLDivElement | null>(null);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [ghostColor, setGhostColor] = useState<NoteColor | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [myIds, setMyIds] = useState<Set<string>>(() => new Set());
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
      const { margin, top, tray } = CANVAS_PAD;
      const { w, h } = canvasSize;
      const x = w ? clamp(nx * w, HALF + margin, w - HALF - margin) / w : clamp(nx, 0.12, 0.88);
      const y = h ? clamp(ny * h, HALF + top, h - HALF - tray) / h : clamp(ny, 0.14, 0.8);
      setDraft({ id: "draft", name: "", body: "", color, x, y, rot, createdAt: Date.now() });
    },
    [canvasSize]
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
        beginDraft(0.5, 0.4, d.color, ghostBaseRot.current);
      }
    },
    [beginDraft, onPointerMove, ghostTilt]
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

  const confirmDraft = useCallback(async () => {
    if (!draft || !draft.body.trim()) return;
    setSubmitting(true);
    try {
      const created = await postNote({
        name: draft.name.trim(),
        body: draft.body.trim(),
        color: draft.color,
        x: draft.x,
        y: draft.y,
        rot: draft.rot,
      });
      await mutate((cur) => [...(cur ?? []), created], { revalidate: false });
      setMyIds((s) => {
        const next = new Set(s);
        next.add(created.id);
        return next;
      });
      setDraft(null);
    } catch (err) {
      console.error("Failed to post note", err);
    } finally {
      setSubmitting(false);
    }
  }, [draft, mutate]);

  const cancelDraft = useCallback(() => setDraft(null), []);

  const reposition = useCallback(
    (id: string, nx: number, ny: number) => {
      mutate((cur) => (cur ?? []).map((n) => (n.id === id ? { ...n, x: nx, y: ny } : n)), {
        revalidate: false,
      });
      // TODO: persist position to the backend (PATCH) once the Worker is live.
    },
    [mutate]
  );

  const moveDraft = useCallback((nx: number, ny: number) => {
    setDraft((d) => (d ? { ...d, x: nx, y: ny } : d));
  }, []);

  return (
    <div className="relative h-full w-full select-none overflow-hidden">
      <div ref={canvasRef} className="wall-grid absolute inset-0">
        <AnimatePresence>
          {canvasSize.w > 0 &&
            (notes ?? []).map((n, i) => (
              <StickyNote
                key={n.id}
                note={n}
                index={i}
                mine={myIds.has(n.id)}
                canvasW={canvasSize.w}
                canvasH={canvasSize.h}
                onReposition={reposition}
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
              canvasW={canvasSize.w}
              canvasH={canvasSize.h}
              onDraftMove={moveDraft}
              onBodyChange={(v) => setDraft((d) => (d ? { ...d, body: v } : d))}
              onNameChange={(v) => setDraft((d) => (d ? { ...d, name: v } : d))}
              onColorChange={(c) => setDraft((d) => (d ? { ...d, color: c } : d))}
              onConfirm={confirmDraft}
              onCancel={cancelDraft}
            />
          )}
        </AnimatePresence>

        {!isLoading && (notes?.length ?? 0) === 0 && !draft && (
          <div className="pointer-events-none absolute inset-0 grid place-items-center">
            <p className="font-mono text-xs uppercase tracking-[0.22em] text-white/30">
              be the first to leave a note
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
  const mid = (NOTE_COLOR_KEYS.length - 1) / 2;
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-0 z-40 flex justify-center pb-6 sm:pb-8">
      <motion.div
        className="glass ring-accent pointer-events-auto flex flex-col items-center gap-3 rounded-[var(--radius-xl)] px-6 pb-4 pt-5"
        initial={false}
        animate={{ y: hidden ? 120 : 0, opacity: hidden ? 0 : 1 }}
        transition={{ type: "spring", stiffness: 260, damping: 26 }}
      >
        <div className="flex items-end gap-2.5">
          {NOTE_COLOR_KEYS.map((c, i) => (
            <motion.button
              key={c}
              type="button"
              onPointerDown={(e) => onPointerDownSticky(e, c)}
              aria-label={`Drag a ${c} sticky onto the wall`}
              whileHover={{ y: -8, scale: 1.08 }}
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
        <div className="font-mono text-[11px] text-white/45">Drag a sticky onto the wall</div>
      </motion.div>
    </div>
  );
}
