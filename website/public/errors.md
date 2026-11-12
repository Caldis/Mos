# Mos error responses

Mos does not expose a hosted JSON API, so there is no product-specific JSON error envelope for agents to parse.

## Static website behavior

Public Mos resources are static files and pages. Existing files return normal HTTP 200 responses. Missing URLs are handled by the static host and may return an HTML 404 page rather than a JSON error document.

## Agent recovery guidance

- Use https://mos.caldis.me/sitemap.xml and https://mos.caldis.me/llms.txt to discover supported URLs.
- Use https://mos.caldis.me/api-docs/ for the current static discovery surface.
- Do not retry nonexistent API paths such as account, billing, settings, webhook registration, or MCP tool endpoints.
- If a public static URL is unavailable, fall back to the GitHub repository and release pages.

Mos has no remote action API for changing local settings. Agents should not expect JSON errors for validation failures, permission failures, or rate limits from mos.caldis.me.
