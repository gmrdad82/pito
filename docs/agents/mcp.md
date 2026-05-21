# pito-mcp — project-specific extensions

Project-scoped overrides for the MCP-impl agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/mcp.md`. Read project-wide rules in
`~/Dev/pito/CLAUDE.md` first.

## Project overrides

- **Canonical scope:** `docs/mcp.md` defines the analytics-first MCP tool
  surface. Tools that fall outside that scope require a docs update first.
- **Action dispatcher:** MCP tools that mutate state call `Pito::ActionDispatcher`
  (the Ruby-side action bus). MCP never bypasses the dispatcher to call models
  or services directly for actions — the dispatcher is the single mutation
  entry point, shared with the web UI and the Rust TUI client.
- **Yes / no boundary (hard rule).** Every boolean crossing MCP I/O is a
  `"yes"` / `"no"` string. Tool argument schemas declare the field with
  `enum: ["yes", "no"]`, not as `boolean`. Internal storage stays Boolean;
  convert at the tool layer.
- **MCP server processes:** `bin/mcp` (stdio transport), `bin/mcp-web`
  (dedicated Puma on port 3028).
- Every tool ships with its conversion + a spec asserting both directions.

## Pointers

- `docs/mcp.md` — canonical tool surface and scope.
- `docs/architecture.md` § "Action bus" — `Pito::ActionDispatcher` contract.
- `CLAUDE.md` — yes/no boundary, bulk-as-foundation, credentials policy.

## File scope

MCP tool definitions under `app/mcp/` (or wherever the project's MCP layer
lives), corresponding `spec/mcp/`. Never touch `extras/`, `docs/`,
`.claude-config/`.

## Out of scope

- Committing or pushing.
- Editing canonical docs.
