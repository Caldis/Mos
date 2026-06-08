/**
 * Mos server — Cloudflare Worker.
 *
 * One Worker at api.mos.caldis.me, multiplexing feature modules by path prefix.
 * Today: the sticky-note wall (/wall/*). To add a feature, drop a module under
 * src/features/ and register its routes below; shared helpers live in src/lib/.
 */
import type { Env } from "./lib/env";
import { pickOrigin, corsHeaders, json } from "./lib/http";
import * as wall from "./features/wall";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = pickOrigin(env, request.headers.get("Origin"));

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(origin) });
    }

    // Health check for the custom domain.
    if (url.pathname === "/" || url.pathname === "") {
      return new Response("mos-server ok", { status: 200, headers: corsHeaders(origin) });
    }

    // --- feature: wall ---
    if (url.pathname === "/wall/messages") {
      if (request.method === "GET") return wall.handleGet(env, request, origin);
      if (request.method === "POST") return wall.handlePost(env, request, origin);
      return json({ error: "method not allowed" }, 405, origin);
    }
    // Admin secret check — lets the panel confirm the password before unlocking.
    if (url.pathname === "/wall/admin") {
      if (request.method === "GET") return wall.handleAdminCheck(env, request, origin);
      return json({ error: "method not allowed" }, 405, origin);
    }
    const wallNote = url.pathname.match(/^\/wall\/messages\/(\d+)$/);
    if (wallNote) {
      if (request.method === "DELETE")
        return wall.handleDelete(env, request, origin, wallNote[1]);
      return json({ error: "method not allowed" }, 405, origin);
    }

    return json({ error: "not found" }, 404, origin);
  },

  // Cron Trigger (see wrangler.toml [triggers]). Runs the moderation sweep so
  // spam that slipped past the POST-time filter gets hidden automatically.
  // waitUntil keeps the worker alive until the DB writes finish.
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(
      wall.sweep(env).then(({ spam, flagged }) => {
        if (spam || flagged) console.log(`wall sweep: hid ${spam} spam, flagged ${flagged} low-quality`);
      }),
    );
  },
};
