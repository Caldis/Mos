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
export const NOTE_SIZE = 198; // px — full size (desktop + compose)
export const CANVAS_PAD = { margin: 48, top: 104, tray: 124 };

// Placed notes are capped a bit below the compose size (PLACED_MAX) so more fit
// on the wall, and shrink further on a narrow phone canvas. Width-driven (~0.33
// of the canvas, clamped 100–PLACED_MAX): desktop/tablet sit at PLACED_MAX, a
// 380px phone ≈125px. Composing always uses the larger NOTE_SIZE — a shrunk card
// is too cramped to type in.
const PLACED_MAX = 170;
export function noteSizeFor(canvasW: number): number {
  if (!canvasW) return PLACED_MAX;
  return Math.round(Math.min(PLACED_MAX, Math.max(100, canvasW * 0.33)));
}

// Phones also get tighter side insets so notes can reach closer to the edges.
export function canvasPadFor(canvasW: number): typeof CANVAS_PAD {
  if (canvasW > 0 && canvasW < 560) return { ...CANVAS_PAD, margin: 20 };
  return CANVAS_PAD;
}

export interface SafeArea {
  minX: number;
  maxX: number;
  minY: number;
  maxY: number;
}

// The rectangle a note's CENTER may occupy (px): keeps the whole sticky on the
// canvas and clear of the header (top) and tray (bottom). Single source of truth
// for every placement interaction — draft drag-constraints, drop clamping, the
// tray-drag ghost, and the click-to-place search all derive their bounds here,
// so a note can never be steered under the chrome no matter how it's placed.
export function safeArea(
  canvasW: number,
  canvasH: number,
  pad: { margin: number; top: number; tray: number },
  half: number,
): SafeArea {
  const minX = pad.margin + half;
  const minY = pad.top + half;
  return {
    minX,
    minY,
    maxX: Math.max(minX, canvasW - pad.margin - half),
    maxY: Math.max(minY, canvasH - pad.tray - half),
  };
}

// Clamp a point (px) into the safe area.
export function clampToSafeArea(x: number, y: number, a: SafeArea): { x: number; y: number } {
  return {
    x: Math.min(a.maxX, Math.max(a.minX, x)),
    y: Math.min(a.maxY, Math.max(a.minY, y)),
  };
}

// Where to drop a note that was *clicked* (not dragged) off the tray: the
// emptiest spot on the wall. This is the largest-empty-circle problem — the
// point farthest from every existing note — solved with a discretized grid
// search (the standard, deterministic approximation; the exact optimum sits at
// a Voronoi vertex, which is overkill here).
//
// For each grid candidate the "clearance" is the radius of the biggest circle
// that fits inside the allowed center-rectangle AND touches no note, i.e.
// min(distance to nearest note, distance to the rectangle edge). Counting the
// edge as an obstacle means an empty canvas resolves to dead center, while a
// crowded one finds the widest interior gap without hugging a wall. Ties break
// toward the center for a calm, predictable landing. Distances are in px so a
// non-square (portrait phone) canvas isn't distorted.
export function sparsestSpot(
  notes: ReadonlyArray<{ x: number; y: number }>,
  canvasW: number,
  canvasH: number,
  pad: { margin: number; top: number; tray: number },
  half: number,
): { x: number; y: number } {
  // Allowed range for a note's CENTER — shared with every other drag interaction.
  const { minX, maxX, minY, maxY } = safeArea(canvasW, canvasH, pad, half);
  // Unmeasured / too-small canvas: fall back to the historical center default.
  if (!(maxX > minX) || !(maxY > minY)) return { x: 0.5, y: 0.4 };

  const obstacles = notes.map((n) => ({ x: n.x * canvasW, y: n.y * canvasH }));
  const cx0 = (minX + maxX) / 2;
  const cy0 = (minY + maxY) / 2;

  const COLS = 11;
  const ROWS = 11;
  let best = { x: cx0, y: cy0 };
  let bestScore = -Infinity;
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      const px = minX + (maxX - minX) * (c / (COLS - 1));
      const py = minY + (maxY - minY) * (r / (ROWS - 1));
      // Radius of the largest circle here that stays in-bounds and clears notes.
      let clear = Math.min(px - minX, maxX - px, py - minY, maxY - py);
      for (const o of obstacles) {
        const d = Math.hypot(px - o.x, py - o.y);
        if (d < clear) clear = d;
      }
      // Clearance dominates; the tiny center pull only settles near-ties.
      const score = clear - 0.02 * Math.hypot(px - cx0, py - cy0);
      if (score > bestScore) {
        bestScore = score;
        best = { x: px, y: py };
      }
    }
  }
  return { x: best.x / canvasW, y: best.y / canvasH };
}

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

