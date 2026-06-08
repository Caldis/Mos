// Run with `pnpm test` (node --test, native TS type-stripping — needs Node >=22.6).
// Pure function, so plain node:test + assert, zero dependencies. The constant-time
// property itself isn't asserted (timing is environment-dependent); we verify the
// equality semantics that gate admin access.
import { test } from "node:test";
import assert from "node:assert/strict";
import type { Env } from "./env.ts";
import { isAdmin, timingSafeEqual } from "./admin.ts";

const envWith = (ADMIN_TOKEN: string) => ({ ADMIN_TOKEN }) as unknown as Env;

test("equal strings match", () => {
  assert.equal(timingSafeEqual("s3cret-token", "s3cret-token"), true);
  assert.equal(timingSafeEqual("", ""), true);
});

test("same length, different content does not match", () => {
  assert.equal(timingSafeEqual("abc123", "abc124"), false);
  assert.equal(timingSafeEqual("xxxxxx", "yyyyyy"), false);
});

test("different length does not match", () => {
  assert.equal(timingSafeEqual("abc", "abcd"), false);
  assert.equal(timingSafeEqual("token", ""), false);
});

test("unicode is compared by code unit", () => {
  assert.equal(timingSafeEqual("café", "café"), true);
  assert.equal(timingSafeEqual("café", "cafe"), false);
});

test("isAdmin: matching token authorizes", () => {
  assert.equal(isAdmin(envWith("s3cret-token"), "s3cret-token"), true);
});

test("isAdmin: wrong or empty token is rejected", () => {
  assert.equal(isAdmin(envWith("s3cret-token"), "nope"), false);
  assert.equal(isAdmin(envWith("s3cret-token"), ""), false);
});

test("isAdmin: fails closed when no secret is configured", () => {
  // An unset/empty ADMIN_TOKEN must NEVER authorize — not even an empty header,
  // which would otherwise be string-equal to an empty secret.
  assert.equal(isAdmin(envWith(""), ""), false);
  assert.equal(isAdmin(envWith(""), "anything"), false);
  // Secret entirely absent (before `wrangler secret put`): must return false,
  // not throw on `.length` — a probe should get 401, never a 500.
  const noSecret = {} as unknown as Env;
  assert.doesNotThrow(() => isAdmin(noSecret, "anything"));
  assert.equal(isAdmin(noSecret, "anything"), false);
});
