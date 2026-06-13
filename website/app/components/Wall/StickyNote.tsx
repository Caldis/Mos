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
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import {
  CANVAS_PAD,
  NOTE_COLORS,
  NOTE_COLOR_KEYS,
  NOTE_MAX_BODY,
  NOTE_MAX_NAME,
  NOTE_SIZE as BASE,
  bodyHasLink,
  safeArea,
  type NoteColor,
  type WallNote,
} from "@/app/services/wall";
import { useI18n } from "@/app/i18n/context";
import { format } from "@/app/i18n/format";
import { TurnstileWidget, WALL_TURNSTILE_ENABLED } from "./TurnstileWidget";

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

// Localized relative time ("2h ago" / "2小时前") via Intl — no extra i18n keys.
// Computed at render; runs client-side only (placed notes never render on the server).
function relativeTime(ms: number, lang: string): string {
  const rtf = new Intl.RelativeTimeFormat(lang, { numeric: "auto" });
  const sec = Math.round((ms - Date.now()) / 1000); // negative = past
  const a = Math.abs(sec);
  if (a < 60) return rtf.format(sec, "second");
  if (a < 3600) return rtf.format(Math.round(sec / 60), "minute");
  if (a < 86400) return rtf.format(Math.round(sec / 3600), "hour");
  if (a < 2592000) return rtf.format(Math.round(sec / 86400), "day");
  if (a < 31536000) return rtf.format(Math.round(sec / 2592000), "month");
  return rtf.format(Math.round(sec / 31536000), "year");
}

interface StickyNoteProps {
  note: WallNote;
  composing?: boolean;
  mine?: boolean;
  // Admin (panel moderation) mode: reveals the delete affordance on EVERY note,
  // not just your own. The Worker still enforces the privilege via the token.
  admin?: boolean;
  index?: number;
  // Total placed-note count, so the entrance stagger can compress its per-note
  // step on a busy wall instead of clumping every late note at one delay.
  count?: number;
  submitting?: boolean;
  canvasW?: number;
  canvasH?: number;
  // Rendered side length in px. Placed notes shrink on narrow canvases; the
  // compose draft always renders at the full BASE size.
  size?: number;
  // Safe-area insets for the drag constraints (responsive — tighter on phones).
  pad?: { margin: number; top: number; tray: number };
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
  // Hide one of your own placed notes (only rendered when `mine`).
  onDelete?: (id: string) => void;
}

