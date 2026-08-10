-- Track WHY a note is hidden, so moderation isn't a single opaque boolean.
--   'user'  — the author soft-deleted their own note (DELETE /wall/messages/:id)
--   'spam'  — the content filter / scheduled sweep hid it (lib/moderation)
--   'admin' — a human hid it by hand (the wrangler d1 UPDATE in the README)
-- NULL means visible (hidden = 0). Kept as a sibling of `hidden` rather than
-- folding both into a status enum, so every existing `WHERE hidden = 0` query
-- keeps working untouched.
ALTER TABLE wall_notes ADD COLUMN hide_reason TEXT;

-- Backfill: until now the ONLY way to hide a note was the owner self-delete
-- (POST-time spam was rejected, never stored), so every currently-hidden row is
-- a user self-delete. Label them accurately instead of leaving NULL.
UPDATE wall_notes SET hide_reason = 'user' WHERE hidden = 1 AND hide_reason IS NULL;
