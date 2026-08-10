# Mos API docs

Mos does not provide a hosted user API for controlling the local macOS app.

These API docs describe static public discovery files that agents and search tools can fetch.

## OpenAPI

- OpenAPI: https://mos.caldis.me/api/openapi.json
- API docs page: https://mos.caldis.me/api-docs/
- Developer resources: https://mos.caldis.me/developers/

The OpenAPI file describes documentation and discovery endpoints. It does not describe remote control over a user's Mac, account APIs, settings mutation, telemetry export, payments, or hosted automation.

## Static discovery endpoints

- API catalog: https://mos.caldis.me/.well-known/api-catalog
- OAuth protected resource metadata: https://mos.caldis.me/.well-known/oauth-protected-resource
- Agent discovery: https://mos.caldis.me/.well-known/agent.json
- A2A agent card: https://mos.caldis.me/.well-known/agent-card.json
- Agent Skills index: https://mos.caldis.me/.well-known/agent-skills/index.json
- MCP status: https://mos.caldis.me/.well-known/mcp
- Schema map: https://mos.caldis.me/schema-map.xml

## Auth and access

Public documentation and discovery resources are zero-auth. Mos does not provide OAuth scopes, API keys, hosted user accounts, or protected remote resources.

## Webhooks and MCP

Mos does not currently provide webhook registration endpoints or a hosted MCP tool server.
