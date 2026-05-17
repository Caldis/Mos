# Mos auth docs

Mos is a local macOS utility. Public website resources are static and do not require OAuth, API keys, sessions, or user accounts.

## Public resource access

The homepage, markdown documents, OpenAPI description, agent discovery files, schema feeds, appcast, and release links are public. Agents can read them without authentication.

Metadata: https://mos.caldis.me/.well-known/oauth-protected-resource

## No OAuth surface

- Mos does not host user accounts.
- Mos does not issue OAuth client IDs, access tokens, or refresh tokens.
- Mos does not define OAuth scopes for remote actions.
- Mos does not expose account, billing, or settings APIs.

## Local macOS permission

Mos may require macOS Accessibility permission so the local app can observe and process input events. This is a local operating-system permission, not a Mos web account or OAuth login.
