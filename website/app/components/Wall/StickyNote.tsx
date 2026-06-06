"use client";

import {
  AnimatePresence,
  motion,
  useDragControls,
  useMotionValue,
  useSpring,
  useTransform,
  useVelocity,
} from "framer-motion";
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  CANVAS_PAD,
  NOTE_COLORS,
  NOTE_COLOR_KEYS,
  NOTE_MAX_BODY,
  NOTE_MAX_NAME,
  NOTE_SIZE as SIZE,
  type NoteColor,
  type WallNote,
} from "@/app/services/wall";
import { useI18n } from "@/app/i18n/context";
import { format } from "@/app/i18n/format";
import { TurnstileWidget, WALL_TURNSTILE_ENABLED } from "./TurnstileWidget";

const HALF = SIZE / 2;
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

interface StickyNoteProps {
  note: WallNote;
  composing?: boolean;
  mine?: boolean;
  index?: number;
  submitting?: boolean;
  canvasW?: number;
  canvasH?: number;
  // Set true once a Turnstile token is in hand (or when Turnstile is disabled),
  // gating the confirm button. Only relevant while composing.
  verified?: boolean;
  errorMessage?: string | null;
  onDraftMove?: (x: number, y: number) => void;
  onBodyChange?: (v: string) => void;
  onNameChange?: (v: string) => void;
  onColorChange?: (c: NoteColor) => void;
  // Receives a fresh Turnstile token (or "" when it expires / errors).
  onTurnstileToken?: (token: string) => void;
  onConfirm?: () => void;
  onCancel?: () => void;
}

function Card({
  palette,
  active,
  children,
}: {
  palette: { bg: string; ink: string; edge: string };
  active?: boolean;
  children: ReactNode;
}) {
  return (
    <div
      className="flex flex-col rounded-[3px] px-4 pb-3.5 pt-4"
      style={{
        width: SIZE,
        minHeight: SIZE,
        background: palette.bg,
        color: palette.ink,
        boxShadow: active
          ? `0 2px 4px rgba(0,0,0,0.2), 0 22px 48px rgba(0,0,0,0.5), 0 0 0 2px ${palette.edge} inset`
          : "0 1px 1px rgba(0,0,0,0.18), 0 12px 26px rgba(0,0,0,0.42), inset 0 1px 0 rgba(255,255,255,0.26)",
      }}
    >
      {children}
    </div>
  );
}

