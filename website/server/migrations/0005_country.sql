-- Country of origin for each note, resolved server-side in handlePost from
-- Cloudflare's edge geolocation (request.cf.country, with a CF-IPCountry header
-- fallback). ISO 3166-1 alpha-2 (e.g. 'US'), or 'XX' (unknown / local dev) /
-- 'T1' (Tor). Nullable on purpose: rows created before this migration stay NULL;
-- new notes always get a value. Aggregate stats only — never emitted to clients
-- (see toPublicNote in src/features/wall.ts).
ALTER TABLE wall_notes ADD COLUMN country TEXT;
CREATE INDEX IF NOT EXISTS idx_wall_notes_country ON wall_notes (country);
