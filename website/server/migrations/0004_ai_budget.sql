-- Daily Workers AI call budget — a hard ceiling so a sustained note flood can't
-- run AI usage past a set number of calls per UTC day, even across many sweeps.
-- Belt-and-suspenders on top of the per-sweep cap (AI_SWEEP_LIMIT) and the
-- once-per-note guard (ai_checked). One row per day; the sweep increments it.
CREATE TABLE IF NOT EXISTS ai_budget (
  day   TEXT PRIMARY KEY,          -- UTC date, 'YYYY-MM-DD'
  count INTEGER NOT NULL DEFAULT 0 -- AI judgements spent that day
);