export function StickyNote({
  note,
  composing = false,
  mine = false,
  index = 0,
  submitting = false,
  canvasW = 0,
  canvasH = 0,
  verified = false,
  errorMessage = null,
  onDraftMove,
  onBodyChange,
  onNameChange,
  onColorChange,
  onTurnstileToken,
  onConfirm,
  onCancel,
}: StickyNoteProps) {
  const { t } = useI18n();
  const palette = NOTE_COLORS[note.color];
  // D3: only the in-progress draft is ever draggable. Once a note is placed its
  // position is locked forever — `mine` is purely a visual cue (brighter tape).
  const draggable = composing;
  const dragControls = useDragControls();
  const x = useMotionValue(note.x * canvasW - HALF);
  const y = useMotionValue(note.y * canvasH - HALF);
  const draggingRef = useRef(false);
  const [dragging, setDragging] = useState(false);
  const bodyRef = useRef<HTMLTextAreaElement | null>(null);

  useEffect(() => {
    if (draggingRef.current) return;
    x.set(note.x * canvasW - HALF);
    y.set(note.y * canvasH - HALF);
  }, [note.x, note.y, canvasW, canvasH, x, y]);

  useEffect(() => {
    if (!composing) return;
    const id = window.requestAnimationFrame(() => bodyRef.current?.focus());
    return () => window.cancelAnimationFrame(id);
  }, [composing]);

  // Tilt against horizontal velocity, like the note lags behind the hand.
  // useVelocity is noisy at low speed (causes twitching), so spring-smooth it
  // first — the standard scroll-velocity-skew pattern — then map to an angle.
  const xVel = useVelocity(x);
  const smoothVel = useSpring(xVel, { stiffness: 170, damping: 40, mass: 0.7 });
  // Held by the top tape: moving right makes the bottom lag left → clockwise (+).
  const sway = useTransform(smoothVel, [-1800, 0, 1800], [-12, 0, 12], { clamp: true });
  const rotate = useTransform(sway, (s) => note.rot + s);

  const { margin, top, tray } = CANVAS_PAD;
  const constraints = {
    left: margin,
    right: Math.max(margin, canvasW - SIZE - margin),
    top,
    bottom: Math.max(top, canvasH - SIZE - tray),
  };

  const endDrag = () => {
    draggingRef.current = false;
    setDragging(false);
    if (!canvasW || !canvasH) return;
    // Only the draft moves; placed notes are never draggable (D3), so the only
    // thing we report here is the draft's new position.
    const nx = clamp((x.get() + HALF) / canvasW, 0.02, 0.98);
    const ny = clamp((y.get() + HALF) / canvasH, 0.02, 0.98);
    onDraftMove?.(nx, ny);
  };

  // Need a body, not mid-submit, and — when Turnstile is enabled — a token.
  const canConfirm = note.body.trim().length > 0 && !submitting && verified;
  const onKey = (e: React.KeyboardEvent) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter" && canConfirm) onConfirm?.();
    if (e.key === "Escape") onCancel?.();
  };

  // Your notes get a bright, wide, grippable tape; others' a small faded one.
  const tape = draggable
    ? { w: 96, h: 28, bg: "rgba(255,255,255,0.4)" }
    : { w: 64, h: 20, bg: "rgba(255,255,255,0.13)" };

  return (
    <motion.div
      className="absolute left-0 top-0 will-change-transform"
      drag={draggable}
      dragListener={false}
      dragControls={dragControls}
      dragConstraints={constraints}
      dragElastic={0.04}
      style={{ x, y, rotate, perspective: 720, zIndex: composing ? 60 : dragging ? 50 : 2 }}
      initial={{ opacity: 0, scale: composing ? 0.6 : 0.7 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={composing ? { opacity: 0, scale: 0.66, transition: { duration: 0.16 } } : undefined}
      transition={
        composing
          ? { type: "spring", stiffness: 440, damping: 24 }
          : { type: "spring", stiffness: 260, damping: 22, delay: Math.min(index * 0.045, 0.6) }
      }
      whileDrag={{ scale: 1.06 }}
      onDragStart={() => {
        draggingRef.current = true;
        setDragging(true);
      }}
      onDragEnd={endDrag}
    >
      {/* tape = top drag handle, peels up on grab (only for draggable notes) */}
      <motion.div
        aria-hidden
        onPointerDown={
          draggable
            ? (e) => {
                e.preventDefault();
                dragControls.start(e);
              }
            : undefined
        }
        className={`absolute -top-[10px] left-1/2 z-20 -translate-x-1/2 rounded-[2px] ${
          draggable ? "cursor-grab touch-none active:cursor-grabbing" : ""
        }`}
        style={{ width: tape.w, height: tape.h, background: tape.bg, transformOrigin: "bottom center" }}
        animate={
          dragging
            ? { rotateX: -62, y: -6, boxShadow: "0 9px 16px rgba(0,0,0,0.38)" }
            : { rotateX: draggable ? -3 : -1, y: 0, boxShadow: "0 1px 2px rgba(0,0,0,0.16)" }
        }
        transition={{ type: "spring", stiffness: 380, damping: 20 }}
      />

      <Card palette={palette} active={composing}>
        {composing ? (
          <>
            <textarea
              ref={bodyRef}
              value={note.body}
              maxLength={NOTE_MAX_BODY}
              rows={3}
              onChange={(e) => onBodyChange?.(e.target.value)}
              onKeyDown={onKey}
              placeholder={t.wall.bodyPlaceholder}
              className="font-hand w-full flex-1 resize-none select-text bg-transparent text-[23px] leading-[1.12] outline-none placeholder:opacity-60"
              style={{ color: palette.ink }}
            />

            <div className="mt-2 flex items-center gap-1.5">
              {NOTE_COLOR_KEYS.map((c) => (
                <button
                  key={c}
                  type="button"
                  aria-label={format(t.wall.colorAria, { color: c })}
                  onClick={() => onColorChange?.(c)}
                  className="h-4 w-4 rounded-full transition-transform hover:scale-110"
                  style={{
                    background: NOTE_COLORS[c].bg,
                    outline: note.color === c ? `2px solid ${palette.ink}` : "1px solid rgba(0,0,0,0.12)",
                    outlineOffset: 1,
                  }}
                />
              ))}
              <span className="ml-auto text-[10px] tabular-nums" style={{ opacity: 0.5 }}>
                {note.body.length}/{NOTE_MAX_BODY}
              </span>
            </div>

            <input
              value={note.name}
              maxLength={NOTE_MAX_NAME}
              onChange={(e) => onNameChange?.(e.target.value)}
              onKeyDown={onKey}
              placeholder={t.wall.namePlaceholder}
              className="mt-2 w-full select-text border-b bg-transparent pb-1 text-[13px] outline-none placeholder:opacity-60"
              style={{ color: palette.ink, borderColor: "rgba(0,0,0,0.14)" }}
            />

            {/* Turnstile: shown only until verified, then collapses away with an
                animated height transition (no abrupt disappear). interaction-only
                keeps it invisible for passive passes; inert when no site key. */}
            <AnimatePresence initial={false}>
              {WALL_TURNSTILE_ENABLED && !verified && (
                <motion.div
                  key="turnstile"
                  initial={{ height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: 0.34, ease: [0.22, 1, 0.36, 1] }}
                  style={{ overflow: "hidden" }}
                >
                  <div className="flex flex-col items-center gap-1 pt-2.5 text-center">
                    <TurnstileWidget onToken={(token) => onTurnstileToken?.(token)} />
                    <div className="text-[10px] tracking-wide" style={{ color: palette.ink, opacity: 0.5 }}>
                      {t.wall.verifyHint}
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>

            {errorMessage && (
              <div
                role="alert"
                className="mt-2 text-[11px] leading-snug"
                style={{ color: palette.ink, opacity: 0.85 }}
              >
                {errorMessage}
              </div>
            )}

            <div className="mt-2.5 flex items-center gap-2">
              <button
                type="button"
                onClick={onCancel}
                className="rounded-md px-2 py-1 text-[12px] font-medium transition-opacity hover:opacity-70"
                style={{ color: palette.ink, opacity: 0.65 }}
              >
                {t.wall.cancel}
              </button>
              <button
                type="button"
                onClick={onConfirm}
                disabled={!canConfirm}
                className="ml-auto rounded-md px-3 py-1.5 text-[12px] font-semibold transition-transform active:scale-95"
                style={{
                  background: palette.ink,
                  color: palette.bg,
                  opacity: canConfirm ? 1 : 0.4,
                  cursor: canConfirm ? "pointer" : "not-allowed",
                }}
              >
                {submitting ? t.wall.submitting : t.wall.submit}
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="font-hand text-[23px] leading-[1.14] [overflow-wrap:anywhere]">{note.body}</div>
            <div
              className="mt-auto flex items-center justify-between pt-3 text-[11px] font-medium"
              style={{ opacity: 0.62 }}
            >
              <span className="max-w-[78%] truncate">{note.name?.trim() || t.wall.anonymous}</span>
              <span aria-hidden>✦</span>
            </div>
          </>
        )}
      </Card>
    </motion.div>
  );
}
