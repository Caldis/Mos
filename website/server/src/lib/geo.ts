// Resolves the country code to store with a wall note. Order of preference:
//   1. request.cf.country — Cloudflare's edge geolocation, an ISO 3166-1 alpha-2
//      code (e.g. "US"), or "T1"/"XX" for Tor / undeterminable.
//   2. the CF-IPCountry header — the same value, kept as a fallback.
//   3. "XX" — when neither is present, e.g. local `wrangler dev`, where the
//      request.cf object is absent.
// `||` (not `??`) so an empty string falls through to the next source instead of
// being stored as-is.
export function resolveCountry(
  cf: { country?: string } | undefined,
  ipCountryHeader: string | null,
): string {
  return cf?.country || ipCountryHeader || "XX";
}
