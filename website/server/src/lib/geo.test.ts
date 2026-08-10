// Run with `pnpm test` (node --test, native TS type-stripping — needs Node >=22.6,
// CI is on 24). Pure function, so plain node:test + assert, zero deps. Excluded
// from tsc via tsconfig.
import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveCountry } from "./geo.ts";

test("uses request.cf.country when present, ahead of the header", () => {
  assert.equal(resolveCountry({ country: "US" }, null), "US");
  assert.equal(resolveCountry({ country: "JP" }, "XX"), "JP"); // cf wins over header
});

test("falls back to the CF-IPCountry header when cf is absent (local dev)", () => {
  assert.equal(resolveCountry(undefined, "DE"), "DE");
  assert.equal(resolveCountry({}, "DE"), "DE"); // cf object present but no country
});

test("defaults to 'XX' when nothing is known", () => {
  assert.equal(resolveCountry(undefined, null), "XX");
  assert.equal(resolveCountry({}, null), "XX");
});

test("treats an empty country as missing and falls through (|| not ??)", () => {
  assert.equal(resolveCountry({ country: "" }, "FR"), "FR");
  assert.equal(resolveCountry({ country: "" }, null), "XX");
  assert.equal(resolveCountry(undefined, ""), "XX");
});

test("passes Cloudflare's special codes through verbatim (T1 Tor, XX unknown)", () => {
  assert.equal(resolveCountry({ country: "T1" }, null), "T1");
  assert.equal(resolveCountry({ country: "XX" }, "US"), "XX"); // cf already decided unknown
});
