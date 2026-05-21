# MCP — Model Context Protocol surface

## Status

`mcp.pitomd.com` is **parked**. The MCP surface is functional but
de-emphasized while the owner focuses on the web + TUI surfaces. Future
revisit will expand the tool catalog.

## Initial scope (when MCP is revived)

**Analytics-first.** MCP exposes a narrower slice of the API than the
CLI does. The initial tool catalog targets the analytics layer:

- `Pito::Analytics::*` — cross-cutting analytics primitives
- `Channel::Analytics::*` — channel-specific rollups
- `Video::Analytics::*` — video-specific rollups

Other tools (recommendations, video editing, schedule conflicts) are
added on demand.

## Process model

- Separate Rails Puma process serving the MCP HTTP transport at
  `mcp.pitomd.com` on port `3001`.
- `bin/mcp` — stdio transport for local Claude Code usage.
- `bin/mcp-web` — HTTP transport for remote MCP clients (Claude Mobile,
  other MCP-aware tools).

## Auth

- **Bearer tokens scoped to the user.** No per-action token. No granular
  scopes within a token. **All-or-nothing access:** present a valid
  bearer, you can call any exposed MCP tool.
- Token management via `/settings/security/tokens` (web UI).
- Mandatory-2FA gate exempt — a bearer credential cannot complete TOTP
  enrollment. Bearer-only flows.

## Action bus integration

MCP tool calls route through the action bus.

- **JS dispatcher** = `window.Pito.dispatchAction` (browser only).
- **Ruby dispatcher** = `Pito::ActionDispatcher` (in-process; used by
  MCP + CLI). Symmetric API to the JS dispatcher.

MCP tools call `Pito::ActionDispatcher.dispatch(:action_name, params)`
under the hood. The dispatcher reads `Pito::ActionRegistry[:action_name]`
and executes the canonical flow.

**Destructive tool calls require a two-step `confirm: bool` parameter** —
parity with the web confirmation dialog. First call returns the
confirmation payload; second call with `confirm: "yes"` executes.

This keeps MCP, web, and TUI flows aligned: same action, same
confirmation, same audit trail.

## Wire format

- **`yes` / `no` strings for booleans.** Never `true` / `false` / `0` /
  `1`. Convert at the wire boundary; internal Ruby uses real Booleans.
- JSON payloads over HTTP. JSON-RPC framing over stdio.
- Error shape: `{ error: { code, message, retry_after? } }`
- Pagination: `{ items, next_cursor }` cursor-based.

## CLI parity (and divergence)

| Surface | Scope |
|---|---|
| CLI | **100% of web app.** Every screen renders in TUI. |
| MCP | **Narrower, analytics-first.** Expands as needs surface. |

If a tool exists in MCP, it's available in CLI too. The reverse is not
guaranteed — CLI covers everything web does; MCP covers the analytics
slice plus selected utility tools.

## Forward plan

When MCP is revived:

1. Audit `Pito::Analytics::*` / `Channel::Analytics::*` /
   `Video::Analytics::*` for tools worth exposing.
2. Wrap each as an MCP tool that calls through `Pito::ActionDispatcher`.
3. Spec-cover the tool boundary (request → response shape).
4. Update this doc with the locked tool catalog.

Until then: the `mcp` gem is wired, the Puma is reachable, but the tool
list is intentionally minimal.
