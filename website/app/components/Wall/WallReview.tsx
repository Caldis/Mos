"use client";

import { AnimatePresence, motion } from "framer-motion";
import { useState } from "react";
import { NOTE_COLORS, type AdminNote } from "@/app/services/wall";
import { useHydratedReducedMotion } from "@/app/hooks/useHydratedReducedMotion";
import { useI18n } from "@/app/i18n/context";

const SPRING = { type: "spring" as const, stiffness: 300, damping: 34 };
const EASE_OUT = [0.16, 1, 0.3, 1] as const;
const DANGER = "#c0392b";

// Filter categories, in display order. A note's category is its hide_reason, or
// "live" when it's visible with no flag. "all" is always shown.
const FILTER_ORDER = ["all", "live", "ai-low-quality", "spam", "user", "admin", "admin-del"] as const;
const FILTER_LABEL: Record<string, string> = {
  all: "All",
  live: "Live",
  "ai-low-quality": "AI",
  spam: "Spam",
  user: "User",
  admin: "Admin",
  "admin-del": "Admin-del",
};
const catOf = (n: AdminNote) => n.hideReason ?? "live";

function relTime(ms: number, lang: string): string {
  const rtf = new Intl.RelativeTimeFormat(lang, { numeric: "auto" });
  const sec = Math.round((ms - Date.now()) / 1000);
  const a = Math.abs(sec);
  if (a < 60) return rtf.format(sec, "second");
  if (a < 3600) return rtf.format(Math.round(sec / 60), "minute");
  if (a < 86400) return rtf.format(Math.round(sec / 3600), "hour");
  if (a < 2592000) return rtf.format(Math.round(sec / 86400), "day");
  return rtf.format(Math.round(sec / 2592000), "month");
}

function FlagMark() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M5 21V4" />
      <path d="M5 4h10l-1.8 3.2L15 11H5" />
    </svg>
  );
}

function Spinner() {
  return <span className="inline-block h-3 w-3 animate-spin rounded-full border border-white/25 border-t-white/85" aria-hidden />;
}

interface WallReviewProps {
  notes: AdminNote[] | undefined;
  loading: boolean;
  onHideOne: (id: string) => Promise<void>;
  onRestore: (id: string) => Promise<void>;
  onHideAllAI: () => Promise<void>;
}

