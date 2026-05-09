# ADR 0004 — MCP Scope Simplification: dev + app

## Status

Accepted, 2026-05-09.

## Context

Phase 5 (Auth Foundation) shipped a nine-scope catalog at `app/lib/scopes.rb`:

| Scope            | Description                                         |
| ---------------- | --------------------------------------------------- |
| `dev:read`       | Read dev knowledge base (docs/).                    |
| `dev:write`      | Write notes to docs/notes/.                         |
| `yt:read`        | Read channels, videos, stats, dashboards.           |
| `yt:write`       | Create / update channels, videos, saved views.      |
| `yt:destructive` | Delete channels, videos, bulk-delete operations.    |
| `website:read`   | Read landing-page content (Phase 6+, no tools yet). |
| `website:write`  | Edit landing-page content (Phase 6+, no tools yet). |
| `project:read`   | Read projects, collections, games, footage, notes.  |
| `project:write`  | Create / update / delete project workspace records. |

The catalog grew defensively to anticipate future surfaces (a future website
editor under `website:*`, future granular destructive separation under
`yt:destructive`). In practice, every token minted to date carries either the
`dev:*` set (Mobile-via-MCP capture) or the full app surface
(`yt:read,yt:write,project:read,project:write`). The `yt:destructive` scope is
carried selectively but has not been a meaningful gating mechanism. The
`website:*` scopes have no tools attached.

Mobile session note-driven direction (notes 1, 4, 6 — YouTube management, Games,
Calendar / Notifications) makes clear the app surface is going to grow
substantially: calendar tools, notification tools, milestone-rule tools, game
sync tools, IGDB tools, and the existing YouTube tools. Splitting that surface
across multiple `app:*` namespaces would re-create the catalog drift problem
without giving real value — every token a user-facing client mints would carry
the full set anyway.

The follow-up direction conversation locked the simplification: collapse to two
scopes — `dev` and `app` — with no read / write split per scope.

## Decision

Collapse the scope catalog to two values:

- **`dev`** — covers everything currently under `Scopes::DEV_*` (dev knowledge
  base read + capture: `list_docs`, `read_doc`, `save_note`) PLUS the future
  website surface (whatever the eventual landing-page editor needs;
  `Scopes::WEBSITE_*` folds in here). The website is dev-adjacent — never a
  user-facing SaaS surface, always a marketing / authoring surface for the
  developer-operator. Bundling them under `dev` keeps the production tokens free
  of dev-only capabilities.

- **`app`** — covers everything user-facing: YouTube data and management
  (current `yt:*` surface), projects and footage and notes (current `project:*`
  surface), plus the new surfaces identified in the Mobile session: calendar
  entries, milestone rules, notifications, delivery channels, game sync, IGDB
  pulls, bundle management. Single scope, no read / write split.

No granular split. A token has `dev`, `app`, both, or neither. The decision
trades fine-grained authorization for catalog stability — a token holder is
either trusted to operate an install, or not.

### Release packaging

