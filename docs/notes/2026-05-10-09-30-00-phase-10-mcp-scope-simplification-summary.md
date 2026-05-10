# Phase 10 — MCP scope simplification (9 → `dev` + `app`)

## Status

**Landed.** Implementation + reviewer + security + prose rewrites all in `main`.
Awaiting your manual validation.

## What changed

- Doorkeeper scope catalog collapsed from 9 scopes (`dev:read`, `dev:write`,
  `yt:read`, `yt:write`, `yt:destructive`, `project:read`, `project:write`,
  `website:read`, `website:write`) to 2: `dev` and `app`.
- New `Scopes::DEV`, `Scopes::APP`, `Scopes::ALL`, `Scopes::DESCRIPTIONS` with
  locked copy: `dev` = `read and capture developer docs.`, `app` =
  `application access. manage channels, videos, projects, and the calendar.`
- Strip-on-release: `Rails.application.config.x.mcp.expose_dev_scope` flag, true
  in dev/test, false in production. Production drops `dev` from `Scopes::ALL`,
  from the MCP tool registry, AND from `ApiToken` validation. Three enforcement
  layers.
- Soft-revoke migration: every existing `ApiToken`, `Doorkeeper::AccessToken`,
  `Doorkeeper::AccessGrant` soft-revoked (`revoked_at` set). Existing
  `OauthApplication.scopes` strings rewritten via legacy → 2-scope mapping.
- Soft-clip monkey-patch (`config/initializers/doorkeeper_scope_clip.rb`)
  unchanged on disk; verified compatible with new catalog.
- Seed: dev token now scoped `["dev", "app"]`. Production seed skips the
  dev-token mint entirely.

## Quality gates

- 1717 RSpec examples → 0 failures (+44 from Phase 9 baseline).
- Rubocop clean.
- Brakeman clean.

## Reviewer playbook

`docs/orchestration/playbooks/2026-05-10-phase-10-mcp-scope-simplification.md`

## Security findings

`docs/orchestration/playbooks/security-2026-05-10-phase-10-mcp-scope-simplification.md`
— Verdict: CLEAR TO MERGE. 0 phase-10-introduced critical/high/medium. 3 low + 3
informational, all non-blocking.

## Validation steps when you're back

1. Already reseeded with new dev token:
   `CCvwZcLPGynpEM5SIAKRKjnsQrrqTTe506S-gf-QICs`. (Save it now — only shown
   once. If you lose it, reseed.)
2. **Re-pair Claude Mobile MCP**: revoke the existing connection, re-add
   `mcp.pitomd.com`, walk consent. Should display two scopes (`dev` + `app`)
   with the locked copy.
3. **Re-pair Claude.ai Web MCP**: same flow.
4. Smoke `list_docs` from Claude Mobile (dev tool) → should succeed.
5. Smoke `list_channels` (or any app tool) → should succeed.
6. Production strip-on-release dry-run (optional):
   `RAILS_ENV=production RAILS_MASTER_KEY=<key> bin/rails runner 'puts Scopes::ALL.inspect'`
   → `["app"]`.
7. Legacy scope rejection: `/oauth/authorize?scope=dev:read+app:write` →
   `error=invalid_scope`. New shape: `?scope=dev+app` → consent renders.

## Open follow-ups (non-blocking)

- F3 — runtime second gate in `Mcp::ToolAuth.require_scope!` for literal
  "defense-in-depth" framing.
- F5 — emit `auth.insufficient_scope` audit log entries.
- F6 — consolidate `Scopes.dev_exposed?` / `Mcp::PitoServer.dev_scope_exposed?`.
- Production `force_ssl` posture (Phase 16+ territory).
- Brakeman ignore-file housekeeping (Phase 9-era; 2 obsolete entries).
