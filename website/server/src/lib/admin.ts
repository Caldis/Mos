// Admin authentication for panel moderation. A single shared secret
// (env.ADMIN_TOKEN, a Worker secret) is sent in the `x-wall-admin` header. The
// real defense is the token's entropy — use `openssl rand -base64 32` (256-bit),
// so brute force is mathematically infeasible. The constant-time compare here
// only removes a timing side channel; the per-IP RL_ADMIN rate limit (applied in
// the handlers) caps abuse before any crypto runs.
import type { Env } from "./env";

// Constant-time string equality — never short-circuits on the first differing
// character, so response timing can't recover the token prefix-by-prefix. A
// length mismatch returns immediately, but the token's length is not the secret.
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// True when `token` matches the configured admin secret. Fails closed: if the
// ADMIN_TOKEN secret is unset (undefined before `wrangler secret put`) or empty,
// nobody is authorized — and the `?? ""` keeps a missing secret from throwing on
// `.length`, so a probe with an x-wall-admin header gets a clean 401, not a 500.
export function isAdmin(env: Env, token: string): boolean {
  const secret = env.ADMIN_TOKEN ?? "";
  return token.length > 0 && secret.length > 0 && timingSafeEqual(token, secret);
}