`dev` is **stripped on release packaging.** Production builds (when pito ever
ships beyond the user's own laptop / Hetzner box) do not expose `dev:save_note`
or `dev:read_doc` to MCP clients. The MCP tool registry's auto-discovery filters
out `dev/*` tools when the build flag indicates a release build. This is the
security boundary equivalent of the Sidekiq Web auth: dev tooling stays behind
the developer-operator boundary.

For the v1 self-hosted-by-the-user shape, dev tooling is always available (every
install IS a dev install). The packaging strip kicks in only if a genuinely
productized release ever ships.

### Renames / merges

Old scope → new scope mapping:

| Old              | New   | Notes                                         |
| ---------------- | ----- | --------------------------------------------- |
| `dev:read`       | `dev` | Folds in.                                     |
| `dev:write`      | `dev` | Folds in.                                     |
| `yt:read`        | `app` | Folds in.                                     |
| `yt:write`       | `app` | Folds in.                                     |
| `yt:destructive` | `app` | Folds in. No more destructive split.          |
| `website:read`   | `dev` | Website is developer-facing, not user-facing. |
| `website:write`  | `dev` | Same.                                         |
| `project:read`   | `app` | Folds in.                                     |
| `project:write`  | `app` | Folds in.                                     |

## Consequences

### Code changes

- `app/lib/scopes.rb`: catalog shrinks to `Scopes::DEV` and `Scopes::APP`.
  `Scopes::ALL` becomes `[DEV, APP]`. `Scopes::DESCRIPTIONS` shrinks to two
  entries.
- Every `require_scope!` callsite in MCP tools and JSON controllers updates to
  the new scope names. Per the post-realignment new-spec dispatches, the catalog
  also gains entries for the calendar / notification / game / IGDB tools — all
  under `app`.
- `Mcp::ToolAuth.require_scope!` API stays unchanged; the values it accepts
  shrink.
- `app/lib/api/auth_concern.rb` controller mixin unchanged.
- Settings UI scope picker (`/settings/tokens` create form) collapses from a
  nested-namespace checkbox tree to two flat checkboxes ("Dev tooling access",
  "App access"). The seed token in `bin/setup` mints with both scopes set.

### Token migration concern

Existing tokens carry old scope strings (`dev:read`, `dev:write`, `yt:read`,
etc.) in their `scopes` jsonb array. The MCP rack app and `Api::AuthConcern`
parse those strings on every request.

Two migration paths considered:

- **In-place rename via data migration.** A migration reads each
  `api_token.scopes`, maps each old value to its new value, deduplicates, writes
  back. Tokens keep working without user action. Cost: one migration
  - a careful test that asserts the mapping is exhaustive.
- **Rotate-on-deploy.** A migration revokes every existing token; the user
  re-mints what they need from `/settings/tokens` after deploy. Cost: a one-time
  pain documented in the deploy notes; zero risk of stale or ambiguous mappings.

**Decision: TBD by user.** The realignment doc surfaces this as an open question
for the user to resolve before the implementation spec is dispatched. Master
agent's lean: **in-place rename**, since the install only has the user's own
tokens (and the seed dev token), and a clean mapping table is easier to audit
than a "you must re-mint everything" deploy note.

### Documentation changes

- `docs/auth.md` §2 (scope catalog), §3 (tool / endpoint scope map), §7
  (bootstrap ceremony — dev token's scope set shrinks) all rewrite.
- `docs/mcp.md` scope-per-tool table rewrites.
- The realignment doc at `docs/realignment-2026-05-09.md` carries the
  authoritative mapping during the transition.

## Rationale

- Every user-facing client of pito's MCP surface (Claude Mobile via
  `mcp.pitomd.com`, the `pito` CLI, Claude Desktop's stdio integration) has
  always wanted the full app surface. The fine-grained `read` / `write` /
  `destructive` split hasn't gated meaningful security decisions in practice.
- Dev capabilities (the docs / notes capture surface) are genuinely separate
  from app capabilities. The dev surface has different access patterns (Desktop
  architect curates; Mobile captures) and a real need to be strippable from a
  release build. The dev / app split survives.
- Adding new tool surfaces (calendar, notifications, games, IGDB) becomes the
  cheapest possible: pick a scope (almost always `app`), declare it. No catalog
  growth, no namespace churn.

## Alternatives considered

- **Keep all nine scopes.** Rejected. Catalog drift; no real-world gating
  benefit; each new tool surface requires a namespace decision that wastes
  thinking.
- **Single `pito` scope.** Rejected. Loses the dev / app strip-on-release
  property, which is genuinely valuable for a productized future.
- **Three scopes (`dev`, `read`, `write`).** Rejected. The read / write split
  was the original design and proved over Phase 5 not to gate meaningful
  decisions for the user-facing surface; bringing it back at the cross-cutting
  level recreates the same tax.

## Date

2026-05-09.

## Related

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — the related
  tenant drop in the same realignment.
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md` — Doorkeeper
  scopes follow the same simplification.
- `docs/realignment-2026-05-09.md` — the realignment doc routes the
  implementation order.
- `docs/auth.md` §2 — the scope catalog rewrites here once the implementation
  spec lands.
- `docs/mcp.md` — the per-tool scope table rewrites here once the implementation
  spec lands.
