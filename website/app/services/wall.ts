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
  rot: number; // degrees — DERIVED from id (rotFromId), never persisted
  createdAt: number;
  // True only for notes this browser authored (server decides via x-wall-owner).
  mine: boolean;
}

export interface NewNoteInput {
  name: string;
  body: string;
  color: NoteColor;
  x: number;
  y: number;
  // Cloudflare Turnstile token; required once the Worker backend is live.
  turnstileToken?: string;
}

export const SERVER_URL =
  process.env.NEXT_PUBLIC_SERVER_URL?.replace(/\/$/, "") ?? "";

// Stable tilt in [-4, 4] derived from the note id, so a note always leans the
// same way without persisting a `rot` field. (Same hash style as Java's
// String.hashCode; the |0 keeps it a 32-bit int.)
export function rotFromId(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
  return Math.round(((Math.abs(h) % 81) / 10 - 4) * 10) / 10;
}

// Per-browser owner token. The server uses it (via the x-wall-owner header) to
// mark which notes are `mine`; it is never shown to other users. Stored in
// localStorage so it survives reloads. Guarded for SSR / missing crypto.
export function getOwner(): string {
  const FALLBACK = () => `o_${Date.now().toString(36)}_${Math.random().toString(36).slice(2)}`;
  if (typeof localStorage === "undefined") return FALLBACK();
  try {
    let owner = localStorage.getItem("wall_owner");
    if (!owner) {
      owner = typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID() : FALLBACK();
      localStorage.setItem("wall_owner", owner);
    }
    return owner;
  } catch {
    return FALLBACK();
  }
}

// Shape of a single note as the Worker returns it (no derived `rot`).
type ServerNote = Omit<WallNote, "rot" | "name"> & { name: string | null };

function fromServer(note: ServerNote): WallNote {
  return { ...note, name: note.name ?? "", rot: rotFromId(note.id) };
}

// Demo seed shown until the Cloudflare Worker is configured. `rot` is derived
// from the id at read time, and seed notes are never `mine`.
const SEED_NOTES: Omit<WallNote, "rot" | "mine">[] = [
  { id: "seed-1", name: "Caldis", body: "Welcome to the wall — peel a sticky off the tray below and leave a note.", color: "amber", x: 0.5, y: 0.25, createdAt: 1717000000000 },
  { id: "seed-2", name: "Lin", body: "Mos 让我的滚轮终于顺了，谢谢你 🙏", color: "mint", x: 0.23, y: 0.52, createdAt: 1717100000000 },
  { id: "seed-3", name: "Aki", body: "scrolling feels like butter now", color: "sky", x: 0.75, y: 0.42, createdAt: 1717200000000 },
  { id: "seed-4", name: "mira", body: "trackpad person on a mouse — finally bearable", color: "lilac", x: 0.62, y: 0.68, createdAt: 1717300000000 },
  { id: "seed-5", name: "あお", body: "毎日つかってます。ありがとう！", color: "blush", x: 0.35, y: 0.78, createdAt: 1717400000000 },
];

let localNotes: WallNote[] | null = null;

function ensureLocal(): WallNote[] {
  if (!localNotes) {
    localNotes = SEED_NOTES.map((n) => ({ ...n, rot: rotFromId(n.id), mine: false }));
  }
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
  if (!SERVER_URL) return [...ensureLocal()];
  const res = await fetch(`${SERVER_URL}/wall/messages`, {
    headers: { accept: "application/json", "x-wall-owner": getOwner() },
  });
  if (!res.ok) throw new Error(`wall fetch failed: ${res.status}`);
  const data = (await res.json()) as { notes: ServerNote[] };
  return data.notes.map(fromServer);
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
  if (!SERVER_URL) {
    const id = makeId();
    const note: WallNote = {
      id,
      name: input.name,
      body: input.body,
      color: input.color,
      x: input.x,
      y: input.y,
      rot: rotFromId(id),
      createdAt: Date.now(),
      mine: true,
    };
    ensureLocal().push(note);
    return note;
  }
  const res = await fetch(`${SERVER_URL}/wall/messages`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      body: input.body,
      color: input.color,
      x: input.x,
      y: input.y,
      name: input.name,
      owner: getOwner(),
      turnstileToken: input.turnstileToken,
    }),
  });
  if (!res.ok) {
    // The Worker returns { error: "<reason>" } on failure; surface that reason
    // so the UI can map it to friendly copy (rate limited, turnstile failed…).
    let reason = `post failed: ${res.status}`;
    try {
      const data = (await res.json()) as { error?: string };
      if (data?.error) reason = data.error;
    } catch {
      // non-JSON body — keep the status-based message
    }
    throw new Error(reason);
  }
  const data = (await res.json()) as { note: ServerNote };
  return fromServer(data.note);
}
