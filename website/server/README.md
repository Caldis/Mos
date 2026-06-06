# Mos server

Cloudflare Worker + D1 backend for the Mos website. One Worker at
`api.mos.caldis.me`, multiplexing feature modules by path prefix. The static
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
pnpm install          # standalone pnpm root (own pnpm-workspace.yaml)
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
wrangler deploy                                     # publishes to api.mos.caldis.me (custom_domain)
```

Then in the site build (GitHub Pages workflow) inject:

- `NEXT_PUBLIC_SERVER_URL=https://api.mos.caldis.me`
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY=<your Turnstile site key>`

Leaving `NEXT_PUBLIC_SERVER_URL` unset keeps the local seed fallback in
`website/app/services/wall.ts` for offline frontend dev.

## Moderation

```sh
wrangler d1 execute mos-server --remote --command "UPDATE wall_notes SET hidden=1 WHERE id=42"
```
