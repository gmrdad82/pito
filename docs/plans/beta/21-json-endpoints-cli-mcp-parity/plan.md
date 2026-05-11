# Phase 21 — JSON Endpoints for CLI / MCP Parity

> **Status:** spec-only (Rails). Active phase. Depends on Phases 14 (Games /
> IGDB), 15 (Calendar Views), 16 (Notifications), 20 (Friendly URLs).

## Why

Phases 14–16 shipped HTML-first surfaces for games, calendar entries, and
notifications. The `pito` CLI (Phase 4 carry-over, scheduled to extend in this
stretch) and the MCP tool surface (`yt:*` namespace) both need a stable JSON
contract on those same surfaces before they can offer parity with the web UI.

Rather than fold the JSON work into each feature phase retroactively, this phase
concentrates the Rails-side JSON surface in one focused sweep so the CLI lane
and the MCP lane can land in parallel follow-ups without cross-phase
coordination on shape changes.

## Scope (what this phase covers)

Three Rails controllers gain `format.json` branches plus dedicated `.jbuilder`
views:

1. **`GamesController`** — `index`, `show`, `resync`, `search` JSON responses.
   `show` accepts slug OR id (Phase 20 `friendly_id` convention).
2. **`Calendar::*Controller`** — schedule list, month grid, entry detail, entry
   CRUD, soft-cancel deletion.
3. **`NotificationsController`** — index, show, badge, and the existing `read` /
   `unread` / `mark_read` / `mark_all_read` actions get a JSON body (replacing
   the current 204).

Specs cover request, jbuilder view, decorator (where used), boundary `yes`/`no`
coercion, friendly-id slug resolution, auth gate, rate-limit considerations, and
the 404 vs 422 distinction.

See `specs/01-rails-json-endpoints.md` for the full breakdown.

## Non-scope (declared explicitly)

- **CLI subcommand additions** — separate follow-up under `extras/cli/` once
  these endpoints land. No Rust code in this phase.
- **MCP tool additions** — separate follow-up under `app/mcp/tools/` once these
  endpoints land. No new MCP tool registrations in this phase.
- **New model attributes / migrations** — the JSON shapes surface what already
  exists. If a shape needs a column the model lacks, the spec calls it out as an
  open question rather than silently adding a migration.
- **Full multi-user auth scoping** — single-install per ADR-0003. Every
  authenticated user sees the same JSON.
- **Bearer-token / `Api::AuthConcern` parity** — these endpoints ride the
  existing cookie-session auth (`Sessions::AuthConcern`). Bearer parity is a
  Phase 5 concern that already exists for the surfaces under `/api/`.

## Phase checkboxes

- [x] Spec drafted: `specs/01-rails-json-endpoints.md`
- [x] Spec validated by user
- [x] Rails-impl lane: GamesController JSON branches + jbuilder views + specs
- [x] Rails-impl lane: Calendar controllers JSON branches + jbuilder views +
      specs
- [x] Rails-impl lane: NotificationsController JSON branches + jbuilder views +
      specs
- [ ] Reviewer pass: every endpoint covered by request + view spec
- [ ] Manual test recipe walked end-to-end (curl)
- [ ] User validates
- [ ] Commit + push

## Dependencies

- Phase 14 — Game model + IGDB-sourced metadata
- Phase 15 — Calendar entries + dispatch declarations
- Phase 16 — Notifications + `NotificationFormatter::InApp`
- Phase 20 — Friendly URLs (`Game` accepts slug + id)

## Phase log

`log.md` is appended after each session. Empty until the first implementation
pass lands.
