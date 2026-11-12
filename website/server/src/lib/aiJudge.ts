// AI low-quality judge for the moderation sweep. This is the ONE place a model
// earns its keep: deciding whether a note is a real human message or meaningless
// gibberish ("Dhdh", "asdfgh") — a semantic call that rules fundamentally can't
// make without nuking legit short/slang/CJK/emoji notes. Runs only in the hourly
// sweep (never at POST, so no user-facing latency) and only FLAGS for review.
//
// The verdict-parsing is split out as a pure function so it can be unit-tested
// without the Workers AI binding; the network call is a thin fail-open wrapper.
import type { Env } from "./env";

// Small + cheap: this is one-word classification, not generation. Swappable.
const MODEL = "@cf/meta/llama-3.2-3b-instruct";

const SYSTEM_PROMPT =
  "You moderate a public wall where people leave short notes about a Mac app called Mos. " +
  'Decide whether a note is a REAL human message or meaningless gibberish (random keyboard ' +
  'mashing like "Dhdh", "asdfgh", "qwerty", "jkjkjk"). ' +
  "A real message can be very short, in ANY language, slang, an emoji, or a simple greeting — " +
  '"hi", "amazing", "nice app", "yyds", "666", "教程?", "👍" are ALL real. ' +
  "Only call it gibberish when the text is clearly random characters with no meaning in any language. " +
  "When unsure, answer REAL. Reply with exactly one word: REAL or GIBBERISH.";

// Turn the model's raw reply into a flag decision. Fail-SAFE: only an explicit
// gibberish verdict flags; anything ambiguous, empty, or contradictory keeps the
// note (we never flag a real note because the model rambled or hedged).
export function interpretVerdict(raw: string): boolean {
  const out = raw.toLowerCase();
  const saysGibberish = out.includes("gibberish");
  const saysReal = out.includes("real") || out.includes("meaningful");
  return saysGibberish && !saysReal;
}

// Pull the text out of whatever shape the model returns (text-gen → { response }).
function extractText(resp: unknown): string {
  if (resp && typeof resp === "object" && "response" in resp) {
    const r = (resp as { response?: unknown }).response;
    if (typeof r === "string") return r;
  }
  return "";
}

// Ask Workers AI whether a note is low-quality gibberish. Fail-OPEN: any error
// (model down, quota exhausted, malformed reply) resolves to false, so an AI
// hiccup never flags — let alone hides — a real note.
export async function looksLowQuality(
  env: Env,
  body: string,
  name: string | null,
): Promise<boolean> {
  const text = `${body} ${name ?? ""}`.trim();
  if (!text) return false;
  try {
    const resp = await env.AI.run(MODEL, {
      max_tokens: 4,
      temperature: 0,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: text },
      ],
    });
    return interpretVerdict(extractText(resp));
  } catch {
    return false;
  }
}