function Card({
  palette,
  active,
  size,
  minHeight,
  children,
}: {
  palette: { bg: string; ink: string; edge: string };
  active?: boolean;
  size: number;
  // Lower bound on card height. Below the old square `size` so a short note can
  // shrink; the flex column still grows past it when the body is long.
  minHeight: number;
  children: ReactNode;
}) {
  const k = size / BASE;
  return (
    <div
      className="flex flex-col rounded-[3px]"
      style={{
        width: size,
        minHeight,
        paddingLeft: 16 * k,
        paddingRight: 16 * k,
        paddingTop: 16 * k,
        paddingBottom: 14 * k,
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
  admin = false,
  index = 0,
  count = 1,
  submitting = false,
  canvasW = 0,
  canvasH = 0,
  size = BASE,
  pad = CANVAS_PAD,
  verified = false,
  errorMessage = null,
  onDraftMove,
  onBodyChange,
  onNameChange,
  onColorChange,
  onTurnstileToken,
  onConfirm,
  onCancel,
  onDelete,
}: StickyNoteProps) {
  const { t, language } = useI18n();
  const palette = NOTE_COLORS[note.color];
  // Compose always renders at the full BASE size (a shrunk card is too cramped to
  // type in); placed notes use the responsive `size`. k scales the tape, padding
  // and type so a smaller sticky stays proportional. HALF re-centers it: a note's
  // center stays at note.x*canvasW regardless of size (positions are normalized).
  const renderSize = composing ? BASE : size;
  const HALF = renderSize / 2;
  const k = renderSize / BASE;
  // D3: only the in-progress draft is ever draggable. Once a note is placed its
  // position is locked forever — `mine` is purely a visual cue (brighter tape).
  const draggable = composing;
  const dragControls = useDragControls();
  const x = useMotionValue(note.x * canvasW - HALF);
  const y = useMotionValue(note.y * canvasH - HALF);
  const draggingRef = useRef(false);
  const [dragging, setDragging] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const bodyRef = useRef<HTMLTextAreaElement | null>(null);

  useEffect(() => {
    if (draggingRef.current) return;
    x.set(note.x * canvasW - HALF);
    y.set(note.y * canvasH - HALF);
  }, [note.x, note.y, canvasW, canvasH, HALF, x, y]);

  useEffect(() => {
    if (!composing) return;
    const id = window.requestAnimationFrame(() => bodyRef.current?.focus());
    return () => window.cancelAnimationFrame(id);
  }, [composing]);

  // Grow the compose textarea to fit its content (collapse to measure, then set
  // to scrollHeight) so the editing card's height tracks what the placed note
  // will be — instead of being frozen at a fixed row count. The CSS min-height on
  // the textarea keeps an empty draft comfortably tall.
  const resizeBody = useCallback(() => {
    const el = bodyRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, []);

  useLayoutEffect(() => {
    if (composing) resizeBody();
  }, [composing, note.body, resizeBody]);

  // Tilt against horizontal velocity, like the note lags behind the hand.
  // useVelocity is noisy at low speed (causes twitching), so spring-smooth it
  // first — the standard scroll-velocity-skew pattern — then map to an angle.
  const xVel = useVelocity(x);
  const smoothVel = useSpring(xVel, { stiffness: 170, damping: 40, mass: 0.7 });
  // Held by the top tape: moving right makes the bottom lag left → clockwise (+).
  const sway = useTransform(smoothVel, [-1800, 0, 1800], [-12, 0, 12], { clamp: true });
  const rotate = useTransform(sway, (s) => note.rot + s);

  // Drag bounds come from the shared safe area — the same module the tray-drag
  // ghost and the drop clamp use, so every interaction is protected identically.
  // The motion value is the note's TOP-LEFT, so shift the center-rect by HALF.
  const a = safeArea(canvasW, canvasH, pad, HALF);
  const constraints = {
    left: a.minX - HALF,
    right: a.maxX - HALF,
    top: a.minY - HALF,
    bottom: a.maxY - HALF,
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

  // Links are banned: warn live and block submit while the body contains one, so
  // the user fixes it here instead of round-tripping to a server rejection.
  const hasLink = composing && bodyHasLink(note.body);
  // Need a body, not mid-submit, no link, and — when Turnstile is on — a token.
  const canConfirm = note.body.trim().length > 0 && !submitting && verified && !hasLink;
  const onKey = (e: React.KeyboardEvent) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter" && canConfirm) onConfirm?.();
    if (e.key === "Escape") onCancel?.();
  };

  // Your notes get a bright, wide, grippable tape; others' a small faded one.
  const tape = draggable
    ? { w: 96, h: 28, bg: "rgba(255,255,255,0.4)" }
    : { w: 64 * k, h: 20 * k, bg: "rgba(255,255,255,0.13)" };

  // Initial-load stagger: notes pop in oldest→newest. Keep the snappy STAGGER_STEP
  // on a small wall, but once there are many notes shrink the step so the LAST one
  // still lands within ~STAGGER_TOTAL. Every note stays sequential — unlike the old
  // hard delay cap, which gave every note past the cap the same delay (they all
  // appeared at once).
  const STAGGER_STEP = 0.04;
  const STAGGER_TOTAL = 1.1;
  const entranceDelay = count > 1 ? index * Math.min(STAGGER_STEP, STAGGER_TOTAL / (count - 1)) : 0;

  // Card floor: vertical padding (16+14) + footer gap & line (12+11) + ~one body
  // line (23 × 1.14), scaled by k. Replaces the old square `size` minimum so a
  // one- or two-line note sits compact instead of padded out to a square; longer
  // bodies grow the flex column past it. compose's stacked controls already
  // exceed this, so there the height is driven purely by the auto-grow textarea.
  const minCardHeight = Math.round((16 + 14 + 12 + 11) * k + 23 * 1.14 * k);

  return (
    <motion.div
      className="group absolute left-0 top-0 will-change-transform"
      onMouseLeave={() => setConfirmingDelete(false)}
      drag={draggable}
      dragListener={false}
      dragControls={dragControls}
      dragConstraints={constraints}
      dragElastic={0.04}
      // Placed notes share one low z-index so they sit below the chrome (header
      // 50 / compose 60 / ghost 90); their mutual order comes from DOM order,
      // which wall-client sorts oldest → newest so the latest sticky is on top.
      style={{ x, y, rotate, perspective: 720, zIndex: composing ? 60 : dragging ? 50 : 2 }}
      initial={{ opacity: 0, scale: composing ? 0.6 : 0.7 }}
      animate={{ opacity: 1, scale: 1 }}
      exit={composing ? { opacity: 0, scale: 0.66, transition: { duration: 0.16 } } : undefined}
      transition={
        composing
          ? { type: "spring", stiffness: 440, damping: 24 }
          : { type: "spring", stiffness: 260, damping: 22, delay: entranceDelay }
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
        className={`absolute left-1/2 z-20 -translate-x-1/2 rounded-[2px] ${
          draggable ? "cursor-grab touch-none active:cursor-grabbing" : ""
        }`}
        style={{ top: -10 * k, width: tape.w, height: tape.h, background: tape.bg, transformOrigin: "bottom center" }}
        animate={
          dragging
            ? { rotateX: -62, y: -6, boxShadow: "0 9px 16px rgba(0,0,0,0.38)" }
            : { rotateX: draggable ? -3 : -1, y: 0, boxShadow: "0 1px 2px rgba(0,0,0,0.16)" }
        }
        transition={{ type: "spring", stiffness: 380, damping: 20 }}
      />

      {/* Delete affordance — own placed notes, or ANY note in admin mode. Hidden
          until the note is hovered (or the button focused); first click arms a red
          "Delete?" confirm, second deletes. Mouse-leave cancels. When an admin is
          deleting someone else's note the × is red — a "this isn't yours" warning. */}
      {!composing && (mine || admin) && onDelete && (
        <button
          type="button"
          onClick={() => (confirmingDelete ? onDelete(note.id) : setConfirmingDelete(true))}
          aria-label={confirmingDelete ? t.wall.deleteConfirm : t.wall.delete}
          className={`absolute -right-2.5 -top-2.5 z-30 grid h-6 place-items-center rounded-full opacity-0 shadow-md transition focus-visible:opacity-100 group-hover:opacity-100 ${
            confirmingDelete
              ? "px-2 text-[10px] font-semibold"
              : "w-6 text-[14px] leading-none hover:scale-110"
          }`}
          style={
            confirmingDelete || (admin && !mine)
              ? { background: "#c0392b", color: "#fff" }
              : { background: palette.ink, color: palette.bg }
          }
        >
          {confirmingDelete ? t.wall.deleteConfirm : "×"}
        </button>
      )}

      <Card palette={palette} active={composing} size={renderSize} minHeight={minCardHeight}>
        {composing ? (
          <>
            <textarea
              ref={bodyRef}
              value={note.body}
              maxLength={NOTE_MAX_BODY}
              rows={1}
              onChange={(e) => {
                onBodyChange?.(e.target.value);
                resizeBody();
              }}
              onKeyDown={onKey}
              placeholder={t.wall.bodyPlaceholder}
              className="font-hand w-full resize-none select-text bg-transparent text-[23px] leading-[1.12] outline-none placeholder:opacity-60"
              style={{ color: palette.ink, minHeight: "2.24em" }}
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

            {hasLink && (
              <div
                role="status"
                className="mt-1.5 text-[11px] leading-snug"
                style={{ color: palette.ink, opacity: 0.72 }}
              >
                {t.wall.noLinksHint}
              </div>
            )}

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
            <div
              className="font-hand leading-[1.14] [overflow-wrap:anywhere]"
              style={{ fontSize: Math.round(23 * k) }}
            >
              {note.body}
            </div>
            <div
              className="mt-auto flex items-center justify-between font-medium"
              style={{ opacity: 0.62, paddingTop: 12 * k, fontSize: Math.max(9, Math.round(11 * k)) }}
            >
              <span className="min-w-0 flex-1 truncate">{note.name?.trim() || t.wall.anonymous}</span>
              <span
                title={new Intl.DateTimeFormat(language, { dateStyle: "medium", timeStyle: "short" }).format(note.createdAt)}
                className="shrink-0 tabular-nums"
                style={{ paddingLeft: 8 * k }}
              >
                {relativeTime(note.createdAt, language)}
              </span>
            </div>
          </>
        )}
      </Card>
    </motion.div>
  );
}
