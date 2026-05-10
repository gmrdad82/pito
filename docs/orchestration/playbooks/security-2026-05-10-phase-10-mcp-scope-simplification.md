# Security audit — Phase 10 (MCP scope simplification: 9 → `dev` + `app`)

**Branch:** `main` (commits `f5b15bd` + `56cb808`) **Spec:**
`docs/plans/beta/10-mcp-scope-simplification/specs/01-collapse-to-dev-app.md`
**ADR:** `docs/decisions/0004-mcp-scope-simplification-dev-app.md` **Reviewer
playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-10-mcp-scope-simplification.md`
**Audit run:** 2026-05-10 11:46

## Verdict

**CLEAR TO MERGE.** No Critical, High, or Medium findings. Three Low and three
Informational notes — none gate the commit.

## Findings by severity

- Critical: 0
- High: 0
- Medium: 0
- Low: 3
- Informational: 3
- Phase-10-introduced findings: 0 critical, 0 high, 0 medium

## F1. `OauthApplication.scopes` whitelist rewrite is a privilege widening for the application (LOW)

- **Location:**
  `db/migrate/20260510110333_revoke_tokens_for_scope_simplification.rb` lines
  22-32, 77-83
- **Description:** The legacy mapping collapses `yt:read`, `yt:write`,
  `yt:destructive`, `project:read`, `project:write` all to `app`. An application
  that previously held a read-only `yt:read` whitelist now holds the full `app`
  whitelist. **However** the whitelist is an upper bound on what the application
  may request; it does not directly issue a token. All in-flight access tokens
  and grants are revoked by the same migration, so the next bearer cannot
  inherit the widened privileges silently — the resource owner must walk a fresh
  consent screen and explicitly approve the new (more permissive) `app` scope.
  Risk is bounded by the locked re-pair ceremony in the manual playbook.
- **Recommendation:** No code change. The destructive-and-reseed posture +
  soft-revoke is the right safety net. Mention in the ADR / log that the
  explicit re-consent flow is the boundary.
- **References:** OWASP A01:2021 (Broken Access Control).

## F2. Migration `rewrite_scopes` defensive `["app"]` fallback is dead code (LOW)

- **Location:**
  `db/migrate/20260510110333_revoke_tokens_for_scope_simplification.rb` line 81
- **Description:** `mapped = ["app"] if mapped.empty?` only fires when an
  application's scopes string contained zero recognised entries. Since every
  legacy entry maps to a non-nil value, the only path is hand-crafted bogus
  scope strings — which `enforce_configured_scopes` would have refused at create
  time. Dead in practice.
- **Recommendation:** Either remove (let empty mapping raise visibly) or pin a
  comment ("defense-in-depth for hand-edited rows; not reachable through any UI
  path"). Either fine; current behaviour is safe (defaults to `app` only, never
  `dev`).

## F3. `tool_registry_spec.rb` documents that `require_scope!` returns nil for smuggled `["dev"]` token in production (LOW)

- **Location:** `spec/requests/mcp/tool_registry_spec.rb` lines 132-152
- **Description:** Test pins the contract: when `expose_dev_scope=false` and a
  hand-crafted `["dev"]` token reaches
  `Mcp::ToolAuth.require_scope!(Scopes::DEV)`, the helper returns nil (success)
  because it does a literal string match. The "defense-in-depth, both gates"
  claim is realised at the **registry-not-registered** layer only — the runtime
  `require_scope!` does NOT independently verify that the requested scope is in
  the production catalog. In practice, the registry gate is sufficient because
  the smuggled token cannot dispatch a tool that isn't in the registry.
- **Recommendation:** Either (a) accept the registry gate as the only effective
  layer (it is sufficient) and update the ADR's "defense-in-depth" framing, or
  (b) add a cheap second check inside `Mcp::ToolAuth.require_scope!`:
  `return error_response(scope) unless Scopes.all.include?(scope.to_s)`. Option
  (b) costs nothing. Recommend (b) as a follow-up if master wants strongest
  framing.

## F4. `WellKnownController` correctly drops `dev` in production via `Scopes::ALL` (INFORMATIONAL — positive)

- **Location:** `app/controllers/well_known_controller.rb` lines 39, 75
- **Description:** Constant `Scopes::ALL` is captured at boot AFTER
  `config/environments/production.rb` sets `expose_dev_scope = false`, so
  production `/.well-known/oauth-authorization-server` and
  `/.well-known/oauth-protected-resource` advertise `scopes_supported: ["app"]`
  only. `dev` is not leaked.

## F5. Audit log doesn't capture scope-required on rejection (INFORMATIONAL — pre-existing)

- **Location:** `app/lib/api/token_authenticator.rb` line 119,
  `app/mcp/tool_auth.rb` lines 23-29
- **Description:** Bearer dispatch's audit always passes `scope_required: nil`
  because scope-check happens later. `Mcp::ToolAuth.require_scope!` does NOT
  emit an audit log entry on rejection. Forensic review of `auth_audit.log`
  cannot reconstruct which scope was demanded vs which the token carried.
  Pre-existing (Phase 5); inherited.
- **Recommendation:** Track as follow-up: emit an `auth.insufficient_scope`
  audit entry from `require_scope!` carrying required scope, current scopes,
  tool name. Do not block Phase 10.
- **References:** OWASP ASVS V8.1.4.

## F6. `Scopes.dev_exposed?` and `Mcp::PitoServer.dev_scope_exposed?` duplicate flag resolution (INFORMATIONAL)

- **Location:** `app/lib/scopes.rb` lines 43-47, `app/mcp/pito_server.rb` lines
  61-65
- **Description:** Reviewer's nit. Two methods read the same flag through
  identical defensive guards. Cosmetic.
- **Recommendation:** Replace `Mcp::PitoServer.dev_scope_exposed?` with
  `Scopes.dev_exposed?` in a follow-up cleanup.

## Out-of-scope but noted

- `config.force_ssl` not enabled in production (Brakeman pre-existing).
  Cloudflare tunnel terminates TLS, but production initializer should set
  `config.assume_ssl = true` and `config.force_ssl = true` before external
  reach.
- `Note.find` and `ApiToken.find` unscoped finds (pre-existing Phase 8).
  Install-wide singletons; `find` raises `RecordNotFound` mapped to 404. Low
  priority.
- Dependabot alert #1 on `pito` CLI — already in
  `docs/orchestration/follow-ups.md`.

## Quality gate evidence

- **Brakeman strict** (`-w1`): 4 findings, 0 new in Phase 10. All pre-date this
  phase.
- **Legacy scope grep**: zero matches in production code paths.
- **Catalog membership**: dev/test `["dev", "app"]`, production `["app"]`.
  Verified.
- **Strip-on-release contract**: 4 enforcement layers verified — `Scopes::ALL`
  membership, Doorkeeper `default_scopes(*Scopes::ALL)`, MCP tool registry
  filter, `ApiToken` validation.
- **Soft-clip monkey-patch**: unchanged on disk; spec sweep covers legacy
  reject + new accept + production-mode dev reject.
- **Migration mapping**: conservative — every legacy → 2-scope without dev/app
  boundary crossings.
- **Token revocation**: ApiToken, OauthAccessToken, OauthAccessGrant all
  soft-revoked in single transaction; verified by spec.
- **Race condition** (mid-flight grant during deploy): half-issued grant
  soft-revoked; user re-pairs. Acceptable.
- **Token rotation messaging**: revoked tokens fail with proper
  `WWW-Authenticate` + `revoked_token` error. Clean failure mode.
- **MCP rack-app gate ordering**: TokenAuthenticator first, then Current.\* set,
  then dispatch via PitoServer registry honoring `dev_scope_exposed?`.

## Blockers

None. **CLEAR TO MERGE.**
