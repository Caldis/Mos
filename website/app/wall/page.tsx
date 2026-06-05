import type { Metadata } from "next";
import { WallClient } from "./wall-client";

export const metadata: Metadata = {
  title: "The Wall — Mos",
  description:
    "A shared sticky-note wall. Drag a sticky onto the canvas and leave a note for Mos.",
};

export default function WallPage() {
  return (
    <main className="relative h-[100dvh] w-full select-none overflow-hidden bg-[var(--bg0)]">
      <WallClient />

      <header className="pointer-events-none absolute inset-x-0 top-0 z-50 flex items-start justify-between px-4 py-4 sm:px-7 sm:py-5">
        <a
          href="/"
          className="pointer-events-auto inline-flex items-center gap-2 rounded-full border border-white/10 bg-black/40 px-3.5 py-2 font-mono text-xs text-white/65 backdrop-blur-md transition-colors hover:border-white/20 hover:text-white"
        >
          <span aria-hidden>←</span> Mos
        </a>
        <div className="select-none text-right">
          <div className="font-display text-base font-semibold tracking-wide text-white">
            The Wall
          </div>
          <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-white/40">
            leave a sticky
          </div>
        </div>
      </header>
    </main>
  );
}
