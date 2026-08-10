// Content moderation for user-submitted text. Pure and dependency-free so the
// SAME logic runs in two places: inline at POST time (reject at the door) and in
// the scheduled sweep (hide anything that slipped through before the rules
// tightened). Keeping it here — not inside a feature — means there is one source
// of truth for "is this spam", and it can be unit-tested with plain Node (no
// Workers runtime needed).
//
// Returns a stable machine reason ("no links" | "spam") that the client maps to
// localized copy, or null when the text is clean. Reasons are intentionally
// coarse: the user only needs to know it was a link vs. an ad, not which rule.

// --- Links (decision: the wall is for short notes, not link sharing) ---------
//
// Strong, unambiguous link signals: a protocol, a www. host, a scheme
// separator, or a domain that carries a path ("foo.bar/…"). A path means
// someone is pointing at a destination, so even neutral TLDs count here.
const STRONG_LINK = /(https?:\/\/|www\.|:\/\/|\b[a-z0-9-]+\.[a-z]{2,}\/\S)/i;

// Bare domains (no path) only count as links on TLDs that are overwhelmingly
// link-drops / spam. We deliberately EXCLUDE neutral TLDs (.app .io .dev .ai …)
// so legit product mentions like "Mos.app" or "foo.dev" don't trip — those are
// links only when they carry a path (caught by STRONG_LINK above).
const BARE_SPAM_DOMAIN =
  /\b[a-z0-9-]+\.(?:com|net|org|cn|xyz|top|vip|shop|club|live|link|cc|tk|ru|info|biz|online|site|store|fun|pro|wang|ltd|icu)\b/i;

// --- Ad / spam keywords ------------------------------------------------------
//
// These are NOT in any profanity library — they're context-specific ad spam
// (contact-pushing, gambling, grey-market promos). Stored already lowercased and
// WITHOUT whitespace, because the haystack is normalized the same way before
// matching, so spaced-out obfuscation ("加 微 信", "c a s i n o") still hits.
// Keep the list small and high-precision: a false positive blocks a real note,
// which is far worse than letting one ad through (the sweep + rate limit + the
// link ban are the other layers). Easy to extend — just add a stripped term.
const SPAM_TERMS: readonly string[] = [
  // contact-pushing (the classic "加微信 xxx" ad)
  "加微信", "微信号", "加vx", "vx号", "加薇信", "威信号", "加扣扣", "qq号", "加企鹅",
  // engagement / order farming
  "代刷", "刷单", "刷钻", "刷赞", "刷粉", "刷量",
  // gambling
  "博彩", "彩金", "赌场", "赌博", "网赌", "棋牌", "老虎机", "现金网", "真人荷官", "六合彩", "时时彩",
  // grey-market promos
  "招代理", "招商加盟", "一手货源", "微商", "代开发票", "办证",
  // get-rich-quick
  "日赚", "月入过万", "躺赚", "稳赚不赔", "包赔",
  // adult solicitation
  "裸聊", "约炮", "一夜情", "同城约",
  // english ad spam
  "casino", "viagra", "cialis", "escort", "freemoney", "workfromhome", "cryptoairdrop",
];

// Strip whitespace + zero-width chars and lowercase, so spaced/obfuscated
// variants normalize to the same form the term list is stored in. The explicit
// codepoints are the zero-width family (ZWSP U+200B, ZWNJ, ZWJ) plus BOM
// (U+FEFF), which spammers splice between characters to dodge naive matching.
function normalize(text: string): string {
  return text.toLowerCase().replace(/[\s\u200B-\u200D\uFEFF]+/g, "");
}

/**
 * Classify a note's text. Checks the body and the optional signature.
 * @returns "no links" | "spam" when it should be rejected/hidden, else null.
 */
export function spamReason(body: string, name?: string | null): string | null {
  const linkTarget = `${body}\n${name ?? ""}`;
  if (STRONG_LINK.test(linkTarget) || BARE_SPAM_DOMAIN.test(linkTarget)) return "no links";

  const haystack = normalize(`${body} ${name ?? ""}`);
  for (const term of SPAM_TERMS) {
    if (haystack.includes(term)) return "spam";
  }
  return null;
}
