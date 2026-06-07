// Bindings + secrets available to the Worker. Add new ones here as features grow.
export interface Env {
  DB: D1Database; // single D1 database, shared by all features
  AI: Ai; // Workers AI (free tier) — used by the sweep's low-quality judge
  ALLOWED_ORIGIN: string; // comma-separated CORS allow-list
  TURNSTILE_SECRET: string; // wrangler secret put TURNSTILE_SECRET
  IP_SALT: string; // wrangler secret put IP_SALT
}
