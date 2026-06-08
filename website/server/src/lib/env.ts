// Minimal shape of the Cloudflare Rate Limiting binding (see wrangler.toml
// [[ratelimits]]). Declared locally so we don't depend on a specific
// workers-types version. Optional in Env: if the binding is ever absent (e.g.
// removed from config), the GET handler degrades to no rate limiting.
export interface RateLimit {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

// Bindings + secrets available to the Worker. Add new ones here as features grow.
export interface Env {
  DB: D1Database; // single D1 database, shared by all features
  AI: Ai; // Workers AI (free tier) — used by the sweep's low-quality judge
  RL?: RateLimit; // per-IP GET flood guard (Cloudflare Rate Limiting binding)
  RL_ADMIN?: RateLimit; // per-IP throttle for the admin endpoints (verify + admin delete)
  ALLOWED_ORIGIN: string; // comma-separated CORS allow-list
  TURNSTILE_SECRET: string; // wrangler secret put TURNSTILE_SECRET
  IP_SALT: string; // wrangler secret put IP_SALT
  ADMIN_TOKEN: string; // wrangler secret put ADMIN_TOKEN — gates panel moderation
}
