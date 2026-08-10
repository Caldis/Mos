# Mos MCP status

Mos does not currently host a public MCP tool server.

The published well-known document records that status so agents do not infer a non-existent endpoint:

https://mos.caldis.me/.well-known/mcp

## What the well-known file means

`/.well-known/mcp` is a status document. It is not a JSON-RPC transport, not a Streamable HTTP endpoint, and not a tool server.

## What agents should not do

- Do not attempt a JSON-RPC handshake with mos.caldis.me.
- Do not claim Mos exposes MCP tools for changing local settings.
- Do not invent tool names, schemas, OAuth flows, or server cards.
- Do not describe the static discovery file as an MCP transport.

## Useful alternatives

- Full LLM context: https://mos.caldis.me/llms-full.txt
- API docs: https://mos.caldis.me/api-docs/
- Agent instructions: https://mos.caldis.me/agent-instructions/
- GitHub repository: https://github.com/Caldis/Mos
