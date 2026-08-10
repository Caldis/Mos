// Unit-tests the pure verdict parser (no Workers AI binding needed). The live
// model call (looksLowQuality) is verified against real Workers AI in the sweep;
// here we lock down the fail-safe parsing that decides whether a reply flags.
// Run with `pnpm test`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { interpretVerdict } from "./aiJudge.ts";

test("flags only an explicit gibberish verdict", () => {
  for (const raw of ["GIBBERISH", "gibberish", "GIBBERISH.", " gibberish\n", "Answer: GIBBERISH"]) {
    assert.equal(interpretVerdict(raw), true, JSON.stringify(raw));
  }
});

test("keeps real / meaningful / ambiguous / empty replies (fail-safe)", () => {
  for (const raw of ["REAL", "real", "MEANINGFUL", "", "   ", "not sure", "yes", "👍", "ok"]) {
    assert.equal(interpretVerdict(raw), false, JSON.stringify(raw));
  }
});

test("contradictory reply is treated as NOT gibberish (never over-flag)", () => {
  assert.equal(interpretVerdict("this is real, not gibberish"), false);
  assert.equal(interpretVerdict("REAL — definitely not gibberish"), false);
});
