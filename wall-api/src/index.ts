/**
 * Mos Wall API — Cloudflare Worker.
 *
 * The static site (GitHub Pages, https://mos.caldis.me/wall) calls this at runtime.
 *
 * Endpoints:
 *   GET     /api/messages   list visible notes (newest first, max 800)
 *   POST    /api/messages   create a note (Turnstile + rate limit + filter)
 *   OPTIONS /api/messages   CORS preflight
 *
 * No PATCH: a note's position is fixed at POST time and locked thereafter
 * (decision D3 — "stick it and it stays"). That removes the owner-authorized
 * mutation path entirely, so existing rows are immutable from the public API.
 */

export interface Env {
  DB: D1Database;
  ALLOWED_ORIGIN: string; // comma-separated list, e.g. "https://mos.caldis.me"
  TURNSTILE_SECRET: string; // wrangler secret put TURNSTILE_SECRET
  IP_SALT: string; // wrangler secret put IP_SALT
}

const PALETTE = new Set(["amber", "rose", "sky", "mint", "lilac", "blush"]);
const MAX_BODY = 180;
const MAX_NAME = 24;
const FETCH_LIMIT = 800;

// Per-IP-hash rate limits (decision D2).
const RL_PER_MINUTE = 1;
const RL_PER_HOUR = 20;

// --- helpers ---------------------------------------------------------------

function pickOrigin(env: Env, reqOrigin: string | null): string {
  const allow = env.ALLOWED_ORIGIN.split(",").map((s) => s.trim()).filter(Boolean);
  if (reqOrigin && allow.includes(reqOrigin)) return reqOrigin;
  // Fall back to the canonical origin so disallowed browsers get blocked by CORS,
  // while header-less clients (curl) still get a usable response.
  return allow[0] ?? "*";
}

function corsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, x-wall-owner",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function json(data: unknown, status: number, origin: string): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders(origin) },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// 2+ URLs in a body is a strong spam signal. Reject. The plan's alternative is
// to soft-hide (INSERT with hidden = 1) instead — flip this if you'd rather
// shadow-ban than bounce.
function looksSpammy(body: string): boolean {
  const links = body.match(/https?:\/\/|www\./gi);
  return (links?.length ?? 0) >= 2;
}

// --- turnstile -------------------------------------------------------------

async function verifyTurnstile(env: Env, token: string, ip: string): Promise<boolean> {
  const form = new FormData();
  form.append("secret", env.TURNSTILE_SECRET);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: form,
  });
  if (!res.ok) return false;
  const data = (await res.json()) as { success?: boolean };
  return data.success === true;
}

// --- row mapping -----------------------------------------------------------

interface NoteRow {
  id: number;
  body: string;
  color: string;
  x: number;
  y: number;
  name: string | null;
  owner: string;
  created_at: number;
}

// Public shape. Critically, row.owner is NEVER emitted — only the boolean
// `mine`, so one client can't learn (and impersonate) another's token.
function toPublicNote(row: NoteRow, owner: string) {
  return {
    id: String(row.id),
    body: row.body,
    color: row.color,
    x: row.x,
    y: row.y,
    name: row.name,
    createdAt: row.created_at,
    mine: owner !== "" && row.owner === owner,
  };
}

// --- handlers --------------------------------------------------------------

async function handleGet(env: Env, request: Request, origin: string): Promise<Response> {
  const owner = request.headers.get("x-wall-owner") ?? "";
  const { results } = await env.DB.prepare(
    `SELECT id, body, color, x, y, name, owner, created_at
       FROM notes
      WHERE hidden = 0
      ORDER BY created_at DESC
      LIMIT ?`,
  )
    .bind(FETCH_LIMIT)
    .all<NoteRow>();
  const notes = (results ?? []).map((r) => toPublicNote(r, owner));
  return json({ notes }, 200, origin);
}

async function handlePost(env: Env, request: Request, origin: string): Promise<Response> {
  let input: Record<string, unknown>;
  try {
    input = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "invalid json" }, 400, origin);
  }

  const body = typeof input.body === "string" ? input.body.trim() : "";
  const color = typeof input.color === "string" ? input.color : "";
  const x = Number(input.x);
  const y = Number(input.y);
  const name = typeof input.name === "string" ? input.name.trim() : "";
  const owner = typeof input.owner === "string" ? input.owner.trim() : "";
  const turnstileToken = typeof input.turnstileToken === "string" ? input.turnstileToken : "";

  // Field validation (server re-checks everything the client claims to enforce).
  if (body.length < 1 || body.length > MAX_BODY) return json({ error: "body length" }, 422, origin);
  if (!PALETTE.has(color)) return json({ error: "bad color" }, 422, origin);
  if (!Number.isFinite(x) || x < 0 || x > 1 || !Number.isFinite(y) || y < 0 || y > 1)
    return json({ error: "bad position" }, 422, origin);
  if (name.length > MAX_NAME) return json({ error: "name too long" }, 422, origin);
  if (!owner) return json({ error: "missing owner" }, 422, origin);
  if (!turnstileToken) return json({ error: "missing turnstile token" }, 422, origin);

  const ip = request.headers.get("cf-connecting-ip") ?? "";

  // 1) Bot check.
  if (!(await verifyTurnstile(env, turnstileToken, ip)))
    return json({ error: "turnstile failed" }, 403, origin);

  // 2) Rate limit by irreversible IP hash (salt is a Worker secret, so the
  //    stored hash can't be reversed back to an IP).
  const ipHash = (await sha256Hex(ip + env.IP_SALT)).slice(0, 32);
  const now = Date.now();
  const rl = await env.DB.prepare(
    `SELECT SUM(CASE WHEN created_at > ? THEN 1 ELSE 0 END) AS last_min,
            COUNT(*) AS last_hour
       FROM notes
      WHERE ip_hash = ? AND created_at > ?`,
  )
    .bind(now - 60_000, ipHash, now - 3_600_000)
    .first<{ last_min: number | null; last_hour: number | null }>();
  if (Number(rl?.last_min ?? 0) >= RL_PER_MINUTE || Number(rl?.last_hour ?? 0) >= RL_PER_HOUR)
    return json({ error: "rate limited" }, 429, origin);

  // 3) Content filter.
  if (looksSpammy(body)) return json({ error: "too many links" }, 422, origin);

  // 4) Insert.
  const res = await env.DB.prepare(
    `INSERT INTO notes (body, color, x, y, name, owner, created_at, hidden, ip_hash)
     VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)`,
  )
    .bind(body, color, x, y, name || null, owner, now, ipHash)
    .run();

  const note = toPublicNote(
    { id: res.meta.last_row_id as number, body, color, x, y, name: name || null, owner, created_at: now },
    owner,
  );
  return json({ note }, 201, origin);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = pickOrigin(env, request.headers.get("Origin"));

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    // Sanity/health check for the custom domain.
    if (url.pathname === "/" || url.pathname === "") {
      return new Response("mos-wall ok", { status: 200, headers: corsHeaders(origin) });
    }

    if (url.pathname === "/api/messages") {
      if (request.method === "GET") return handleGet(env, request, origin);
      if (request.method === "POST") return handlePost(env, request, origin);
      return json({ error: "method not allowed" }, 405, origin);
    }

    return json({ error: "not found" }, 404, origin);
  },
};