// Client-side mirror of the server link rule (server/src/lib/moderation.ts:
// STRONG_LINK + BARE_SPAM_DOMAIN). Used ONLY to warn the user as they type —
// the Worker re-checks and is the real authority. Keep the two in sync: if the
// banned-TLD set changes there, change it here too. The ad-keyword blocklist is
// intentionally NOT mirrored (it stays server-side, private, and the server
// surfaces a "spam" reason instead).
const LINK_RE =
  /(https?:\/\/|www\.|:\/\/|\b[a-z0-9-]+\.[a-z]{2,}\/\S|\b[a-z0-9-]+\.(?:com|net|org|cn|xyz|top|vip|shop|club|live|link|cc|tk|ru|info|biz|online|site|store|fun|pro|wang|ltd|icu)\b)/i;

// True when the text contains something the server will reject as a link.
export function bodyHasLink(text: string): boolean {
  return LINK_RE.test(text);
}

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

// --- Admin (panel moderation) -----------------------------------------------
// A single shared secret unlocks panel moderation (delete ANY note). It lives in
// sessionStorage — cleared when the tab closes, safer than localStorage for a
// privileged credential — and rides on the x-wall-admin header. The Worker is the
// only authority: without a valid token every admin request is rejected, so the
// client-side "admin mode" is purely a UI affordance, not a security boundary.
const ADMIN_TOKEN_KEY = "wall_admin";
// Same-tab listeners can't use the native `storage` event (it only fires in OTHER
// tabs), so unlock/lock dispatch this so the current tab's hook re-renders too.
export const WALL_ADMIN_EVENT = "wall-admin-change";

export function getAdminToken(): string {
  if (typeof sessionStorage === "undefined") return "";
  try {
    return sessionStorage.getItem(ADMIN_TOKEN_KEY) ?? "";
  } catch {
    return "";
  }
}

export function isAdminUnlocked(): boolean {
  return getAdminToken().length > 0;
}

function setAdminToken(token: string): void {
  try {
    if (token) sessionStorage.setItem(ADMIN_TOKEN_KEY, token);
    else sessionStorage.removeItem(ADMIN_TOKEN_KEY);
  } catch {
    // private mode / quota — admin mode just won't persist; ignore.
  }
  if (typeof window !== "undefined") window.dispatchEvent(new Event(WALL_ADMIN_EVENT));
}

// Validate a candidate admin token against the Worker. On success it's stored and
// admin mode unlocks; on any failure storage is cleared. Returns whether it passed.
export async function verifyAdmin(token: string): Promise<boolean> {
  const candidate = token.trim();
  if (!SERVER_URL) {
    // Local seed mode (no backend): accept any non-empty token so the admin UI is
    // exercisable offline against the seed notes.
    setAdminToken(candidate);
    return candidate.length > 0;
  }
  try {
    const res = await fetch(`${SERVER_URL}/wall/admin`, {
      headers: { accept: "application/json", "x-wall-admin": candidate },
    });
    if (!res.ok) {
      setAdminToken("");
      return false;
    }
    setAdminToken(candidate);
    return true;
  } catch {
    setAdminToken("");
    return false;
  }
}