export function WallReview({ notes, loading, onHideOne, onRestore, onHideAllAI }: WallReviewProps) {
  const reduce = useHydratedReducedMotion();
  const { language } = useI18n();
  const [open, setOpen] = useState(false);
  const [filter, setFilter] = useState<string>("ai-low-quality");
  const [sortDir, setSortDir] = useState<"desc" | "asc">("desc");
  // Per-id in-flight set, so each row's hide/restore shows a LOCAL spinner without
  // blocking any other row.
  const [pending, setPending] = useState<ReadonlySet<string>>(new Set());
  const [armingAll, setArmingAll] = useState(false);
  const [hidingAll, setHidingAll] = useState(false);

  const all = notes ?? [];
  // Counts per category for the chip badges.
  const counts: Record<string, number> = { all: all.length };
  for (const n of all) counts[catOf(n)] = (counts[catOf(n)] ?? 0) + 1;
  const chips = FILTER_ORDER.filter((k) => k === "all" || (counts[k] ?? 0) > 0);
  const effective = chips.includes(filter as (typeof FILTER_ORDER)[number]) ? filter : "all";
  const list = effective === "all" ? all : all.filter((n) => catOf(n) === effective);
  const sorted = [...list].sort((a, b) =>
    sortDir === "desc" ? b.createdAt - a.createdAt : a.createdAt - b.createdAt,
  );
  // AI notes still awaiting a call (the "Hide all" target + trigger badge count).
  const aiOpen = all.filter((n) => !n.hidden && n.hideReason === "ai-low-quality").length;

  const runRow = async (id: string, fn: (id: string) => Promise<void>) => {
    setPending((p) => new Set(p).add(id));
    try {
      await fn(id);
    } catch {
      // Swallow: the row stays as-is; a transient failure can be retried.
    } finally {
      setPending((p) => {
        const s = new Set(p);
        s.delete(id);
        return s;
      });
    }
  };

  const runHideAll = async () => {
    setHidingAll(true);
    try {
      await onHideAllAI();
    } catch {
      // ignore
    } finally {
      setHidingAll(false);
      setArmingAll(false);
    }
  };

  return (
    <>
      {/* Trigger — top-right, tucked under the wall title. Always present in admin
          mode; the badge counts AI notes still awaiting a call. */}
      <AnimatePresence>
        {!open && (
          <motion.button
            type="button"
            onClick={() => setOpen(true)}
            aria-label="Open moderation review"
            className="glass pointer-events-auto fixed right-4 top-[60px] z-40 flex items-center gap-2 rounded-full py-1.5 pl-3 pr-2 sm:right-7 sm:top-[70px]"
            initial={reduce ? { opacity: 0 } : { opacity: 0, y: -8, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={reduce ? { opacity: 0 } : { opacity: 0, y: -8, scale: 0.95 }}
            transition={{ type: "spring", stiffness: 320, damping: 26 }}
            whileHover={{ y: -1 }}
          >
            <span className="text-white/65">
              <FlagMark />
            </span>
            <span className="font-mono text-[10px] uppercase tracking-[0.16em] text-white/65">Review</span>
            {aiOpen > 0 && (
              <span className="grid h-[18px] min-w-[18px] place-items-center rounded-full bg-white/90 px-1.5 font-mono text-[10px] font-semibold tabular-nums text-black">
                <AnimatePresence mode="popLayout" initial={false}>
                  <motion.span
                    key={aiOpen}
                    initial={reduce ? false : { y: -7, opacity: 0 }}
                    animate={{ y: 0, opacity: 1 }}
                    exit={reduce ? { opacity: 0 } : { y: 7, opacity: 0 }}
                    transition={{ duration: 0.18, ease: EASE_OUT }}
                  >
                    {aiOpen}
                  </motion.span>
                </AnimatePresence>
              </span>
            )}
          </motion.button>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {open && (
          <>
            <motion.div
              className="fixed inset-0 z-[60] bg-black/45"
              style={{ backdropFilter: "blur(2px)", WebkitBackdropFilter: "blur(2px)" }}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.22, ease: EASE_OUT }}
              onClick={() => setOpen(false)}
            />

            <motion.aside
              className="glass ring-accent fixed bottom-3 right-3 top-3 z-[61] flex w-[min(94vw,400px)] flex-col overflow-hidden rounded-[var(--radius-xl)] sm:bottom-4 sm:right-4 sm:top-4"
              initial={reduce ? { opacity: 0 } : { x: "calc(100% + 1.5rem)" }}
              animate={reduce ? { opacity: 1 } : { x: 0 }}
              exit={reduce ? { opacity: 0 } : { x: "calc(100% + 1.5rem)" }}
              transition={SPRING}
            >
              {/* Header */}
              <div className="flex shrink-0 items-start justify-between gap-3 px-5 pb-3 pt-5">
                <div>
                  <h2 className="font-display text-[17px] font-semibold tracking-wide text-white/95">Review</h2>
                  <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.18em] text-white/40">
                    {all.length} message{all.length === 1 ? "" : "s"} · {aiOpen} AI flagged
                  </p>
                </div>
                <button
                  type="button"
                  onClick={() => setOpen(false)}
                  aria-label="Close review"
                  className="-mr-1 -mt-1 grid h-8 w-8 shrink-0 place-items-center rounded-full text-white/45 transition hover:bg-white/10 hover:text-white/85"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden>
                    <path d="M6 6l12 12M18 6L6 18" />
                  </svg>
                </button>
              </div>

              {/* Filter chips + time-sort toggle */}
              {!loading && all.length > 0 && (
                <div className="flex shrink-0 flex-wrap items-center gap-1.5 px-5 pb-3">
                  {chips.map((k) => {
                    const active = k === effective;
                    return (
                      <button
                        key={k}
                        type="button"
                        onClick={() => setFilter(k)}
                        className="rounded-full px-2.5 py-1 font-mono text-[10px] uppercase tracking-wide transition-colors"
                        style={
                          active
                            ? { background: "rgba(255,255,255,0.92)", color: "#000" }
                            : { background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.55)" }
                        }
                      >
                        {FILTER_LABEL[k]} {counts[k] ?? 0}
                      </button>
                    );
                  })}
                  <button
                    type="button"
                    onClick={() => setSortDir((d) => (d === "desc" ? "asc" : "desc"))}
                    aria-label={`Sort by time, ${sortDir === "desc" ? "newest first" : "oldest first"}`}
                    className="ml-auto flex items-center gap-1 rounded-full bg-white/[0.06] px-2 py-1 font-mono text-[10px] uppercase tracking-wide text-white/55 transition-colors hover:text-white/90"
                  >
                    <motion.svg
                      width="11"
                      height="11"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.4"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      animate={{ rotate: sortDir === "desc" ? 0 : 180 }}
                      transition={{ duration: 0.2, ease: EASE_OUT }}
                      aria-hidden
                    >
                      <path d="M12 5v14M6 13l6 6 6-6" />
                    </motion.svg>
                    {sortDir === "desc" ? "Newest" : "Oldest"}
                  </button>
                </div>
              )}

              <div className="hairline mx-5 h-px shrink-0" />

              {/* List. Keyed by filter+sort so a switch is a single quiet fade of
                  the whole list — NOT a per-row reorder tween (which looked bad).
                  Rows themselves carry no layout animation. */}
              <div className="min-h-0 flex-1 overflow-y-auto px-2.5 py-2">
                {loading && all.length === 0 ? (
                  <Skeletons />
                ) : sorted.length === 0 ? (
                  <EmptyState />
                ) : (
                  <motion.ul
                    key={effective + sortDir}
                    className="m-0 list-none p-0"
                    initial={reduce ? false : { opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ duration: 0.15, ease: EASE_OUT }}
                  >
                    {sorted.map((n) => (
                      <ReviewRow
                        key={n.id}
                        note={n}
                        lang={language}
                        pending={pending.has(n.id)}
                        onHide={() => runRow(n.id, onHideOne)}
                        onRestore={() => runRow(n.id, onRestore)}
                      />
                    ))}
                  </motion.ul>
                )}
              </div>

              {/* Hide-all — only meaningful on the AI filter */}
              <AnimatePresence>
                {effective === "ai-low-quality" && aiOpen > 0 && (
                  <motion.div
                    className="shrink-0 border-t border-white/10 p-3"
                    onMouseLeave={() => setArmingAll(false)}
                    initial={reduce ? false : { opacity: 0, y: 12 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={reduce ? { opacity: 0 } : { opacity: 0, y: 12 }}
                    transition={{ duration: 0.2, ease: EASE_OUT }}
                  >
                    <button
                      type="button"
                      disabled={hidingAll}
                      onClick={() => (armingAll ? runHideAll() : setArmingAll(true))}
                      className="flex w-full items-center justify-center gap-2 rounded-[14px] px-4 py-2.5 font-mono text-[11px] uppercase tracking-[0.14em] transition-colors disabled:cursor-wait"
                      style={
                        armingAll
                          ? { background: DANGER, color: "#fff" }
                          : { background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.82)" }
                      }
                    >
                      {hidingAll ? (
                        <>
                          <Spinner /> Hiding…
                        </>
                      ) : armingAll ? (
                        `Confirm — hide all ${aiOpen}`
                      ) : (
                        `Hide all ${aiOpen}`
                      )}
                    </button>
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.aside>
          </>
        )}
      </AnimatePresence>
    </>
  );
}

// Dense single-line row (~38px): body truncates to one line; name · time · reason
// share the sub-line; action sits at the right. No per-row animation by design.
function ReviewRow({
  note,
  lang,
  pending,
  onHide,
  onRestore,
}: {
  note: AdminNote;
  lang: string;
  pending: boolean;
  onHide: () => void;
  onRestore: () => void;
}) {
  const palette = NOTE_COLORS[note.color];
  const cat = catOf(note);
  return (
    <li
      className={`group relative mb-1 flex items-center gap-2.5 overflow-hidden rounded-[9px] bg-white/[0.03] py-1.5 pl-3 pr-2 transition-colors last:mb-0 hover:bg-white/[0.06] ${
        note.hidden ? "opacity-50" : ""
      }`}
    >
      <span className="absolute inset-y-0 left-0 w-[3px]" style={{ background: palette.bg }} aria-hidden />
      <div className="min-w-0 flex-1">
        <p className="truncate text-[12.5px] leading-tight text-white/85">{note.body}</p>
        <p className="mt-0.5 truncate font-mono text-[9px] uppercase tracking-wide text-white/30">
          {(note.name?.trim() || "anon") + " · " + relTime(note.createdAt, lang) + " · " + (FILTER_LABEL[cat] ?? cat)}
        </p>
      </div>
      <button
        type="button"
        disabled={pending}
        onClick={note.hidden ? onRestore : onHide}
        className="grid h-[22px] min-w-[50px] shrink-0 place-items-center rounded-full border border-white/15 px-2 font-mono text-[9.5px] uppercase tracking-wide text-white/60 transition hover:border-white/35 hover:text-white/90 disabled:cursor-wait disabled:opacity-60"
      >
        {pending ? <Spinner /> : note.hidden ? "Restore" : "Hide"}
      </button>
    </li>
  );
}

function Skeletons() {
  return (
    <div className="space-y-1.5 px-0.5">
      {[0, 1, 2, 3, 4].map((i) => (
        <div key={i} className="h-[52px] animate-pulse rounded-[11px] bg-white/[0.04]" />
      ))}
    </div>
  );
}

function EmptyState() {
  return (
    <div className="grid h-full place-items-center px-6 text-center">
      <div className="flex flex-col items-center">
        <span className="grid h-11 w-11 place-items-center rounded-full border border-white/12 text-white/55">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M20 6 9 17l-5-5" />
          </svg>
        </span>
        <p className="mt-3 font-display text-[15px] text-white/80">Nothing here</p>
        <p className="mt-1 font-mono text-[10px] uppercase tracking-[0.15em] text-white/35">no messages in this filter</p>
      </div>
    </div>
  );
}
