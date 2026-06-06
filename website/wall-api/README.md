# Mos Wall API

Cloudflare Worker + D1 backing the sticky-note wall at <https://mos.caldis.me/wall>.
The static site (GitHub Pages, `output: export`) calls this at runtime — all
validation, anti-abuse, and storage live here.

## Endpoints

| Method | Path            | Notes                                                        |
| ------ | --------------- | ----------------------------------------------------------- |
| GET    | `/api/messages` | visible notes, newest first, max 800. Send `x-wall-owner` for per-note `mine`. |
| POST   | `/api/messages` | create a note: `{ body, color, x, y, name?, owner, turnstileToken }` |
| OPTIONS| `/api/messages` | CORS preflight                                              |

No `PATCH`: a note's position is set at POST time and **locked** (decision D3 —
stick it and it stays). Rotation is not stored; the client derives it from `id`.

## Local dev

```sh
cd website/wall-api
pnpm install          # or npm install
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
# health
curl -s http://localhost:8787/

# list
curl -s http://localhost:8787/api/messages

# create (any non-empty token passes with the test secret)
curl -s -X POST http://localhost:8787/api/messages \
  -H 'content-type: application/json' \
  -d '{"body":"hello wall","color":"sky","x":0.5,"y":0.4,"name":"me","owner":"tok-123","turnstileToken":"dummy"}'

# mine=true only when x-wall-owner matches the note's owner
curl -s http://localhost:8787/api/messages -H 'x-wall-owner: tok-123'

# rate limit: a 2nd POST within 60s from the same IP -> 429
```

## Deploy

```sh
wrangler d1 create mos-wall                       # paste database_id into wrangler.toml
wrangler d1 migrations apply mos-wall --remote    # build tables on the real DB
wrangler secret put TURNSTILE_SECRET              # your real Turnstile secret
wrangler secret put IP_SALT                       # any long random string
wrangler deploy                                   # publishes to api.mos.caldis.me (custom_domain)
```

Then in the site build (GitHub Pages workflow) inject:

- `NEXT_PUBLIC_WALL_API_URL=https://api.mos.caldis.me`
- `NEXT_PUBLIC_TURNSTILE_SITE_KEY=<your Turnstile site key>`

Leaving `NEXT_PUBLIC_WALL_API_URL` unset keeps the local seed fallback in
`website/app/services/wall.ts` for offline frontend dev.

## Moderation

```sh
# hide a note
wrangler d1 execute mos-wall --remote --command "UPDATE notes SET hidden=1 WHERE id=42"
```