export function lockAdmin(): void {
  setAdminToken("");
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

// --- Local snapshot cache ---------------------------------------------------
// Persist the last server fetch so reloads within the TTL render instantly
// WITHOUT re-hitting the API. SWR's in-memory dedupe only lasts the session, so
// a reload would otherwise re-fetch every time; this stops a user (or a tab they
// keep reopening) from hammering /wall/messages. One key, overwritten each fetch
// — at most FETCH_LIMIT notes ≈ a couple hundred KB, far under the ~5MB
// localStorage quota, so it can't grow unbounded.
const NOTES_CACHE_KEY = "wall_notes_cache";
const NOTES_CACHE_TTL = 5 * 60_000; // 5 min

function readNotesCache(): ServerNote[] | null {
  try {
    const raw = localStorage.getItem(NOTES_CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { ts?: number; notes?: ServerNote[] };
    if (!parsed || typeof parsed.ts !== "number" || !Array.isArray(parsed.notes)) return null;
    if (Date.now() - parsed.ts >= NOTES_CACHE_TTL) return null; // stale → refetch
    return parsed.notes;
  } catch {
    return null;
  }
}

function writeNotesCache(notes: ServerNote[]): void {
  try {
    localStorage.setItem(NOTES_CACHE_KEY, JSON.stringify({ ts: Date.now(), notes }));
  } catch {
    // private mode / quota exceeded — caching is best-effort, just skip it.
  }
}

// Drop the snapshot after the user changes the wall (post / delete) so the next
// load reflects their action instead of serving a stale copy.
function invalidateNotesCache(): void {
  try {
    localStorage.removeItem(NOTES_CACHE_KEY);
  } catch {
    // ignore
  }
}

async function fetchNotes(): Promise<WallNote[]> {
  // Return a copy so the SWR cache never aliases the in-memory store
  // (otherwise an optimistic append would duplicate the just-posted note).
  if (!SERVER_URL) return [...ensureLocal()];

  // Fresh local snapshot → skip the network entirely. `mine` was baked in by the
  // server (via x-wall-owner) when cached, and the owner token is stable, so it
  // stays correct across reloads.
  if (typeof localStorage !== "undefined") {
    const cached = readNotesCache();
    if (cached) return cached.map(fromServer);
  }

  const res = await fetch(`${SERVER_URL}/wall/messages`, {
    headers: { accept: "application/json", "x-wall-owner": getOwner() },
  });
  if (!res.ok) throw new Error(`wall fetch failed: ${res.status}`);
  const data = (await res.json()) as { notes: ServerNote[] };
  if (typeof localStorage !== "undefined") writeNotesCache(data.notes);
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
  invalidateNotesCache(); // their new note must show on the next load
  return fromServer(data.note);
}

// Soft-delete (hide) a note. Normally owner-scoped: the server checks
// owner === note.owner via x-wall-owner, so you can only remove your own. When an
// admin token is unlocked it also rides along as x-wall-admin; the Worker then
// lets it hide ANY note (tagged 'admin-del'). The server is the authority — a
// stray admin header without a valid token is simply rejected.
export async function deleteNote(id: string): Promise<void> {
  if (!SERVER_URL) {
    const list = ensureLocal();
    const i = list.findIndex((n) => n.id === id);
    if (i >= 0) list.splice(i, 1);
    return;
  }
  const admin = getAdminToken();
  const res = await fetch(`${SERVER_URL}/wall/messages/${id}`, {
    method: "DELETE",
    headers: { "x-wall-owner": getOwner(), ...(admin ? { "x-wall-admin": admin } : {}) },
  });
  if (!res.ok) {
    let reason = `delete failed: ${res.status}`;
    try {
      const data = (await res.json()) as { error?: string };
      if (data?.error) reason = data.error;
    } catch {
      // non-JSON body
    }
    throw new Error(reason);
  }
  invalidateNotesCache(); // the hidden note must be gone on the next load
}

// --- Admin moderation ledger -------------------------------------------------
// EVERY note (visible AND hidden) with its state, so the panel can list all and
// filter by hide_reason. Admin-only; the public GET never reveals hide_reason.
// `x`/`y` are included so a restored note can be re-placed on the canvas.
export interface AdminNote {
  id: string;
  body: string;
  color: NoteColor;
  name: string | null;
  x: number;
  y: number;
  createdAt: number;
  hidden: boolean;
  hideReason: string | null;
}

async function fetchAdminNotes(): Promise<AdminNote[]> {
  const admin = getAdminToken();
  if (!admin) return [];
  if (!SERVER_URL) {
    // Local seed mode: surface the seed notes as the ledger, faking a couple of
    // ai-low-quality flags so the filter + actions are exercisable offline.
    return ensureLocal().map((n, i) => ({
      id: n.id,
      body: n.body,
      color: n.color,
      name: n.name,
      x: n.x,
      y: n.y,
      createdAt: n.createdAt,
      hidden: false,
      hideReason: i < 2 ? "ai-low-quality" : null,
    }));
  }
  const res = await fetch(`${SERVER_URL}/wall/admin/notes`, {
    headers: { accept: "application/json", "x-wall-admin": admin },
  });
  if (!res.ok) throw new Error(`admin notes fetch failed: ${res.status}`);
  const data = (await res.json()) as { notes: AdminNote[] };
  return data.notes;
}

// SWR hook for the ledger. enabled=false (not admin) → null key → no fetch at all.
// Manual revalidation only: it changes when the admin acts or the hourly sweep
// runs, never on window focus.
export function useAdminNotes(enabled: boolean) {
  return useSWR<AdminNote[]>(enabled ? "wall-admin-notes" : null, fetchAdminNotes, {
    revalidateOnFocus: false,
    revalidateOnReconnect: false,
  });
}

// Un-hide a note (admin) — inverse of the admin delete. Throws on failure so the
// caller can surface a per-row error and roll back.
export async function restoreNote(id: string): Promise<void> {
  const admin = getAdminToken();
  if (!SERVER_URL) return; // seed mode has nothing hidden to restore
  if (!admin) throw new Error("not admin");
  const res = await fetch(`${SERVER_URL}/wall/admin/notes/${id}/restore`, {
    method: "POST",
    headers: { "x-wall-admin": admin },
  });
  if (!res.ok) throw new Error(`restore failed: ${res.status}`);
  invalidateNotesCache(); // the restored note must reappear on the next load
}

// Hide every AI-flagged note in ONE request (server-side bulk UPDATE → 'admin-del'),
// returning the count. Looping per-note DELETEs would trip RL_ADMIN after 10.
export async function hideAllFlagged(): Promise<number> {
  const admin = getAdminToken();
  if (!admin) return 0;
  if (!SERVER_URL) {
    const list = ensureLocal();
    const ids = list.slice(0, 2).map((n) => n.id);
    for (const id of ids) {
      const i = list.findIndex((n) => n.id === id);
      if (i >= 0) list.splice(i, 1);
    }
    return ids.length;
  }
  const res = await fetch(`${SERVER_URL}/wall/admin/flagged/hide`, {
    method: "POST",
    headers: { "x-wall-admin": admin },
  });
  if (!res.ok) throw new Error(`hide all failed: ${res.status}`);
  const data = (await res.json()) as { hidden: number };
  invalidateNotesCache();
  return data.hidden;
}
