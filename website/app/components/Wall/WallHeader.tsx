"use client";

import { useI18n } from "@/app/i18n/context";

// Just the visible header chrome for /wall. Split out as a client component so
// the page itself can stay a server component (it owns the static `metadata`,
// which static export requires to live server-side).
export function WallHeader() {
  const { t } = useI18n();
  return (
    <header className="pointer-events-none absolute inset-x-0 top-0 z-50 flex items-start justify-between px-4 py-4 sm:px-7 sm:py-5">
      <a
        href="/"
        className="pointer-events-auto inline-flex items-center gap-2 rounded-full border border-white/10 bg-black/40 px-3.5 py-2 font-mono text-xs text-white/65 backdrop-blur-md transition-colors hover:border-white/20 hover:text-white"
      >
        <span aria-hidden>←</span> {t.wall.back}
      </a>
      <div className="select-none text-right">
        <div className="font-display text-base font-semibold tracking-wide text-white">
          {t.wall.title}
        </div>
        <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-white/40">
          {t.wall.tagline}
        </div>
      </div>
    </header>
  );
}
