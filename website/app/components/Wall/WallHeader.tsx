"use client";

import type { MouseEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { useI18n } from "@/app/i18n/context";

// Just the visible header chrome for /wall. Split out as a client component so
// the page itself can stay a server component (it owns the static `metadata`,
// which static export requires to live server-side).
export function WallHeader() {
  const { t } = useI18n();
  const router = useRouter();

  // The "← Mos" control should behave like a real back button. If the visitor
  // reached the wall from our own homepage (a client-side <Link> push), pop that
  // entry so the homepage restores its scroll position instead of jumping to the
  // top. Only fall back to the <Link>'s default push to "/" when /wall was opened
  // cold (a shared deep link or a fresh tab), where there's no in-app entry to
  // return to.
  const handleBack = (e: MouseEvent<HTMLAnchorElement>) => {
    // `nav.name` is the URL the *document* loaded at; after an in-app SPA
    // navigation it still points at the entry page, so a path mismatch with the
    // current location means we have our own history to pop.
    const nav = performance.getEntriesByType("navigation")[0];
    const arrivedViaClientNav =
      !!nav && new URL(nav.name).pathname !== window.location.pathname;
    if (arrivedViaClientNav) {
      e.preventDefault();
      router.back();
    }
  };

  return (
    <header className="pointer-events-none absolute inset-x-0 top-0 z-50 flex items-start justify-between px-4 py-4 sm:px-7 sm:py-5">
      <Link
        href="/"
        onClick={handleBack}
        className="pointer-events-auto inline-flex items-center gap-2 rounded-full border border-white/10 bg-black/40 px-3.5 py-2 font-mono text-xs text-white/65 backdrop-blur-md transition-colors hover:border-white/20 hover:text-white"
      >
        <span aria-hidden>←</span> {t.wall.back}
      </Link>
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
