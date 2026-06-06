-- Mos Wall — initial schema.
-- Stores text / color / position only. Rotation is derived client-side from id
-- (see website/app/services/wall.ts rotFromId), never persisted.

CREATE TABLE IF NOT EXISTS notes (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  body        TEXT    NOT NULL,
  color       TEXT    NOT NULL,            -- palette key: amber|rose|sky|mint|lilac|blush
  x           REAL    NOT NULL,            -- center, normalized 0..1
  y           REAL    NOT NULL,            -- center, normalized 0..1
  name        TEXT,                        -- optional signature (decision D1)
  owner       TEXT    NOT NULL,            -- opaque client token, for attribution
  created_at  INTEGER NOT NULL,            -- epoch ms
  hidden      INTEGER NOT NULL DEFAULT 0,  -- moderation soft-delete
  ip_hash     TEXT                         -- rate limit / moderation, irreversible hash
);

CREATE INDEX IF NOT EXISTS idx_notes_visible   ON notes (hidden, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_ratelimit ON notes (ip_hash, created_at);
