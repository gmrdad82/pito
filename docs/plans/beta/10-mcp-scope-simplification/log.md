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

## 2026-05-10 — Implementation landed (rails-impl dispatch)

**Done (Rails-only lane):**

- `app/lib/scopes.rb` rewritten end-to-end. Final shape: `Scopes::DEV = "dev"`,
  `Scopes::APP = "app"`, `Scopes::DESCRIPTIONS` has exactly two entries with the
  locked copy (`"read and capture developer docs."` and
  `"application access. manage channels, videos, projects, and the calendar."`).
  `Scopes.all` recomputes from the live config flag; `Scopes::ALL` is the
  boot-captured frozen array.
- Strip-on-release flag `Rails.application.config.x.mcp.expose_dev_scope`
  declared in `config/application.rb` (so it is set before any initializer runs)
  and overridden per-environment in
  `config/environments/{development,test,production}.rb`. Production-only flag
  is `false`.
- `config/initializers/doorkeeper.rb` updated: `default_scopes(*Scopes::ALL)`
  - empty `optional_scopes`. Soft-clip monkey-patch
    (`config/initializers/doorkeeper_scope_clip.rb`) verified unchanged.
- Every `app/mcp/tools/*.rb` updated per the spec mapping. Dev-KB tools
  reference `Scopes::DEV`; every other tool references `Scopes::APP`.
  `manage_settings.rb` lost its read/write scope branching.
- `app/mcp/pito_server.rb` registers tools through a flag-aware filter:
  `list_docs` / `read_doc` / `save_note` are NOT registered when
  `Rails.application.config.x.mcp.expose_dev_scope == false`. Defense-in-depth
  pairs with the per-tool `require_scope!(Scopes::DEV)` inside each tool.
- `app/models/api_token.rb` gained `dev_scope_only_when_exposed` validation —
  even a runtime stub of `Scopes::ALL` cannot smuggle a `["dev"]` row past the
  model when the flag is `false`.
- `db/seeds.rb` collapses the dev `ApiToken` scope set to `Scopes::ALL.dup` and
  skips the dev token mint entirely under `Rails.env.production?` (per
  master-agent decision — production operators mint their own via
  `/settings/tokens`).
- `lib/tasks/tokens.rake` default scopes argument is now `dev+app` (was
  `dev:read+dev:write`); help text updated accordingly.
- `app/views/settings/tokens/_form.html.erb` and
  `app/views/settings/oauth_applications/_form.html.erb` switched from a
  per-namespace `<fieldset>` grouping to a flat list rendered from
  `Scopes::DESCRIPTIONS`.
- New migration:
  `db/migrate/20260510110333_revoke_tokens_for_scope_simplification.rb`.
  Soft-revokes every active `ApiToken`, `OauthAccessToken`, and
  `OauthAccessGrant`. Rewrites `OauthApplication.scopes` strings in-place using
  the legacy → `dev` / `app` mapping table.
- Test sweep: `spec/lib/scopes_spec.rb` rewritten for the 2-scope catalog
  (`Scopes::DEV` / `Scopes::APP`, the strip-on-release behavior, the locked
  descriptions). Every spec referencing legacy constants (`DEV_READ`, `YT_READ`,
  etc.) updated. New specs: `spec/requests/mcp/tool_registry_spec.rb`
  (strip-on-release behavior), `spec/mcp/tool_auth_spec.rb` (helper happy-path /
  sad-path / legacy string defense-in-depth),
  `spec/db/migrate/revoke_tokens_for_scope_simplification_spec.rb` (migration
  integration).
- `spec/requests/oauth_scope_clip_spec.rb` rewritten: every old per-scope
  assertion now uses `Scopes::DEV` / `Scopes::APP`; explicit rejection of legacy
  strings (`dev:read`) added; strip-on-release describe block stubs Doorkeeper
  config to drop `dev` from `server.scopes`.
- `Api::FootagesController` and the `Api::AuthConcern` doc comment updated:
  every `require_scope!(Scopes::PROJECT_*)` call now uses `Scopes::APP`.
  `spec/requests/api/auth_concern_spec.rb` rewritten — the previous
  read-vs-write reject matrix becomes a `dev`-only-token vs `app`-token matrix.

**Verification:**

- `bundle exec rspec` — 1717 examples, 0 failures (was 1673 in Phase 9; net +44
  from new test files).
- `bundle exec rubocop` — 425 files inspected, no offenses.
- `bundle exec brakeman -q -w2` — 0 errors, 0 security warnings.
- `bin/rails db:migrate` — migration runs cleanly; `db/schema.rb` only bumps the
  version, no column changes.
- `git grep` for legacy constants (`DEV_READ`, `YT_*`, `WEBSITE_*`, `PROJECT_*`)
  — zero matches in `app/`, `lib/`, `spec/`, `config/`, `db/` (ignoring the
  migration mapping body and a single reference in an older Phase 1 migration's
  audit comment).
- `git grep` for legacy literal strings (`"dev:read"`, `"yt:read"`, etc.) — only
  in the migration mapping body, the migration's "rejects legacy string" tests,
  and the old Phase-1 migration's audit comment.

**Deferred / out-of-scope (per the spec):**

- `docs/auth.md`, `docs/mcp.md`, and `CLAUDE.md` prose rewrites — handled by the
  docs-keeper after the user validates.
- ADR 0004 status flip from "Accepted" to "Implemented" — same dispatch.
- `extras/cli/`, `extras/website/` — unaffected (no client-side scope encoding).
