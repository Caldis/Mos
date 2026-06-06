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

    return json({ error: "not found" }, 404, origin);
  },
};
