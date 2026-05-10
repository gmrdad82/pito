# Security audit — Phase 8: Tenant Drop + Email-Only Login

**Branch:** `main` (uncommitted, vs `origin/main`) **Spec:**
`docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
**Reviewer playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-8-tenant-drop-and-email-only-login.md`
**Audit run:** 2026-05-10

## Verdict

**MERGE WITH FIX-FORWARD.** No Critical or High findings. One Medium that should
land as a fix-forward before broader release (account-enumeration timing
oracle). The rest are Low / Informational.

## Findings by severity

- Critical: 0
- High: 0
- Medium: 1
- Low: 3
- Informational: 4

## F1 — MEDIUM. Account-enumeration timing oracle in `bcrypt_dummy_compare` (cost mismatch)

- **Location:** `app/controllers/sessions_controller.rb:121-128`
- **Description:** Dummy bcrypt compare precomputed at
  `BCrypt::Engine::MIN_COST` (4 rounds) but `User#authenticate` runs at
  `BCrypt::Engine::DEFAULT_COST` (12 rounds). ~220x timing asymmetry (~0.9ms vs
  ~198ms) defeats the dummy's purpose. A network attacker distinguishes "email
  exists" (slow real bcrypt) from "email doesn't exist" (fast dummy bcrypt) via
  a single timing measurement. Pre-Phase-8 issue (introduced in Phase 6/7 commit
  `718996c`); Phase 8's spec listed timing-attack resistance as covered.
- **Recommendation:** Compute dummy at `BCrypt::Engine::DEFAULT_COST` (or
  `ActiveModel::SecurePassword.min_cost ? MIN_COST : DEFAULT_COST` to track
  test-env override). One-line fix; spec assertion is straightforward.
- **References:** OWASP ASVS V2.4.5; CWE-208.
- **Status (post-audit):** Master agent dispatched fix-forward as a follow-up
  `pito-rails-impl` task on 2026-05-10. Once landed, this finding moves to
  "Closed."

## F2 — LOW. Seed fallback to placeholder credentials silently provisions a user with a known password

- **Location:** `db/seeds.rb:39-54`
- **Description:** When `Rails.application.credentials.dig(:owner)` is missing
  in dev, the seed prints `WARNING:` and falls back to `owner@example.test` /
  `change-me-please`, creates a `User` row, and continues. The dev-token-pepper
  missing path correctly `abort`s in dev — the `:owner` block deserves the same
  posture.
- **Recommendation:** Match the pepper path: `abort` in `Rails.env.development?`
  when `:owner` block is missing. Test/CI/non-interactive paths keep the
  warning + fallback.
- **References:** OWASP ASVS V2.10.2; CWE-1392.

## F3 — LOW. `URI::MailTo::EMAIL_REGEXP` accepts addresses without a TLD

- **Location:** `app/models/user.rb:24`
- **Description:** `URI::MailTo::EMAIL_REGEXP` permits `user@localhost`,
  `user@x`. Academic for single-operator install; matters when Theta-phase
  introduces multi-user signup or invite flows.
- **Recommendation:** Defer until multi-user signup ships. Track in
  `docs/orchestration/follow-ups.md`.
- **References:** RFC-conformant behavior; defense-in-depth only.

## F4 — LOW. Brakeman `Unscoped Find` warnings (3) on `Note` and `ApiToken`

- **Location:** `app/controllers/notes_controller.rb:119`,
  `app/controllers/settings/tokens_controller.rb:83,87`
- **Description:** `brakeman -q -A -w1` (strict + all-checks) surfaces three
  weak-confidence `Unscoped Find` warnings. Per ADR 0003, the install is
  single-tenant + multi-user with no per-user data isolation; every
  authenticated user has install-wide access. Both controllers include
  `Sessions::AuthConcern` so routes require auth and unscoped find is the
  correct semantic. Brakeman cannot reason about the ADR-locked authorization
  model. Also: `brakeman -q -w1` reports 2 obsolete-ignore entries (the
  `SendFile` carve-out at `footages_controller#serve_frame` and the
  `VerbConfusion` carve-out at `Sessions::AuthConcern#stash_intended_url`) —
  Concern N4 from the reviewer's playbook. Underlying defenses still apply;
  fingerprints shifted because of the `Api::AuthConcern` rewrite.
- **Recommendation:** No code change. Either (a) brief note in `docs/auth.md`
  explaining `Unscoped Find` warnings are expected in single-install +
  multi-user posture, OR (b) add fingerprints to `config/brakeman.ignore` with
  `note` blocks. Option (a) preferred; pair with the obsolete-ignore refresh.
- **References:** ADR 0003.

## F5 — INFORMATIONAL. MCP rack-app token-revocation chain verified clean

- **Location:** `app/mcp/rack_app.rb`, `app/lib/api/token_authenticator.rb`,
  `spec/requests/mcp/rack_app_auth_spec.rb`
- **Description:** Spec concern: with the cross-tenant defense-in-depth check
  removed, does the auth chain still reject revoked / expired / unknown tokens?
  Verified: `Api::TokenAuthenticator#call` checks `token.revoked?` and
  `token.expired?` for both `ApiToken` and `OauthAccessToken`, returns
  `failure("revoked_token")` / `failure("expired_token")`, and the rack app's
  post-auth `user.nil?` branch (line 34-38) catches the hard-deleted-User edge
  case. Per-tool scope enforcement via `Mcp::ToolAuth.require_scope!` is still
  wired.
