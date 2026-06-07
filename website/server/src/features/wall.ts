// Wall feature — the shared sticky-note board. One of possibly many features
// hosted by this Worker; everything wall-specific (schema, validation, routes)
// lives here. Routes are registered in ../index.ts under the /wall prefix.
import type { Env } from "../lib/env";
import { json } from "../lib/http";
import { verifyTurnstile } from "../lib/turnstile";
import { sha256Hex } from "../lib/hash";
import { spamReason } from "../lib/moderation";
import { looksLowQuality } from "../lib/aiJudge";

const PALETTE = new Set(["amber", "rose", "sky", "mint", "lilac", "blush"]);
const MAX_BODY = 180;
const MAX_NAME = 24;
const FETCH_LIMIT = 800;

// Per-IP-hash rate limits (decision D2).
// Short window counts only VISIBLE notes, so soft-deleting your just-posted note
// (hidden=1) frees the slot and lets you repost immediately.
const RL_VISIBLE_WINDOW_MS = 2 * 60_000; // 2 minutes
const RL_VISIBLE_MAX = 1;
// Hard hourly ceiling counts ALL posts (incl. deleted), so the "delete unlocks"
// exception can't be abused to churn unlimited rows.
const RL_HOURLY_MAX = 8;

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

// Public shape. row.owner is NEVER emitted — only the boolean `mine`, so one
// client can't learn (and impersonate) another's token.
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

// Re-scan this many of the newest visible notes per sweep. New spam is recent,
// and the wall only holds a few hundred notes, so this stays a cheap query.
const SWEEP_LIMIT = 800;

// Cap AI judgements per sweep so Workers AI usage stays tiny: at most this many
// not-yet-judged notes are sent to the model each run. The existing backlog
// drains over a few hourly sweeps; after that it's just the handful of new notes.
const AI_SWEEP_LIMIT = 25;

// Hard ceiling on AI judgements per UTC day (tracked in the ai_budget table) — a
// backstop so a sustained note flood can't run up Workers AI usage even across
// many sweeps. The free tier is ~10k neurons/day and each judge costs a fraction
// of that, so 150/day stays comfortably free. Tune to taste.
const AI_DAILY_MAX = 150;

// GET /wall/messages — list visible notes (newest first, max 800). Send
// `x-wall-owner` to get a per-note `mine`.
export async function handleGet(env: Env, request: Request, origin: string): Promise<Response> {
  // Cheap per-IP flood guard: a burst gets a 429 before any D1 work. Optional
  // binding (env.RL) so the handler still works if it isn't configured.
  if (env.RL) {
    const ip = request.headers.get("cf-connecting-ip") ?? "";
    const { success } = await env.RL.limit({ key: ip || "anon" });
    if (!success) return json({ error: "rate limited" }, 429, origin);
  }

  const owner = request.headers.get("x-wall-owner") ?? "";
  const { results } = await env.DB.prepare(
    `SELECT id, body, color, x, y, name, owner, created_at
       FROM wall_notes
      WHERE hidden = 0
      ORDER BY created_at DESC
      LIMIT ?`,
  )
    .bind(FETCH_LIMIT)
    .all<NoteRow>();
  const notes = (results ?? []).map((r) => toPublicNote(r, owner));
  return json({ notes }, 200, origin);
}

