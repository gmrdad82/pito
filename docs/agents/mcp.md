# pito-mcp — project-specific extensions

Project-scoped overrides for the MCP-impl agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/mcp.md`.

## Pito specifics

- MCP server: stdio transport via `bin/mcp`, HTTP transport via `bin/mcp-web`
  (dedicated Puma on port 3001).
- Tool surface documented in `docs/mcp.md`.
- Dev KB tools (`list_docs`, `read_doc`, `save_note`) expose the `docs/` tree to
  Claude Mobile — see CLAUDE.md "MCP Dev KB surface" section.
- Mobile-saved notes land in `docs/notes/`. Filename is server-generated as
  `YYYY-MM-DD-HH-MM-SS-<slug>.md`. Desktop curates and prunes; Mobile is read +
  capture only.
- Tool definitions, scope checks, and RSpec coverage all required.
- Boolean values at the MCP I/O boundary use `"yes"` / `"no"` strings, never
  `true` / `false` — see `CLAUDE.md` hard rule.

## Out of scope

- Touching `extras/`, `docs/` (except `docs/notes/` which is the Mobile capture
  surface), `.claude-config/`.
- Committing or pushing.
