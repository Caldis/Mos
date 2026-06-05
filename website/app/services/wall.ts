"use client";

import useSWR from "swr";

export type NoteColor = "amber" | "rose" | "sky" | "mint" | "lilac" | "blush";

export const NOTE_COLORS: Record<NoteColor, { bg: string; ink: string; edge: string }> = {
  amber: { bg: "#F2C879", ink: "#43320b", edge: "#dcae57" },
  rose: { bg: "#EE9A88", ink: "#451912", edge: "#db8472" },
  sky: { bg: "#9CC1E6", ink: "#142a3f", edge: "#83acd7" },
  mint: { bg: "#A4D8AE", ink: "#10311a", edge: "#8cc899" },
  lilac: { bg: "#C2AEE8", ink: "#281340", edge: "#ad99d8" },
  blush: { bg: "#EBC7DA", ink: "#3c1a2c", edge: "#d8acc5" },
};

export const NOTE_COLOR_KEYS = Object.keys(NOTE_COLORS) as NoteColor[];

export const NOTE_MAX_NAME = 24;
export const NOTE_MAX_BODY = 180;

// Sticky square size + safe insets used by both the canvas and drag constraints.
export const NOTE_SIZE = 198; // px
export const CANVAS_PAD = { margin: 48, top: 104, tray: 124 };

export interface WallNote {
  id: string;
  name: string;
  body: string;
  color: NoteColor;
  x: number; // normalized canvas coords, 0..1
  y: number; // normalized canvas coords, 0..1
  rot: number; // degrees
  createdAt: number;
}

export interface NewNoteInput {
  name: string;
  body: string;
  color: NoteColor;
  x: number;
  y: number;
  rot: number;
  // Cloudflare Turnstile token; required once the Worker backend is live.
  turnstileToken?: string;
}

export const WALL_API_URL =
  process.env.NEXT_PUBLIC_WALL_API_URL?.replace(/\/$/, "") ?? "";

// Demo seed shown until the Cloudflare Worker is configured.
const SEED_NOTES: WallNote[] = [
  { id: "seed-1", name: "Caldis", body: "Welcome to the wall — peel a sticky off the tray below and leave a note.", color: "amber", x: 0.5, y: 0.25, rot: -3, createdAt: 1717000000000 },
  { id: "seed-2", name: "Lin", body: "Mos 让我的滚轮终于顺了，谢谢你 🙏", color: "mint", x: 0.23, y: 0.52, rot: 2.5, createdAt: 1717100000000 },
  { id: "seed-3", name: "Aki", body: "scrolling feels like butter now", color: "sky", x: 0.75, y: 0.42, rot: -2, createdAt: 1717200000000 },
  { id: "seed-4", name: "mira", body: "trackpad person on a mouse — finally bearable", color: "lilac", x: 0.62, y: 0.68, rot: 3, createdAt: 1717300000000 },
  { id: "seed-5", name: "あお", body: "毎日つかってます。ありがとう！", color: "blush", x: 0.35, y: 0.78, rot: -3.5, createdAt: 1717400000000 },
];

let localNotes: WallNote[] | null = null;

function ensureLocal(): WallNote[] {
  if (!localNotes) localNotes = [...SEED_NOTES];
  return localNotes;
}

function makeId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return `n_${Date.now().toString(36)}`;
  }
}

async function fetchNotes(): Promise<WallNote[]> {
  // Return a copy so the SWR cache never aliases the in-memory store
  // (otherwise an optimistic append would duplicate the just-posted note).
  if (!WALL_API_URL) return [...ensureLocal()];
  const res = await fetch(`${WALL_API_URL}/api/messages`, {
    headers: { accept: "application/json" },
  });
  if (!res.ok) throw new Error(`wall fetch failed: ${res.status}`);
  const data = (await res.json()) as { notes: WallNote[] };
  return data.notes;
}

export function useWallNotes() {
  return useSWR<WallNote[]>("wall-notes", fetchNotes, {
    revalidateOnFocus: false,
    revalidateOnReconnect: false,
    refreshInterval: 0,
    dedupingInterval: 1000 * 20,
  });
}

export async function postNote(input: NewNoteInput): Promise<WallNote> {
  if (!WALL_API_URL) {
    const note: WallNote = {
      id: makeId(),
      name: input.name,
      body: input.body,
      color: input.color,
      x: input.x,
      y: input.y,
      rot: input.rot,
      createdAt: Date.now(),
    };
    ensureLocal().push(note);
    return note;
  }
  const res = await fetch(`${WALL_API_URL}/api/messages`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(detail || `post failed: ${res.status}`);
  }
  const data = (await res.json()) as { note: WallNote };
  return data.note;
}
