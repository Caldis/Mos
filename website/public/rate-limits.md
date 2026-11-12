# Mos rate limits

Mos does not provide a hosted API with product-level quotas.

Public documentation and discovery files are static resources served by the website.

## Current status

- No Mos API rate-limit headers are provided.
- No account quotas are provided.
- No paid request tiers are provided.
- No product-level Retry-After rule is provided.

## Agent request guidance

- Fetch https://mos.caldis.me/llms-full.txt first when full product context is needed.
- Use section files such as https://mos.caldis.me/api/llms.txt for narrower context.
- Cache static resources within the current task instead of repeatedly fetching the same URL.
- Do not infer API quotas, billing limits, or user-specific request budgets.

Generic CDN or GitHub Pages throttling may apply outside Mos's control. That is hosting infrastructure behavior, not a Mos product API contract.