- **Recommendation:** None. Filed for audit trail.

## F6 — INFORMATIONAL. Doorkeeper scope catalog and grant-flow whitelist intact

- **Location:** `config/initializers/doorkeeper.rb`
- **Description:** Verified: `default_scopes Scopes::DEV_READ`,
  `optional_scopes(*(Scopes::ALL - [DEV_READ]))`, `enforce_configured_scopes`,
  `force_pkce`, `grant_flows %w[authorization_code]`, `use_refresh_token` all
  remain. Implicit / ROPC / Client Credentials NOT in `grant_flows` so
  Doorkeeper rejects with `unsupported_grant_type` before reaching any
  authenticator block. The `resource_owner_authenticator` block now skips the
  `Current.tenant` pin but still resolves the cookie via
  `Sessions::Authenticator.call(request)`, sets `Current.user` and
  `Current.session`, calls `auth_result.session.touch_activity!`, returns
  `auth_result.session.user`. No scope-elevation regression.
- **Recommendation:** None.

## F7 — INFORMATIONAL. Storage-path migration: traversal defenses preserved

- **Location:** `app/lib/notes_filesystem.rb`, `app/lib/pito/assets_root.rb`,
  `app/controllers/footages_controller.rb:128-147`,
  `app/controllers/api/footages_controller.rb:97-122,180-186`
- **Description:** Verified: `NotesFilesystem.absolute_path_for` still calls
  `sanitize_relative` (rejects `..` and absolute paths) AND
  `ensure_within_project!` (uses `File.realpath` to follow symlinks before
  containment check); `Pito::AssetsRoot.path` still validates with `cleanpath` +
  `inside?` + rejects empty / leading-`/` / traversal segments; the frame
  endpoints re-check the `\d{2}-\d{2}-\d{2}` regex inside `serve_frame`
  (defense-in-depth even though the route constraint already enforces it); the
  API frame upload (`update_frames`) regex-gates the `timestamp` key before any
  FS write and uses `Pito::AssetsRoot.ensure_dir!` for path resolution. The
  "Legacy tenant path read returns not-found" test the spec called for is not
  implemented, but in practice the legacy `tenant-1/` path simply doesn't exist
  on disk after the destructive reseed (404 via the existing `head :not_found`
  branch).
- **Recommendation:** None for this phase. If a Theta-phase migration includes a
  one-shot legacy-path rejection, document it then.

## F8 — INFORMATIONAL. Audit-log key rename complete; no event was dropped

- **Location:** `app/controllers/sessions_controller.rb:37,43`
- **Description:** `identifier_attempted` → `email_attempted`.
  `git grep 'identifier_attempted'` returns zero matches in `app/` and `spec/`.
  The three `audit(...)` calls (`session.login.failed unknown_email`,
  `session.login.failed wrong_password`, `session.login.success`) are all
  preserved. `session.login.throttled` and `session.logout` are preserved. The
  `Api::TokenAuthenticator#audit` chain is unchanged. No audit event was
  dropped.
- **Recommendation:** None.

## Quality gate evidence

- **Brakeman** (`bundle exec brakeman -q -w1`): 0 security warnings. 2
  obsolete-ignore entries (Concern N4 from reviewer playbook).
- **Brakeman strict** (`bundle exec brakeman -q -A -w1`): 4 warnings —
  `Missing Encryption` (ForceSSL not enabled in production.rb; project runs
  behind Cloudflare tunnel that enforces TLS termination; out-of-scope for
  Phase 8) plus 3 weak-confidence `UnscopedFind` warnings analyzed in F4.
- **Bundler-audit**: no advisories (1078-advisory DB, last updated 2026-03-30).
- **Reviewer suite**: RSpec 1662/0/0; rubocop 420/0; brakeman -w2 0 warnings.
- **Diff sweep:** `git grep` for
  `Tenant|tenant_id|Current\.tenant|BelongsToTenant|find_by_username_or_email|username`
  in `app/`, `lib/`, `spec/`, `db/`, `config/` shows only explanatory comments +
  migration body + schema-version comment + intentional `_legacy_tenant_id`
  cron-compat shim in `NoteSyncJob#perform`. No live tenant references.
- **Migration safety:** drop is wrapped in `if foreign_key_exists?` /
  `if column_exists?` guards. Idempotent on re-run after interruption. The
  `down` is bookkeeping-only per ADR 0003.
- **Reseed posture:** seed prints user email (not sensitive) and dev API token
  plaintext (intentional one-time display). Does NOT print owner password.

## Out-of-scope but noted

- F4 obsolete-ignore drift in `config/brakeman.ignore` (also Concern N4 in
  reviewer playbook). Pair brakeman-ignore refresh with next security-sensitive
  dispatch.
- F2 placeholder-credential fallback. Trivial fix; track in follow-ups.
- F3 weak email regex. Revisit when multi-user signup ships.

## Blockers

None. F1 is Medium and pre-dates Phase 8; lands as fix-forward, does not block
merge.

## Summary

- Critical/High blockers: none.
- One Medium fix-forward (F1) — already dispatched as follow-up rails-impl on
  2026-05-10.
- Three Low / four Informational findings — track in
  `docs/orchestration/follow-ups.md`; none warrant a separate spec.
