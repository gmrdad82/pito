# pito-mcp — project-specific extensions

Project-scoped overrides for the MCP-impl agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/mcp.md`.

## Project conventions

### E. Yes / no boundary (load-bearing for MCP I/O)

Every boolean value crossing the MCP I/O boundary — tool arguments, tool
results, payload fields exposed to clients — is a `"yes"` / `"no"` string. Never
`true` / `false`, never `0` / `1`. Internal Ruby storage stays Boolean; the MCP
tool layer converts on entry and exit. This is a hard rule from `CLAUDE.md`.

Concrete cases:

- `delete_records` / `sync_records` — `confirm: "yes"` to commit, `"no"` (or
  omitted) for the dry-run preview.
- Any tool that surfaces a boolean column (e.g. `connected`, `star`, `syncing`)
  renders `"yes"` / `"no"` in the JSON response, not Ruby `true` / `false`.
- Tool argument schemas declare the field as a string with enum `["yes", "no"]`,
  not as `boolean`.

Reviewer checks for this; ship the tool with its conversion + a spec asserting
both directions.

## pito specifics

- MCP server: stdio transport via `bin/mcp`, HTTP transport via `bin/mcp-web`
  (dedicated Puma on port 3028).
- Tool surface documented in `docs/mcp.md`.
- Tool definitions, scope checks, and RSpec coverage all required.
- Boolean values at the MCP I/O boundary use `"yes"` / `"no"` strings, never
  `true` / `false` — see `CLAUDE.md` hard rule.

## Out of scope

- Touching `extras/`, `docs/` (except `docs/notes/` which is the Mobile capture
  surface), `.claude-config/`.
- Committing or pushing.
