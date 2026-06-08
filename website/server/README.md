# Mos server

Cloudflare Worker + D1 backend for the Mos website. One Worker at
`mos-api.caldis.me`, multiplexing feature modules by path prefix. The static
site (GitHub Pages, `output: export`) calls it at runtime.

## Structure

```
src/
  index.ts          # top-level router: dispatch by path prefix to features
  lib/              # shared across features
    env.ts          #   Env (bindings + secrets)
    http.ts         #   CORS + json() helpers
    turnstile.ts    #   Turnstile siteverify
    hash.ts         #   sha256 (rate-limit / ip hashing)
    geo.ts          #   resolveCountry (edge geolocation -> country code)
  features/
    wall.ts         # sticky-note wall (/wall/*)
migrations/         # D1 schema (one shared database)
```

To add a feature: drop `src/features/<name>.ts`, register its routes in
`src/index.ts`, and add a `migrations/000N_<name>.sql` if it needs tables.

## Features

### wall — `/wall/messages`

| Method | Path             | Notes                                                       |
| ------ | ---------------- | ---------------------------------------------------------- |
| GET    | `/wall/messages` | visible notes, newest first, max 800. Send `x-wall-owner` for per-note `mine`. |
| POST   | `/wall/messages` | create a note: `{ body, color, x, y, name?, owner, turnstileToken }` |

No `PATCH`: a note's position is set at POST time and **locked** (decision D3 —
stick it and it stays). Rotation is not stored; the client derives it from `id`.

## Local dev

```sh
cd website/server
pnpm install          # standalone pnpm root; allowBuilds approves workerd/esbuild (pnpm 11+)
pnpm migrate:local    # apply migrations to the local SQLite
pnpm dev              # wrangler dev -> http://localhost:8787
```

Create `.dev.vars` (gitignored) so secrets exist locally. Use Cloudflare's
"always passes" Turnstile **test** secret so POST works without a real widget:

```
TURNSTILE_SECRET=1x0000000000000000000000000000000AA
IP_SALT=dev-salt
ALLOWED_ORIGIN=https://mos.caldis.me,http://localhost:3000
```

(The matching always-passes **site** key for the frontend is `1x00000000000000000000AA`.)

### curl checks

```sh
curl -s http://localhost:8787/                       # health -> "mos-server ok"
curl -s http://localhost:8787/wall/messages          # list

# create (any non-empty token passes with the test secret)
curl -s -X POST http://localhost:8787/wall/messages \
  -H 'content-type: application/json' \
  -d '{"body":"hello wall","color":"sky","x":0.5,"y":0.4,"name":"me","owner":"tok-123","turnstileToken":"dummy"}'

curl -s http://localhost:8787/wall/messages -H 'x-wall-owner: tok-123'   # mine=true
# a 2nd POST within 60s from the same IP -> 429
```

## Deploy

```sh
cd website/server
wrangler d1 create mos-server                       # paste database_id into wrangler.toml
wrangler d1 migrations apply mos-server --remote    # build tables on the real DB
wrangler secret put TURNSTILE_SECRET                # your real Turnstile secret
wrangler secret put IP_SALT                         # any long random string
wrangler deploy                                     # publishes to mos-api.caldis.me (custom_domain)
```

Then in the site build (GitHub Pages workflow) inject:

- `NEXT_PUBLIC_SERVER_URL=https://mos-api.caldis.me`
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY=<your Turnstile site key>`

Leaving `NEXT_PUBLIC_SERVER_URL` unset keeps the local seed fallback in
`website/app/services/wall.ts` for offline frontend dev.

## Geo (country stats)

Each note stores a `country` column (migration `0005`), resolved server-side in
`handlePost` from Cloudflare's edge geolocation — `request.cf.country`, falling
back to the `CF-IPCountry` header, then `'XX'`. It's an ISO 3166-1 alpha-2 code
(e.g. `SG`), `'XX'` (unknown / local `wrangler dev`, where `request.cf` is absent),
or `'T1'` (Tor). The selection logic is the pure `resolveCountry` (`lib/geo.ts`,
unit-tested in `geo.test.ts`).

This adds **no extra request and stores no IP**: the country rides on the inbound
request for free, and only the 2-letter code is persisted (the separate `ip_hash`
is for rate-limiting, not geo). It is **stored only, never emitted** — `toPublicNote`
doesn't expose it, so it stays backend-only, for aggregate stats:

```sh
# country distribution of visible notes
wrangler d1 execute mos-server --remote --command "SELECT country, COUNT(*) AS notes FROM wall_notes WHERE hidden=0 GROUP BY country ORDER BY notes DESC"
```

Rows created before `0005` have `country = NULL`; every new note gets a value.

## Moderation

`hide_reason` records **why** a note was hidden — or, for `ai-low-quality`, why
it was flagged while still visible:

| `hide_reason`    | `hidden` | Meaning                                                                 |
| ---------------- | -------- | ----------------------------------------------------------------------- |
| `NULL`           | 0        | visible, nothing flagged                                                |
| `user`           | 1        | the author self-deleted (`DELETE /wall/messages/:id`)                   |
| `spam`           | 1        | rule filter at POST time / the hourly sweep (`lib/moderation`: links + ad keywords) |
| `ai-low-quality` | **0**    | the sweep's AI judge thinks it's gibberish — **still visible**, awaiting your review |
| `admin`          | 1        | a human hid it by hand (command below)                                  |

Two automated layers, both in the hourly sweep (`features/wall.ts` → `sweep`):
- **Rule spam** (`lib/moderation.ts`, shared with the POST handler so the door
  and the broom agree) — links banned + ad-keyword blocklist. Tune it there.
- **AI low-quality** (`lib/aiJudge.ts`) — a small Workers AI model flags gibberish
  like `Dhdh`. It only flags; you decide. `ai_checked` ensures each note is judged
  once, so AI usage stays within the free tier.

```sh
# review what the AI flagged (still visible until you act):
wrangler d1 execute mos-server --remote --command "SELECT id, substr(body,1,60) AS body FROM wall_notes WHERE hide_reason='ai-low-quality' AND hidden=0"
# agree → hide it by hand, tagged 'admin' so the audit trail is honest:
wrangler d1 execute mos-server --remote --command "UPDATE wall_notes SET hidden=1, hide_reason='admin' WHERE id=42"
# disagree → clear the flag (ai_checked stays 1, so it won't be re-judged):
wrangler d1 execute mos-server --remote --command "UPDATE wall_notes SET hide_reason=NULL WHERE id=42"
# inspect everything hidden:
wrangler d1 execute mos-server --remote --command "SELECT id, hide_reason, substr(body,1,60) AS body FROM wall_notes WHERE hidden=1 ORDER BY id DESC LIMIT 50"
# un-hide (restore) a note:
wrangler d1 execute mos-server --remote --command "UPDATE wall_notes SET hidden=0, hide_reason=NULL WHERE id=42"
```

## Abuse & cost controls

The account is on the **Workers Free plan**: every service hard-stops at its free
limit instead of billing overage, so the worst case under attack is temporary
unavailability, not a surprise bill. Cloudflare also adds no bandwidth/egress
charges and free, unmetered DDoS mitigation. Layers in this Worker:

- **POST** — Turnstile + per-IP-hash rate limit (1 visible / 2 min, 8 / hour),
  plus the link + ad-keyword content filter.
- **GET** — Cloudflare Rate Limiting binding (`env.RL`, `[[ratelimits]]`):
  120 req / 60 s per IP, per-colo. A burst gets a cheap 429 before any D1 query.
  This guards D1/CPU, **not** the Worker request quota (the Worker still runs to
  evaluate the limit) — for that, add an edge **WAF Rate Limiting Rule** in the
  dashboard (Security → WAF → Rate limiting rules), which blocks before the Worker.
- **Workers AI** — not reachable from any public route (only the hourly cron calls
  it). Triple-capped: once per note (`ai_checked`), `AI_SWEEP_LIMIT` per run, and
  `AI_DAILY_MAX` per UTC day (`ai_budget` table). Fail-open on any error.
- **Client** — the site caches `GET /wall/messages` in `localStorage` for 5 min,
  so reloads don't re-hit the API (`website/app/services/wall.ts`).
