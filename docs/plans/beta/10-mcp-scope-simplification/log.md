# Phase 10 — MCP Scope Simplification · Log

## 2026-05-10 — Phase folder created; spec dispatched

**Done:**

- Phase folder `docs/plans/beta/10-mcp-scope-simplification/` created.
- Implementation spec dispatched at
  `docs/plans/beta/10-mcp-scope-simplification/specs/01-collapse-to-dev-app.md`.
- Phase 10 sits between Phase 8 (Tenant Drop) and Phase 9 (`GoogleIdentity`
  rename) in the realignment roadmap. Per the architect dispatch's master-agent
  decisions, this phase assumes Phase 8 has landed (the seed dev token still
  carries the 6-scope set; Phase 10 collapses it to `[dev, app]`).

**Decisions in flight (locked by the dispatch):**

- Final catalog: `dev` + `app`. No read/write split, no further granularity.
- Old → new mapping: `dev:*` + `website:*` → `dev`; `yt:*` + `project:*` →
  `app`. Per ADR 0004.
- Token rotation: rotate-on-deploy (existing tokens revoked; user re-pairs
  Claude Mobile + Web MCP once).
- Strip-on-release: env-config flag
  (`Rails.application.config.x.mcp.expose_dev_scope`) defaulting on for
  development/test, off for production.
- Soft-clip monkey-patch (`config/initializers/doorkeeper_scope_clip.rb`)
  survives the simplification under the new 2-scope catalog.
- Seed dev `ApiToken` collapses from
  `[DEV_READ, DEV_WRITE, YT_READ, YT_WRITE, PROJECT_READ, PROJECT_WRITE]` to
  `[dev, app]`.

**Cross-references:**

- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — primary ADR.
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — Phase 8
  prerequisite.
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md` — Doorkeeper
  survives; Phase 10 reconfigures its `default_scopes` / `optional_scopes`.
- `docs/realignment-2026-05-09.md` — work unit 2 (MCP scope simplification).
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
  — prerequisite spec; explicitly defers scope collapse to this phase.

**Next:**

- Pending master-agent answers on the copy questions surfaced in the spec
  (consent-screen scope descriptions, error message text).
- Once copy lands, dispatch `pito-rails-impl` against the spec; reviewer pass
  follows after.
- After user validates the implementation, dispatch `pito-docs-keeper` to update
  `docs/mcp.md`, `docs/auth.md`, and `CLAUDE.md`, and to flip ADR 0004 status
  from "Accepted" to "Implemented".
