// Run with `pnpm test` (node --test, native TS type-stripping — needs Node >=22.6,
// CI is on 24). No test framework: this is a pure function, so plain node:test +
// assert is enough and adds zero dependencies. Excluded from tsc via tsconfig.
import { test } from "node:test";
import assert from "node:assert/strict";
import { spamReason } from "./moderation.ts";

test("clean notes pass (incl. a bare neutral-TLD product mention)", () => {
  for (const body of [
    "Mos 让我的滚轮终于顺了，谢谢你 🙏",
    "scrolling feels like butter now",
    "毎日つかってます。ありがとう！",
    "试了 Mos.app，很好用", // bare .app, no path → NOT a link
    "great app, 5/5 — thanks!",
    "trackpad person on a mouse, finally bearable",
  ]) {
    assert.equal(spamReason(body, ""), null, body);
  }
});

test("links are rejected", () => {
  for (const body of [
    "check http://spam.example/win",
    "go to www.spam.cc now",
    "buy at shady.com/deal",
    "join t.me/cryptopump",
    "cheap-deals.top", // bare spam TLD, no path
    "wikipedia.org", // bare, org is in the spam-TLD set (it IS a link)
  ]) {
    assert.equal(spamReason(body, ""), "no links", body);
  }
});

test("a link hidden in the name field is caught too", () => {
  assert.equal(spamReason("nice app", "visit foo.com/promo"), "no links");
});

test("ad keywords are rejected, including spaced/zero-width obfuscation", () => {
  for (const body of [
    "加微信 abc888 领红包",
    "加 微 信 abc888", // spaced — normalized away before matching
    "best casino bonus here",
    "代刷服务 dm 我",
    "月入过万 不是梦",
  ]) {
    assert.equal(spamReason(body, ""), "spam", body);
  }
});

test("link check wins over keyword check (reason is stable)", () => {
  // Has both a link and an ad keyword; "no links" is reported first.
  assert.equal(spamReason("加微信 www.x.cc", ""), "no links");
});
