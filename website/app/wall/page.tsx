import type { Metadata } from "next";
import { WallHeader } from "@/app/components/Wall/WallHeader";
import { WallClient } from "./wall-client";

// Kept server-side and in English on purpose: static export resolves metadata at
// build time, so it can't read the client-side language. The visible header is
// localized separately via <WallHeader/>.
export const metadata: Metadata = {
  title: "The Wall — Mos",
  description:
    "A shared sticky-note wall. Drag a sticky onto the canvas and leave a note for Mos.",
};

export default function WallPage() {
  return (
    <main className="relative h-[100dvh] w-full select-none overflow-hidden bg-[var(--bg0)]">
      <WallClient />
      <WallHeader />
    </main>
  );
}
