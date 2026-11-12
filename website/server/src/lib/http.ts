import type { Env } from "./env";

// CORS allow-list is comma-separated; echo back the request origin when allowed
// so multiple sites (prod + local dev) can share one Worker.
export function pickOrigin(env: Env, reqOrigin: string | null): string {
  const allow = env.ALLOWED_ORIGIN.split(",").map((s) => s.trim()).filter(Boolean);
  if (reqOrigin && allow.includes(reqOrigin)) return reqOrigin;
  // Fall back to the canonical origin so disallowed browsers get blocked by CORS,
  // while header-less clients (curl) still get a usable response.
  return allow[0] ?? "*";
}

export function corsHeaders(origin: string): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, x-wall-owner, x-wall-admin",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

export function json(data: unknown, status: number, origin: string): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders(origin) },
  });
}