// POST /wall/messages — create a note. Position is set here and locked (D3).
export async function handlePost(env: Env, request: Request, origin: string): Promise<Response> {
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

  // 2) Rate limit by irreversible IP hash (salt is a Worker secret).
  const ipHash = (await sha256Hex(ip + env.IP_SALT)).slice(0, 32);
  const now = Date.now();
  const rl = await env.DB.prepare(
    `SELECT SUM(CASE WHEN created_at > ? AND hidden = 0 THEN 1 ELSE 0 END) AS recent_visible,
            COUNT(*) AS hourly_all
       FROM wall_notes
      WHERE ip_hash = ? AND created_at > ?`,
  )
    .bind(now - RL_VISIBLE_WINDOW_MS, ipHash, now - 3_600_000)
    .first<{ recent_visible: number | null; hourly_all: number | null }>();
  if (Number(rl?.recent_visible ?? 0) >= RL_VISIBLE_MAX || Number(rl?.hourly_all ?? 0) >= RL_HOURLY_MAX)
    return json({ error: "rate limited" }, 429, origin);

  // 3) Content filter — links are banned and obvious ad spam is rejected. Same
  // logic the scheduled sweep uses, so the door and the broom agree (moderation).
  const reason = spamReason(body, name);
  if (reason) return json({ error: reason }, 422, origin);

  // 4) Insert.
  const res = await env.DB.prepare(
    `INSERT INTO wall_notes (body, color, x, y, name, owner, created_at, hidden, ip_hash)
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

// DELETE /wall/messages/:id — soft-delete (hidden=1) a note you own. The owner
// token comes from the x-wall-owner header. You can only hide your own notes,
// and other users' owner tokens are never exposed, so this can't wipe the wall.
export async function handleDelete(
  env: Env,
  request: Request,
  origin: string,
  id: string,
): Promise<Response> {
  const owner = request.headers.get("x-wall-owner") ?? "";
  if (!owner) return json({ error: "missing owner" }, 422, origin);

  const res = await env.DB.prepare(
    `UPDATE wall_notes SET hidden = 1, hide_reason = 'user' WHERE id = ? AND owner = ? AND hidden = 0`,
  )
    .bind(Number(id), owner)
    .run();

  // No row changed → not yours, gone, or already hidden. Don't reveal which.
  if (!res.meta.changes) return json({ error: "not found" }, 404, origin);
  return json({ ok: true }, 200, origin);
}

// Scheduled moderation sweep, wired to a Cron Trigger via the `scheduled` handler
// in ../index.ts. Two passes:
//   1. Rule spam — re-scan visible notes; hide outright (hide_reason='spam').
//      Catches spam that landed before the rules tightened.
//   2. AI low-quality — ask Workers AI whether each not-yet-judged note is
//      gibberish; FLAG (hide_reason='ai-low-quality'), never hide. A human
//      decides. Each note is judged once (ai_checked), capped per run, so AI
//      usage is minimal.
// Read-then-write is safe: the sweep is the only content-based writer, runs
// single-instance on the cron, and a missed note is simply caught next hour.
export async function sweep(env: Env): Promise<{ spam: number; flagged: number }> {
  // Pass 1 — rule spam (cheap, no AI).
  const { results } = await env.DB.prepare(
    `SELECT id, body, name
       FROM wall_notes
      WHERE hidden = 0
      ORDER BY created_at DESC
      LIMIT ?`,
  )
    .bind(SWEEP_LIMIT)
    .all<{ id: number; body: string; name: string | null }>();

  const spamIds = (results ?? []).filter((r) => spamReason(r.body, r.name) !== null).map((r) => r.id);
  if (spamIds.length) {
    const ph = spamIds.map(() => "?").join(",");
    await env.DB.prepare(
      `UPDATE wall_notes SET hidden = 1, hide_reason = 'spam' WHERE id IN (${ph})`,
    )
      .bind(...spamIds)
      .run();
  }

  // Pass 2 — AI low-quality flag. Triple-capped so a flood can't run up AI usage:
  // once-per-note (ai_checked), per-run (AI_SWEEP_LIMIT), and per-UTC-day
  // (AI_DAILY_MAX via the ai_budget table). Only notes that survived pass 1
  // (hidden=0) and haven't been judged are eligible.
  const day = new Date().toISOString().slice(0, 10);
  const spent =
    (await env.DB.prepare(`SELECT count FROM ai_budget WHERE day = ?`).bind(day).first<{ count: number }>())
      ?.count ?? 0;
  const aiLimit = Math.min(AI_SWEEP_LIMIT, Math.max(0, AI_DAILY_MAX - spent));

  const judged: number[] = [];
  const flagged: number[] = [];
  if (aiLimit > 0) {
    const { results: pending } = await env.DB.prepare(
      `SELECT id, body, name
         FROM wall_notes
        WHERE hidden = 0 AND ai_checked = 0
        ORDER BY created_at DESC
        LIMIT ?`,
    )
      .bind(aiLimit)
      .all<{ id: number; body: string; name: string | null }>();

    for (const r of pending ?? []) {
      judged.push(r.id);
      if (await looksLowQuality(env, r.body, r.name)) flagged.push(r.id);
    }
    if (judged.length) {
      // Mark every judged note checked, so it's never re-sent to the model…
      const ph = judged.map(() => "?").join(",");
      await env.DB.prepare(`UPDATE wall_notes SET ai_checked = 1 WHERE id IN (${ph})`)
        .bind(...judged)
        .run();
      // …and record today's spend so the daily cap holds across sweeps.
      await env.DB.prepare(
        `INSERT INTO ai_budget (day, count) VALUES (?, ?)
         ON CONFLICT(day) DO UPDATE SET count = count + excluded.count`,
      )
        .bind(day, judged.length)
        .run();
    }
    if (flagged.length) {
      // Tag the gibberish ones for review WITHOUT hiding them (hidden stays 0).
      const ph = flagged.map(() => "?").join(",");
      await env.DB.prepare(
        `UPDATE wall_notes SET hide_reason = 'ai-low-quality' WHERE id IN (${ph}) AND hidden = 0`,
      )
        .bind(...flagged)
        .run();
    }
  }

  return { spam: spamIds.length, flagged: flagged.length };
}
