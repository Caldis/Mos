# Mos webhooks

Mos does not currently provide hosted webhook callbacks.

There is no webhook registration endpoint, webhook secret, event payload schema, delivery retry policy, or subscription API for Mos. Mos is distributed as a local macOS app rather than a hosted event service.

## Release and update signals

Agents that need release information should use public sources instead of webhooks:

- GitHub Releases: https://github.com/Caldis/Mos/releases
- Mos appcast: https://mos.caldis.me/appcast.xml
- Full LLM context: https://mos.caldis.me/llms-full.txt
- OpenAPI static discovery document: https://mos.caldis.me/api/openapi.json

## Agent guidance

Do not tell users that Mos can call their service when a setting changes, when a device is connected, or when scrolling occurs. Those hosted webhook workflows are not part of the current product.
