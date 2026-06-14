"use client";

import { useCallback, useEffect, useRef, type MouseEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { useI18n } from "@/app/i18n/context";
import { useWallAdmin } from "@/app/hooks/useWallAdmin";

// Hidden admin entry: clicking the wall title this many times (within a short
// gap of each other) opens the admin-token prompt. No visual feedback by design —
// it's an unadvertised maintainer shortcut, not a public control.
const ADMIN_CLICKS = 10;
const ADMIN_CLICK_GAP_MS = 1500;

// Just the visible header chrome for /wall. Split out as a client component so
// the page itself can stay a server component (it owns the static `metadata`,
// which static export requires to live server-side).
export function WallHeader() {
  const { t } = useI18n();
  const router = useRouter();
  const { unlock } = useWallAdmin();

  // Count clicks on the title; reset if they slow down (so stray taps over time
  // never accumulate). On the threshold, prompt for the token and verify it.
  const clicks = useRef(0);
  const resetTimer = useRef<number | null>(null);
  useEffect(() => () => {
    if (resetTimer.current) window.clearTimeout(resetTimer.current);
  }, []);

  const handleTitleClick = useCallback(() => {
    if (resetTimer.current) window.clearTimeout(resetTimer.current);
    clicks.current += 1;
    if (clicks.current < ADMIN_CLICKS) {
      resetTimer.current = window.setTimeout(() => {
        clicks.current = 0;
      }, ADMIN_CLICK_GAP_MS);
      return;
    }
    clicks.current = 0;
    const token = window.prompt("Admin token");
    if (!token) return;
    void unlock(token).then((ok) => {
      window.alert(ok ? "Admin mode unlocked" : "Invalid token");
    });
  }, [unlock]);

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
      <div className="wall-enter-left pointer-events-none">
        <Link
          href="/"
          onClick={handleBack}
          className="pointer-events-auto inline-flex items-center gap-2 rounded-full border border-white/10 bg-black/40 px-3.5 py-2 font-mono text-xs text-white/65 backdrop-blur-md transition-colors hover:border-white/20 hover:text-white"
        >
          <span aria-hidden>←</span> {t.wall.back}
        </Link>
      </div>
      {/* Hidden admin entry: click the title ADMIN_CLICKS× to open the token
          prompt. Intentionally NOT announced as interactive (no role/keyboard
          handler) — it's an unadvertised maintainer shortcut. */}
      <div
        className="wall-enter-right pointer-events-auto select-none text-right"
        onClick={handleTitleClick}
      >
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
