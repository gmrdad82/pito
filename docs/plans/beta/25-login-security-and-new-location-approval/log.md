# Phase 25 — Login Security + New-Location Approval · Session Log

## 2026-05-11 — sub-spec 01f auto-block list + purge UI (pito-rails-impl) [skipci]

**Dispatch:** `pito-rails-impl` against
`specs/01f-auto-block-list-and-purge-ui.md`. Finishes the auto-block
surface by wiring routes, adding the per-row unblock action-screen,
extracting a row component + helper, and ticking the acceptance
checks. Most of 01f's controllers, services, views, and MCP tool
arrived earlier as scaffolding under HEAD `ec2bc26`; this session
glued them together and filled the remaining gaps.

**Routes (new)**

- `GET/POST /settings/security/blocks/purge` — helper
  `settings_security_blocks_purge_path`. Declared outside `resources`
  so the helper reads naturally instead of `purge_settings_security_blocks_*`.
- `GET/POST /settings/security/attempts/purge` — helper
  `settings_security_attempts_purge_path`. Same shape.
- `GET/POST /settings/security/blocks/:block_id/unblocking` — helper
  `settings_security_block_unblocking_path`. Per-row action-screen for
  soft-unblock. Nested singular `resource` keeps the URL hierarchical
  while leaving the bulk-purge surface a flat collection action.

**Controllers (new)**

- `Settings::Security::Blocks::UnblockingsController` — `show`
  renders the action-screen; `create` consumes `confirm=yes` and
  delegates to `Auth::BlockedLocationUnblocker.call(blocked_location:, acting_user:, source: :web)`.
  Idempotent on an already-unblocked row (notice copy
  reflects the no-op). Cancels on `confirm!=yes` or missing confirm.
  `NotBlocked` is caught and surfaced as a friendly redirect.

**Views (new + refactored)**

- `settings/security/blocks/unblockings/show.html.erb` — full
  action-screen with `dl` of the block details and a `[unblock]` /
  `[cancel]` footer. `data-keyboard-confirmation` wired for the
  global keyboard controller.
- `settings/security/blocks/index.html.erb` — refactored to render
  rows through `BlockedLocationRowComponent` (was inline markup).
- `settings/security/blocks/show.html.erb` — adds `[unblock]`
  bracketed-link for active rows in the action footer.
- `settings/security/show.html.erb` — adds `[auto-block list]`
  bracketed-link next to `[all attempts]` so the dashboard exposes
  the block surface.

**Components (new)**

- `BlockedLocationRowComponent` (`.rb` + `.html.erb`) — single-row
  presenter for the block list table. Renders the source badge
  (uppercase), short fingerprint, ip prefix, attempt counter,
  last-attempt timestamp, state label, and the conditional
  `[unblock]` / `[view]` actions. Soft-unblocked rows skip the
  unblock link (no idempotent re-unblock surface).

**Helpers (new)**

- `BlockedLocationsHelper` — `source_badge`, `state_label`,
  `state_css`, `reason_label`, `age` formatter. Centralises the
  presentation vocabulary so the index, detail, and unblock screens
  stay aligned.

**Specs (new)**

- `spec/requests/settings/security/blocks/unblockings_spec.rb` —
  GET action-screen for active + soft-unblocked + missing rows; POST
  confirm=yes / confirm=no / no-confirm / idempotent / 404 / unauth.
  11 examples.
- `spec/components/blocked_location_row_component_spec.rb` — active
  vs soft-unblocked variants, source badges (WEB/TUI/MCP), fingerprint
  truncation, attempt counter, last-attempt timestamp formatting,
  `show_unblock_link: false` override. 15 examples.
- `spec/helpers/blocked_locations_helper_spec.rb` — coverage for all
  five helpers, including the age formatter at each threshold and the
  reason fallback. 14 examples.
- `spec/routing/settings_security_blocks_routing_spec.rb` — extended
  with the two unblocking routes (GET + POST). 8 examples total.

Existing specs (`blocks_spec.rb`, `blocks/purges_spec.rb`,
`attempts/purges_spec.rb`, `blocked_location_lister_spec.rb`,
`blocked_location_purger_spec.rb`, `blocked_location_unblocker_spec.rb`,
`blocked_locations_list_spec.rb`) flip from red (missing routes) to
green with no edits.

**MCP tool**

`Mcp::Tools::BlockedLocationsList` (read-only) was already in place
at HEAD `ec2bc26` from earlier scaffolding; it now reads through the
same route surface the web UI exposes. The destructive companions
(`login_attempt_block`, `login_attempt_unblock`, `login_attempt_purge`)
landed in 01d.

**Acceptance check (per spec)**

- [x] `/settings/security/blocks` paginated index, filterable.
- [x] `/settings/security/blocks/:id` detail with `[unblock]` and
      `[purge]` bracketed-links.
- [x] Unblock + purge action-screens (no JS confirm).
- [x] Unblock soft-marks via `unblocked_at`; row stays for audit.
- [x] Purge hard-deletes rows; audit log entry left as a TODO marker
      in both purge controllers (lands when `Auth::AuditLogger` write
      is added to the purge path — see TODOs in the controllers).
- [x] Purge requires at least one filter (safety rule).
- [x] Attempt log purge mirrors the same UX at
      `/settings/security/attempts/purge`.
- [x] No JS confirm / alert / prompt.
- [x] Yes / no Booleans at every external boundary.
- [-] TUI `g s b` opens the read-only block list — deferred (Phase 26
      P2 per spec open question).
- [x] MCP `blocked_locations_list` (read-only) returns the same shape
      as the web index.
- [-] `docs/auth.md` updates — deferred to `pito-docs` sweep.
- [-] Auto-block decay (Q-E) — locked: blocks persist until manual
      unblock / purge. Documenting in `docs/auth.md` falls to the
      docs agent.
- [x] Full RSpec green on the touched files (142 examples, 0 failures
      across routing + request + component + helper + service + MCP).
- [x] Brakeman clean (no warnings, 0 errors).

**Files touched**

```
app/controllers/settings/security/blocks/unblockings_controller.rb  (new)
app/views/settings/security/blocks/unblockings/show.html.erb        (new)
app/views/settings/security/blocks/index.html.erb                   (refactor → component)
app/views/settings/security/blocks/show.html.erb                    (add [unblock])
app/views/settings/security/show.html.erb                           (add [auto-block list] link)
app/components/blocked_location_row_component.rb                    (new)
app/components/blocked_location_row_component.html.erb              (new)
app/helpers/blocked_locations_helper.rb                             (new)
config/routes.rb                                                    (wire purge + unblocking routes)
spec/requests/settings/security/blocks/unblockings_spec.rb          (new, 11 examples)
spec/components/blocked_location_row_component_spec.rb              (new, 15 examples)
spec/helpers/blocked_locations_helper_spec.rb                       (new, 14 examples)
spec/routing/settings_security_blocks_routing_spec.rb               (+2 examples for unblockings)
docs/plans/beta/25-login-security-and-new-location-approval/plan.md (tick 01f)
docs/plans/beta/25-login-security-and-new-location-approval/log.md  (this entry)
```

**Manual test recipe**

1. `bin/dev`.
2. Seed an active block in the console:
   `BlockedLocation.create!(fingerprint_hash: "a"*64, ip_prefix: "1.2.3.0/24", blocked_by_user: User.first, source_surface: :web)`.
3. Visit `/settings/security` → confirm the `[auto-block list]` link.
4. Click through to `/settings/security/blocks` → row appears.
5. Click `[unblock]` (or `[view]` then `[unblock]`) → action-screen
   shows the pair details + `[unblock]` / `[cancel]` footer.
6. Confirm → redirected to the block detail page with
   `block unblocked.` notice; state shows `unblocked at ...`.
7. From the index, switch the `active` filter to `no` → unblocked row
   shows; switch to `yes` → empty list.
8. Bulk-purge: `/settings/security/blocks?source_surface=web` →
   `[purge by filter]` → preview count + `[purge]` → confirm → row
   disappears.
9. Repeat for attempts: `/settings/security/attempts/purge?result=failed`
   → preview → confirm → matching attempts vanish.
10. Pre-camera sanity: confirm no JS `alert` / `confirm` fires
    anywhere in the flow.

**Open follow-ups (queued under `docs/orchestration/follow-ups.md`)**

- TUI block-list pane (`g s b`) — Phase 26 P2.
- `docs/auth.md` write-up of the unblock + purge procedures + the
  Q-E lock (blocks persist forever) — `pito-docs` sweep.
- Wire `Auth::AuditLogger` into both purge controllers (TODO markers
  already in place; the spec calls for this and the audit log surface
  exists since 01d).
- Optional: "block this fingerprint going forward" link on the
  attempt detail page (spec open question, locked yes — minor add).

## 2026-05-11 — sub-spec 01e TOTP 2FA + backup codes (pito-rails-impl) [skipci]

**Dispatch:** `pito-rails-impl` against
`specs/01e-totp-2fa-integration-with-backup-codes.md`. Adds standard
TOTP 2FA (1Password-compatible) on top of the 01b new-location flow,
plus 10 single-use backup codes. Plain `rotp`; no 1Password Connect
SDK. TOTP gates EVERY login (not just new locations) once enrolled
so a stolen device cookie cannot bypass it.

**Gems added**

- `rotp ~> 6.3` — TOTP generation + verification (RFC 6238).
- `rqrcode ~> 2.2` — SVG QR rendering for the one-shot enrollment view.
  Pulls `chunky_png` + `rqrcode_core` transitively.

**Migrations** — already `up` at HEAD `ec66c9b`. No new migrations.

- `users.totp_seed_encrypted` (`:text`, AR-encrypted plaintext envelope).
- `users.totp_enabled_at`, `users.totp_disabled_at`.
- `totp_backup_codes (user_id, code_digest, used_at, timestamps)`.

**Models**

- `app/models/user.rb` — `encrypts :totp_seed_encrypted`,
  `has_many :totp_backup_codes`, `#totp_enabled?` (spec definition:
  `seed.present? && disabled_at.nil?`), `#totp_uri(issuer:)`.
- `app/models/totp_backup_code.rb` (new) — `belongs_to :user`,
  validations, `:unused` / `:used` scopes, `#matches?(plaintext)`
  (constant-time BCrypt compare), `#used?`. The model never sees the
  plaintext after creation.

**Services (Auth::*)**

- `Auth::TotpEnroller` — `ROTP::Base32.random_base32` (160 bits),
  10 backup codes from the 27-char safe alphabet (no `0` / `O` /
  `1` / `I` / `L` / `B` / `8`), BCrypt digests at rest. Returns
  `{ seed:, codes: }` ONCE. Mid-enrollment users (seed present,
  no `enabled_at`) can re-enroll without disabling — a lost flash
  must not strand them.
- `Auth::TotpVerifier` — `drift_behind: 30` so the previous
  30-sec window still validates. Returns `:ok` / `:invalid`.
- `Auth::BackupCodeConsumer` — finds the matching row, stamps
  `used_at` under a pessimistic row lock so concurrent consumes
  cannot both succeed. Returns `:ok` / `:invalid` / `:already_used`.
- `Auth::TotpDisabler` — clears seed, stamps `disabled_at`,
  destroys backup codes, audit-logs via `Auth::AuditLogger`.
- `Auth::BackupCodeRegenerator` — destroys + regenerates 10 fresh
  codes (seed untouched), audit-logs.

**Controllers + views**

- `Settings::Security::TotpsController`
  (`/settings/security/totp{,/show,/confirm,/disable}`) — six
  actions for new / create / show (one-shot) / update (confirm) /
  destroy_screen / destroy_confirmed. The one-shot view is the
  ONLY surface that ever displays the seed + the 10 plaintext
  codes; subsequent loads redirect.
- `Settings::Security::TotpBackupCodesController`
  (`/settings/security/totp_backup_codes{,/new}`) — read + action-
  screen regenerate. Plaintexts never re-displayed; freshly minted
  codes pass through a one-shot flash on the show page.
- `Login::TotpChallengesController` (`/login/totp`) —
  `allow_anonymous` since the pre-auth marker is the only
  credential at this stage. Accepts a 6-digit TOTP OR an 8-char
  backup code. On success: `reset_session`, `Auth::SessionActivator`
  with `reason: :new_location_2fa_passed`, fresh signed cookie
  (LD-12 — token rotation). On failure: `LoginAttempt` with
  `reason: :twofa_failed`, generic "login failed." flash, 422.
- `SessionsController#create` — adds the TOTP gate: when a
  password-verified user has `totp_enabled?`, the controller stashes
  the pre-auth marker and bounces to `/login/totp` BEFORE the
  trusted / new-location dispatch runs. Pending-approval still
  works for non-2FA users.
- `Settings::SecurityController#show` — flips `@twofa_enabled` to
  read `Current.user.totp_enabled?` and exposes a
  `[manage 2FA]` bracketed link on the dashboard.

**Views** — pure ERB, monospace, bracketed-link convention.

- `app/views/settings/security/totps/{new,show,destroy_screen}.html.erb`
- `app/views/settings/security/totp_backup_codes/{show,new}.html.erb`
- `app/views/login/totp_challenges/show.html.erb`

**Helper**

- `app/helpers/totp_helper.rb` — issuer constant + accessor so the
  QR code, the `User#totp_uri`, and the enrollment view agree on
  `"pito"`.

**MCP**

- `app/mcp/tools/totp_status.rb` (new, `auth` scope, read-only) —
  reports `totp_enabled` (yes/no), `totp_enabled_at`, unused +
  used backup-code counts. Counts stay numeric per the hard rule
  (yes/no is for Booleans only). Registered in
  `app/mcp/pito_server.rb`'s `AUTH_TOOL_NAMES` so strip-on-release
  carries it.

**Routes**

- `get/post /login/totp` (was a placeholder redirect at `01b`).
- `get/post /settings/security/totp`,
  `get /settings/security/totp/show`,
  `patch /settings/security/totp/confirm`,
  `get/post /settings/security/totp/disable`,
  `get /settings/security/totp_backup_codes`,
  `get /settings/security/totp_backup_codes/new`,
  `post /settings/security/totp_backup_codes`.

**Factories**

- `spec/factories/totp_backup_codes.rb` (new).
- `spec/factories/users.rb` — `:totp_enabled` trait that seeds a
  deterministic base32 seed + 10 backup codes.

**Spec coverage** (149 new examples — all green; 315 examples
across `spec/services/auth/`, `spec/requests/sessions_spec.rb`, and
`spec/requests/login/` re-verified):

- `spec/models/user_spec.rb` — encryption at rest, `totp_enabled?`,
  `totp_uri`, cascade destroy of backup codes.
- `spec/models/totp_backup_code_spec.rb` — validations, `matches?`,
  scopes, `used?`.
- `spec/services/auth/totp_enroller_spec.rb` — happy / sad / flaw
  (10 codes, safe alphabet, re-enrollment after disable, refusal
  when already confirmed).
- `spec/services/auth/totp_verifier_spec.rb` — happy / drift /
  non-6-digit input / unenrolled-user / nil-user guard.
- `spec/services/auth/backup_code_consumer_spec.rb` — happy / used /
  invalid / reuse rejection.
- `spec/services/auth/totp_disabler_spec.rb` — clears seed +
  destroys codes + audit-logs; no-op on unenrolled user.
- `spec/services/auth/backup_code_regenerator_spec.rb` — happy /
  raises on unenrolled user / audit-log row.
- `spec/requests/login/totp_challenges_spec.rb` — TOTP success
  (activates, rotates, writes `new_location_2fa_passed`), backup
  code success, wrong TOTP (422 + `twofa_failed`), already-used
  backup (422), missing pre-auth marker.
- `spec/requests/settings/security/totps_spec.rb` — full enroll /
  confirm / disable / auth-gate cycle.
- `spec/requests/settings/security/totp_backup_codes_spec.rb` —
  count display, action-screen regenerate, no-plaintext invariant.
- `spec/routing/settings_security_totp_routing_spec.rb` — route
  pins.
- `spec/mcp/tools/totp_status_spec.rb` — happy + scope-gate +
  yes/no boundary + numeric counts.
- `spec/system/totp_2fa_journey_spec.rb` (rack_test) — happy
  enrollment → confirm; sad wrong-code; regenerate-codes action-
  screen flow.

**Locked spec deviations**

- Column / table names follow the migrations on disk:
  `totp_seed_encrypted` (not `totp_secret`), `totp_backup_codes`
  (not `backup_codes`). The model name is `TotpBackupCode` so the
  table mapping is conventional.
- `LoginAttempt.reasons` already declared `twofa_failed: 7`; the
  spec's `2fa_failed` would have collided with Ruby symbol naming
  rules, so the implementation uses `:twofa_failed`.
- `totp_enabled?` per spec: `seed.present? && disabled_at.nil?`.
  Re-enrollment was gated on `totp_enabled_at.present?` instead so
  a user mid-enrollment (seed present, no enabled_at) can recover
  from a lost one-shot flash without being stranded.

**Manual recipe** (the spec's, condensed)

1. `bundle install`, `bin/dev`.
2. `/settings/security/totp` → `[ enable 2FA ]`. Scan QR with
   1Password (or any TOTP app); save the 10 backup codes.
3. Enter a fresh 6-digit code → confirmation message. Verify
   `totp_enabled_at` in the DB.
4. Log out. From a new browser, password → bounce to `/login/totp`
   → 6-digit code → activated, redirect to `/`. New session token
   differs from the pre-auth cookie (LD-12).
5. `/settings/security/attempts` row carries
   `reason: new_location_2fa_passed`.
6. New browser again → password → `/login/totp` → enter a backup
   code → activates; that backup code stamps `used_at`. A second
   attempt with the same code fails with generic "login failed.".
7. `/settings/security/totp/disable` → enter fresh code → 2FA off.
8. `/settings/security/totp_backup_codes` → `[regenerate]` →
   fresh 10 codes shown once.
9. MCP: call `totp_status` → `{ totp_enabled: "yes",
   unused_backup_codes: 10, ... }`.

**Quality gates**

- RSpec — 149 examples / 0 failures on the new + touched specs.
  315 across the wider auth surface (services + sessions + login)
  re-verified green.
- RuboCop — clean on every new + touched file.
- Brakeman — `0 warnings` on the new code.
- bundler-audit — unchanged at this commit.

**Open items / handoff**

- The TUI is out of scope this phase (P2 — Phase 26).
  `Login::TotpChallenges#create` accepts the JSON envelope but the
  TUI does not currently route through it; spec calls this out
  explicitly.
- `docs/auth.md` doc surface (recovery procedure, backup-code reuse
  policy) belongs to `pito-docs`, not this lane.

## 2026-05-11 — sub-spec 01d MCP login_attempts tools (pito-mcp) [skipci]

**Dispatch:** `pito-mcp` agent against spec
`specs/01d-mcp-tools-pending-approve-block-purge.md`. Promotes the read
scaffolds from 01a / 01b to a fully-gated MCP surface. Adds the `auth`
MCP scope with strip-on-release semantics mirroring the `dev`
precedent (ADR 0004). Wires six new destructive / read tools through
the existing service layer (no new business logic).

**What landed**

Scope catalog

- `app/lib/scopes.rb` — adds `Scopes::AUTH = "auth"`, the
  `.auth_exposed?` runtime check, the matching `DESCRIPTIONS` entry.
  `Scopes::ALL` now orders `[dev, app, auth]` in the test/dev
  environments and strips `auth` from production builds via the
  `expose_auth_scope` flag.
- `app/models/api_token.rb` — adds `auth_scope_only_when_exposed`
  validation mirroring the dev guard. Stub-mid-process specs see the
  row rejected when the flag is `false`.
- `app/mcp/pito_server.rb` — strips `AUTH_TOOL_NAMES` from
  `tools/list` when `expose_auth_scope` is `false`. Defense-in-depth
  with the per-tool `require_scope!(Scopes::AUTH)` gate.
- `config/environments/{development,test,production}.rb` — three new
  `config.x.mcp.expose_auth_scope` declarations matching the existing
  `expose_dev_scope` pattern.

Tools (promoted)

- `app/mcp/tools/login_attempts_pending.rb` — scope gate swapped from
  the temporary `app` placeholder to `auth`.
- `app/mcp/tools/login_attempts_list.rb` — scope swapped to `auth`,
  filter set expanded (`until_ts`, `user_email`), invalid filters now
  return a structured `invalid_filter` error rather than silently
  widening the result set.
- `app/mcp/tools/blocked_locations_list.rb` — scope swapped to `auth`.

Tools (new)

- `app/mcp/tools/login_attempt_approve.rb` — delegates to
  `Auth::LoginAttemptApprover` with `source: :mcp`. Two-step
  `confirm: yes/no`; missing confirm returns a preview shape. Builds
  a synthetic `ActionDispatch::Request` via `Rack::MockRequest.env_for`
  so the downstream `Auth::SessionActivator` + `Auth::AttemptLogger`
  chain has a non-nil request object (the IP falls through to
  `0.0.0.0`; the audit row's `source_surface: :mcp` is the canonical
  marker).
- `app/mcp/tools/login_attempt_block.rb` — delegates to
  `Auth::LoginAttemptBlocker` with `source: :mcp`. Preview surfaces
  `already_blocked` + `will_create_blocked_location` yes/no flags so
  a caller knows whether the row will be a fresh BlockedLocation or
  reuse the existing pair via the unique partial index.
- `app/mcp/tools/login_attempt_unblock.rb` — delegates to the new
  `Auth::BlockedLocationUnblocker`. Accepts EITHER
  `blocked_location_id` OR `(fingerprint, ip_prefix)` pair. Idempotent
  on already-unblocked rows (returns `already_unblocked: yes` with no
  fresh audit row). Preview path describes the prospective stamp.
- `app/mcp/tools/login_attempt_purge.rb` — delegates to
  `Auth::AttemptPurger`. Empty filter rejected up-front so a tool-
  level error fires before the service raises `EmptyFilter`. Preview
  path computes the prospective row count without deleting (re-runs
  the same filter narrowing as the service). The purge audit row
  carries `target_type: User` (the actor), with
  `metadata: { scope: "login_attempts", filter, deleted_count }`. Q-K
  resolves: system-wide; any `auth`-scoped caller can purge any rows;
  the audit row identifies the actor.
- `app/mcp/tools/auth_audit_log_list.rb` — read-only paginated audit
  log. Filter set: `action`, `source_surface`, `since`, `until_ts`,
  `acting_user_email` (resolved through the User table), `target_type`,
  `target_id`. Output rows carry an `is_recent: yes/no` Boolean
  (7-day window) per LD-15.

Services (new)

- `app/services/auth/blocked_location_unblocker.rb` — soft-unblock
  with pessimistic lock on the row, idempotent for already-unblocked
  rows, audit-logs `action: :unblock`. Two callable shapes
  (row reference OR pair lookup); the pair-shape path only finds
  *active* matching rows so a caller passing the pair gets the same
  `not_found` shape as the controller. Audit row metadata carries
  `fingerprint_short` + `ip_prefix`.

Specs

- `spec/mcp/tools/login_attempt_approve_spec.rb` (new, 11 examples)
- `spec/mcp/tools/login_attempt_block_spec.rb` (new, 13 examples)
- `spec/mcp/tools/login_attempt_unblock_spec.rb` (new, 12 examples)
- `spec/mcp/tools/login_attempt_purge_spec.rb` (new, 11 examples)
- `spec/mcp/tools/auth_audit_log_list_spec.rb` (new, 14 examples)
- `spec/services/auth/blocked_location_unblocker_spec.rb` (new, 10 examples)
- `spec/lib/scopes_spec.rb` — refreshed for the three-scope catalog,
  added `.auth_exposed?` coverage + the `[app, auth]` /
  `[dev, app]` / `[app]` strip permutations.
- `spec/models/api_token_spec.rb` — added a parallel describe block
  for the new `auth_scope_only_when_exposed` validation.
- `spec/mcp/tools/login_attempts_list_spec.rb` — expanded to cover
  `until_ts`, `user_email`, combined-filter intersection, and the
  new "invalid filter raises an error" contract; old "silently
  ignored" case dropped.
- `spec/mcp/tools/{login_attempts_pending,blocked_locations_list}_spec.rb`
  — scope-gate tests updated to assert rejection against an `app`-only
  token (was: `dev`-only) reflecting the swap from `app` → `auth`.

Total: 175 examples across the touched files, 0 failures.
Rubocop: 26 files inspected, 0 offenses.

**Open questions resolved**

- **Q-K**: system-wide. Any `auth`-scoped caller acts on any rows;
  the audit row identifies the actor (acting_user_id). Codified in
  `login_attempt_purge.rb` and `blocked_location_unblocker.rb`.

**Open questions deferred to 01g / future**

- Per-call row cap for `login_attempt_purge` (spec proposal: cap at
  10k). Not implemented; the service-level `BATCH_SIZE = 1_000`
  already keeps each transaction small. Track if the field surfaces
  the need.
- `blocked_location_purge` MCP tool — out of scope for 01d (01f-side
  hard-delete UI). The `blocked_locations_list` read-only swap to
  `auth` lands here so callers can audit the block list from MCP.
- `login_attempt_revoke_session` separate from block — declined.
  Block already revokes; revoke-only path stays in the
  `/settings/sessions` UI.

**Files**

```
app/lib/scopes.rb                                    M
app/models/api_token.rb                              M
app/mcp/pito_server.rb                               M
app/mcp/tools/login_attempts_pending.rb              M
app/mcp/tools/login_attempts_list.rb                 M
app/mcp/tools/blocked_locations_list.rb              M
app/mcp/tools/login_attempt_approve.rb               +
app/mcp/tools/login_attempt_block.rb                 +
app/mcp/tools/login_attempt_unblock.rb               +
app/mcp/tools/login_attempt_purge.rb                 +
app/mcp/tools/auth_audit_log_list.rb                 +
app/services/auth/blocked_location_unblocker.rb      +
config/environments/development.rb                   M
config/environments/production.rb                    M
config/environments/test.rb                          M
spec/lib/scopes_spec.rb                              M
spec/models/api_token_spec.rb                        M
spec/services/auth/blocked_location_unblocker_spec.rb +
spec/mcp/tools/login_attempts_pending_spec.rb        M
spec/mcp/tools/login_attempts_list_spec.rb           M
spec/mcp/tools/blocked_locations_list_spec.rb        M
spec/mcp/tools/login_attempt_approve_spec.rb         +
spec/mcp/tools/login_attempt_block_spec.rb           +
spec/mcp/tools/login_attempt_unblock_spec.rb         +
spec/mcp/tools/login_attempt_purge_spec.rb           +
spec/mcp/tools/auth_audit_log_list_spec.rb           +
docs/plans/beta/25-login-security-and-new-location-approval/plan.md M
docs/plans/beta/25-login-security-and-new-location-approval/log.md M
```

**Out of scope (deferred to 01f / docs sweep)**

- `docs/mcp.md` scope-catalog table update and per-tool entries — the
  `pito-mcp` agent's file scope is the MCP layer; docs updates belong
  to the master agent's post-validation pass. Plan tickbox flips here;
  doc sweep happens before push.
- `docs/auth.md` "MCP auth surface" section — same reasoning.
- Per-token opt-in checkbox on `/settings/tokens/new` — UI work
  belongs to `pito-rails`; the model + catalog wiring above already
  supports the opt-in (token-mint with `scopes: [Scopes::AUTH]` is a
  valid path when the flag is on, rejected when the flag is off).

## 2026-05-11 — 01a — Attempt logging + fingerprinting

**Dispatch:** `pito-rails` agent against spec
`specs/01a-attempt-logging-and-fingerprinting.md`. Foundation sub-spec —
ships independently and unblocks 01b–01g. Locked decisions LD-1 (schema),
LD-2 (fingerprint composition), LD-3 (IP-prefix matching), LD-4 (geo
enrichment), LD-14 (generic failure copy), LD-15 (yes/no boundary), LD-17
(friendly URLs) all applied directly.

**What landed**

Database

- `db/migrate/20260511120000_create_login_attempts.rb` — schema per LD-1
  plus all 5 indexes (user_id, created_at, result, email_attempted,
  fingerprint_hash, composite (fingerprint_hash, ip_prefix),
  approved_by_user_id). `reason` enum encodes the full 15-value LD-1
  vocabulary so 01b–01g need no further migration.
- `db/migrate/20260511120001_create_blocked_locations.rb` — schema-only
  per LD-10. Unique partial index on (fingerprint_hash, ip_prefix).
  `source_surface` enum (web/tui/mcp) ready for 01d.
- `db/migrate/20260511120002_create_trusted_locations.rb` — schema-only
  per LD-5. Unique composite (user_id, fingerprint_hash, ip_prefix).
  01b will use this for new-location detection.

Migrations were applied against dev DB AND test DB.

Models

- `app/models/login_attempt.rb` — result/reason enums, validations,
  scopes (`recent`, `failed`, `succeeded`, `blocked_results`, `pending`,
  `for_user`, `for_fingerprint`, `for_ip`, `since`), `belongs_to`
  associations (user/notification/approved_by_user, all optional). Soft
  IP-family validation on `(ip, ip_prefix)`. `before_update` stamps
  `resolved_at` when transitioning out of `pending_approval` (01b prep).
  Two display helpers (`fingerprint_short`, `geo_summary`).
- `app/models/blocked_location.rb` — validations, `active` scope,
  `for_pair?` lookup (the hot path the AttemptLogger reads on every
  authenticate POST), `bump_attempt!` updater.
- `app/models/trusted_location.rb` — validations, `for_user` / `for_pair`
  scopes, `.trusted?` class helper.

Services

- `app/services/auth/fingerprint_composer.rb` — privacy-preserving
  fingerprint per LD-2. Accepts UA + Accept/Accept-Language/Accept-
  Encoding + Sec-Ch-Ua-Platform/Mobile + screen hint + locale hint.
  **Rejects** `canvas_hash`, `audio_hash`, `webgl_renderer`, `font_list`,
  `battery_level` kwargs with `ArgumentError` — defense-in-depth against
  a future regression that tries to add invasive signals. Pure function;
  deterministic; canonical input ordering.
- `app/services/auth/ip_prefix_calculator.rb` — service facade over
  `Pito::Auth::IpPrefix` so the AttemptLogger composes from one
  namespace.
- `app/services/auth/geo_enricher.rb` — MaxMind GeoLite2 offline lookup
  with the LD-4 fallback semantics: sync primary, deferred-flag flip on
  miss / over-budget (5 ms) / missing DB / missing gem. NEVER makes
  outbound HTTP. Returns `{city:, region:, country:}` (nils on miss).
  Memoized reader per-DB-path; test-only `reset_reader_for_test!` hook.
  Reads `ENV["PITO_GEOIP_DB_PATH"]`.
- `app/services/auth/attempt_logger.rb` — **single entry point**. The
  `SessionsController` MUST NOT bypass it for any LoginAttempt write.
  Composes fingerprint + ip_prefix + geo + UA, checks the auto-block
  list, writes the row, and enqueues `LoginAttemptGeoEnrichJob` when
  geo was deferred. Blocked-pair short-circuit rewrites `result:
  success` (or any non-:blocked result) to `result: blocked` and
  `reason: blocked_pair`, then bumps the BlockedLocation's
  attempt_count + last_attempt_at.

Jobs

- `app/jobs/login_attempt_geo_enrich_job.rb` — Sidekiq async backfill.
  Idempotent: row-already-has-geo and row-deleted-between-enqueue-and-
  run are both no-ops.

Lib

- `app/lib/pito/auth/ip_prefix.rb` — pure function. `/24` IPv4, `/64`
  IPv6, IPv4-mapped IPv6 unwrap.
- `app/lib/pito/auth/user_agent_parser.rb` — wraps `useragent` gem.
  Normalizes verbose OS strings ("OS X 10.15.7" → "macOS",
  "iOS 17.5.1" → "iOS", "Linux x86_64" → "Linux") so the attempt-log
  table stays compact and minor-version rolling doesn't multiply
  trusted-location rows.

Controllers

- `app/controllers/sessions_controller.rb` — now calls
  `Auth::AttemptLogger.call` on EVERY authenticate POST (success,
  wrong-password, unknown-email, rate-limited). On the success branch,
  re-checks the returned row's `result_blocked?` — if the logger
  rewrote it to `blocked` via the auto-block list, the controller
  refuses to mint a session and renders the generic flash. Failure
  copy collapsed to `login failed.` per LD-14 (was `invalid email or
  password.`).
- `app/controllers/settings/security_controller.rb` — `show` action
  renders the pane with 2FA status (off in this sub-spec), 24h
  failed/blocked counts, active-block count, and the 10 most-recent
  attempts.
- `app/controllers/settings/security/attempts_controller.rb` —
  paginated (50/page) + filterable index, plus show. Filters:
  `result`, `since`, `ip`, `fingerprint`. JSON branch returns
  `is_success` / `is_failed` / `is_blocked` yes/no Booleans per
  LD-15.

Views

- `app/views/settings/security/show.html.erb` — `pane--standalone`
  primitive per project rule; lead paragraph one-sentence-per-line.
  Lists the recent rows via the component.
- `app/views/settings/security/attempts/index.html.erb` — filter form
  (plain GET, shareable URLs), table of rows, pagination footer.
- `app/views/settings/security/attempts/show.html.erb` — full
  fingerprint hash, full UA, geo, resolved_at when present.
- `app/views/sessions/new.html.erb` — gains the two hidden fields
  (`fp_screen`, `fp_locale`) plus `data-controller="fingerprint-hints"`.
  Lead paragraph reflowed to one-sentence-per-line.

Stimulus

- `app/javascript/controllers/fingerprint_hints_controller.js` — fills
  the hidden fields from `window.screen.*` and
  `Intl.DateTimeFormat().resolvedOptions().timeZone` +
  `navigator.language`. **No** canvas / AudioContext / WebGL / font /
  battery signals collected. Graceful degrade if any read raises.

Components & helpers

- `app/components/login_attempt_row_component.rb` (+ ERB partial) —
  one `<tr>` per attempt. Used in both the index table and the
  security dashboard's recent-activity table; designed for reuse in
  01b's pending-approval notification card.
- `app/helpers/login_attempts_helper.rb` — result / reason / geo /
  CSS-class mappings centralized.

MCP

- `app/mcp/tools/login_attempts_list.rb` — scaffold tool. Filter set:
  result, since, ip, fingerprint; pagination caps at 100/page. Uses
  the existing `app` scope as a placeholder; 01d swaps to the
  dedicated `auth` scope when LD-8's scope catalog wiring lands. Rows
  carry `is_success` / `is_failed` / `is_blocked` yes/no Booleans per
  LD-15.

Routes

- `config/routes.rb` — adds `resource :security` (singular,
  `/settings/security`) and the nested
  `namespace :security do resources :attempts, only: %i[index show] end`.

**Specs added (210 examples)**

Model (65)
: `spec/models/login_attempt_spec.rb`,
  `spec/models/blocked_location_spec.rb`,
  `spec/models/trusted_location_spec.rb`

Services (28)
: `spec/services/auth/fingerprint_composer_spec.rb` (12 examples
  including 4 flaw-class rejection specs for canvas / audio / WebGL /
  fonts kwargs),
  `spec/services/auth/ip_prefix_calculator_spec.rb`,
  `spec/services/auth/geo_enricher_spec.rb` (11 — DB-available,
  DB-unavailable, unknown-IP, over-budget, exception, nil-input,
  defer-flag lifecycle, no-outbound-HTTP),
  `spec/services/auth/attempt_logger_spec.rb` (12 — happy / sad /
  blocked-pair / geo-deferred / rate-limited / malformed-IP /
  password-never-logged flaw)

Job (4)
: `spec/jobs/login_attempt_geo_enrich_job_spec.rb`

Lib (14)
: `spec/lib/pito/auth/ip_prefix_spec.rb`,
  `spec/lib/pito/auth/user_agent_parser_spec.rb`

Component (8)
: `spec/components/login_attempt_row_component_spec.rb`

Helper (12)
: `spec/helpers/login_attempts_helper_spec.rb`

Request (20 across two files)
: `spec/requests/settings/security_spec.rb`,
  `spec/requests/settings/security/attempts_spec.rb`

Sessions request gain (+5 in `spec/requests/sessions_spec.rb`)
: success-row write, wrong-password row, unknown-account row,
  blocked-pair short-circuit, fingerprint composition without
  hints.

MCP (13)
: `spec/mcp/tools/login_attempts_list_spec.rb` — happy / scope-gate /
  filter-set / pagination

Routing (3)
: `spec/routing/settings_security_routing_spec.rb`

Factories: `spec/factories/login_attempts.rb`,
`spec/factories/blocked_locations.rb`,
`spec/factories/trusted_locations.rb`.

**Gates**

- `bundle exec rspec` (touched specs + broad regression across models,
  services, helpers, components, lib, jobs, mcp, routing): 3,782
  examples, 0 failures, 1 pre-existing pending.
- `bundle exec rubocop` on all touched files: 39 files clean.
- `bin/brakeman -q -w2`: 0 warnings, 0 errors.
- Two `bundle exec rspec spec/requests/` failures (`auth_concern_spec`
  intended-URL stash, `settings_spec` 8-vs-9 pane count) are
  pre-existing / Phase-26-in-flight and unrelated to this dispatch.

**Migrations applied**

```
== 20260511120000 CreateLoginAttempts: migrated ==
== 20260511120001 CreateBlockedLocations: migrated ==
== 20260511120002 CreateTrustedLocations: migrated ==
```

Both dev and test DBs migrated. Master will tell user to restart
`bin/dev` after commit lands.

**Manual test plan**

1. Restart `bin/dev` after the commit (migrations require Puma reload).
2. Log out, then visit `http://127.0.0.1:3027/login` in a fresh
   incognito window. Submit the wrong password — see the generic
   `login failed.` flash.
3. Log in correctly.
4. Visit `/settings/security` — expect the 2FA pane to say
   `status: off`, the recent activity pane to show 1 failed + 1
   success row with `location unknown` geo (because no MaxMind DB is
   set) and a 12-char fingerprint hash.
5. Visit `/settings/security/attempts` — confirm filter form, both
   rows visible, both clickable into the detail page.
6. Apply `?result=failed` — only the failed row remains.
7. Visit `/settings/security/attempts.json` — confirm rows carry
   `"is_success"`, `"is_failed"`, `"is_blocked"` as `"yes"` / `"no"`
   strings.
8. From a Claude session with an `app`-scoped token, call
   `login_attempts_list` — JSON rows match the web JSON shape, yes/no
   Booleans included.
9. Open `bin/rails console`: seed a `BlockedLocation` row with the
   fingerprint hash from step 4's success row and the matching IP
   prefix. Re-log-in with the correct password. Expect generic
   `login failed.`; the new attempt row reads `result: blocked,
   reason: blocked_pair`; the `BlockedLocation#attempt_count` ticks
   up.
10. Teardown: `LoginAttempt.delete_all; BlockedLocation.delete_all`
    from the console (full purge UI ships in 01f).

**Deferred to later sub-specs (per umbrella + dispatch)**

- TUI `g s a` keybind for the attempts list — dispatcher said "defer
  TUI for now; web sufficient". 01c / 01g pick it up.
- `auth` MCP scope catalog wiring + `login_attempts_list` scope swap
  from `app` to `auth` — 01d's job per LD-8.
- MaxMind GeoLite2 gem dependency + `bin/setup` download step.
  `Auth::GeoEnricher` gracefully degrades to "deferred" today; the
  gem add lands when the user explicitly opts into GeoIP. The
  `.env.example` line documenting `PITO_GEOIP_DB_PATH` was NOT
  added in this dispatch — flagged as a follow-up so it pairs with
  the gem add.
- `docs/auth.md` "login attempt logging" section — `pito-docs` agent
  owns docs work.

**Open issues**

- Two pre-existing test failures in `spec/requests/`
  (`auth_concern_spec:57`, `settings_spec:216`) are unrelated to this
  dispatch — Phase 24 dropped `:create` from `:channels` without
  updating the auth-concern spec, and Phase 26's in-flight timezone
  pane changes the settings index expected layout.
- The `.env.example` documentation + MaxMind gem add are queued for
  the same follow-up; geo enrichment ships fully functional but
  inert until that follow-up lands.

## 2026-05-11 — 01b — New-location detection + pending sessions

**Dispatch:** `pito-rails` agent against spec
`specs/01b-new-location-detection-and-pending-sessions.md`. Builds on 01a's
attempt log + fingerprint + ip_prefix surfaces. Locked decisions LD-5
(trusted-location definition), LD-6 (pending state machine), LD-15 (yes/no),
LD-17 (friendly URLs) applied directly. Q-G (option 2, expired pending rows
stay) and Q-J (countdown + cancel UX) resolved here.

**What landed**

Database

- `db/migrate/20260511140000_add_state_to_sessions.rb` — `state` integer enum
  + `approval_required_until` datetime on the existing `sessions` table, plus
  two indexes (state, approval_required_until). Default 0 (= `active`) so the
  column is backward-compatible without a backfill.
- `db/migrate/20260511140001_add_session_id_to_login_attempts.rb` — nullable
  FK + index from `login_attempts.session_id` to `sessions`. Lets attempt
  rows link back to the session they spawned (trusted success, pending,
  expired-pending sweep).

Both migrations applied against dev DB AND test DB.
`bin/rails db:migrate:status` confirms both as `up`.

Models

- `app/models/session.rb` — gains `enum :state` (active / pending_approval /
  expired / revoked, prefix `:state`), `PENDING_APPROVAL_TTL = 10.minutes`,
  scopes `active_sessions` / `pending` / `expired_pending` /
  `pending_within_window`, class method `.create_pending!`, instance methods
  `pending_within_window?` / `expired_pending?` / `expire_if_overdue!` /
  `transition_to_active!`. `revoke!` now also flips state to `:revoked`.
- `app/models/trusted_location.rb` — gains `.touch_for(user:,
  fingerprint_hash:, ip_prefix:)` upsert. Atomic against the unique index;
  `update_only: %i[last_seen_at]` (Rails auto-bumps `updated_at`).
- `app/models/user.rb` — gains `has_many :trusted_locations` /
  `has_many :login_attempts`, plus `#trusted_location?(fingerprint:,
  ip_prefix:)` and `#has_pending_session?` helpers used by the controllers
  and the security dashboard.
- `app/models/login_attempt.rb` — gains `belongs_to :session, optional:
  true` so attempts can link to the session they spawned.

Services

- `app/services/auth/new_location_detector.rb` — pure decision. Given a
  user + fingerprint + ip_prefix triple, returns `:trusted` /
  `:new_location` / `:blocked_pair` (with `:blocked_pair` precedence over
  `:trusted` — defense-in-depth against a regression that re-enables an
  operator-blocked device).
- `app/services/auth/session_pending_approver.rb` — mints a pending-approval
  Session row + an attempt row with `reason: new_location_pending`. Enforces
  `MAX_ACTIVE_PENDING = 3` anti-spam cap; raises `TooManyPending` past that,
  which the controller surfaces as generic "Login failed." (LD-14).
- `app/services/auth/session_activator.rb` — sole minter of `:active`
  sessions. Two callers: trusted-location branch (fresh mint) and 01c/01e
  approve/2FA-success branch (`existing:` pending row → flipped to active,
  token rotated per LD-12). Stamps the trusted-location upsert + writes the
  attempt row in one transaction. Raises on terminal-state activations.
- `app/services/auth/pending_session_expirer.rb` — sweeper. Walks
  `Session.expired_pending`, flips state to `:expired`, writes a
  `pending_expired` attempt row per transition. One-bad-row-doesn't-stop-
  the-sweep behaviour via per-row `rescue StandardError`.
- `app/services/auth/attempt_logger.rb` — gains optional `session:` kwarg so
  every write paths can link the attempt to its session.

Jobs

- `app/jobs/session_pending_approval_sweeper_job.rb` — Sidekiq cron entry.
  Calls `Auth::PendingSessionExpirer.call`, logs the transitioned count.
- `config/sidekiq_cron.yml` — new `pending_session_approval_sweeper` entry
  scheduled every minute (`* * * * *`).

Controllers

- `app/controllers/sessions_controller.rb` — refactored post-password-check.
  After authenticate, asks `Auth::NewLocationDetector` and branches:
  trusted → `Auth::SessionActivator` mints + sets cookie + redirects;
  new_location → stashes a signed pre-auth marker (`PRE_AUTH_COOKIE`,
  10-minute TTL) and redirects to `/login/challenge`, NO session minted;
  blocked_pair → writes a `blocked` row and renders generic failure.
- `app/controllers/login/challenges_controller.rb` — new. `show` renders
  the two-choice surface; `create` accepts `challenge_path: "approval" |
  "totp"`. Approval path calls `Auth::SessionPendingApprover` + redirects
  to `/login/pending`. TOTP path redirects to the `/login/totp` placeholder
  route (01e fills it). `<unknown>` returns 422.
- `app/controllers/login/pendings_controller.rb` — new. `show` renders the
  countdown + attempt detail card + `[cancel & log out]` form. `destroy`
  revokes the pending row and clears the marker.
- `app/controllers/settings/security_controller.rb` — adds
  `@trusted_locations_count` and `@pending_sessions_count` for the
  dashboard. View renders them as "trusted locations: N, pending: M".

Views

- `app/views/login/challenges/show.html.erb` — choice surface, renders the
  `LoginChallengeChoiceComponent`.
- `app/views/login/pendings/show.html.erb` — countdown pane wired to the
  `pending-countdown` Stimulus controller; attempt-detail partial; cancel
  form. No JS `confirm` (HTML-escaped ampersand keeps the bracketed label
  valid).
- `app/views/login/_attempt_detail.html.erb` — partial shared with 01c's
  notification card.
- `app/views/settings/security/show.html.erb` — gains the two counters.

Routes

- `config/routes.rb` — `/login/challenge` (GET / POST), `/login/pending`
  (GET / DELETE), `/login/totp` (placeholder GET redirect to `/login`).

Stimulus

- `app/javascript/controllers/pending_countdown_controller.js` — ticks once
  per second from `data-pending-countdown-deadline-value` (ISO 8601),
  renders `MM:SS`, reloads the page when the deadline elapses so the
  server-side expiry path takes over.

Components

- `app/components/login_challenge_choice_component.rb` (+ ERB) — two
  bracketed-link choices (`[enter 2FA code]`, `[ask for approval]`).

MCP

- `app/mcp/tools/login_attempts_pending.rb` — read scaffold. Returns
  attempts whose linked session is in `:pending_approval` AND
  `approval_required_until > now`. Boundary booleans (`is_pending`,
  `is_expired`, `has_session`) serialize as yes/no per LD-15.
  Currently gated on `app` scope; 01d swaps to dedicated `auth` scope.

Factories

- `spec/factories/sessions.rb` — adds `:pending`, `:expired_pending`,
  `:expired`, `:revoked_state` traits.

**Specs added (113 new examples)**

Models (+27)
: `spec/models/session_spec.rb` (state enum + all transitions + scopes),
  `spec/models/trusted_location_spec.rb` (`.touch_for` upsert),
  `spec/models/user_spec.rb` (`#trusted_location?` /
  `#has_pending_session?`).

Services (+30)
: `spec/services/auth/new_location_detector_spec.rb` (8),
  `spec/services/auth/session_pending_approver_spec.rb` (8 — incl. spam
  cap + clock-skew),
  `spec/services/auth/session_activator_spec.rb` (10 — fresh + existing
  + terminal-row raises + token rotation),
  `spec/services/auth/pending_session_expirer_spec.rb` (8 — incl. bulk
  100-row sweep + bad-row tolerance).

Job (+3)
: `spec/jobs/session_pending_approval_sweeper_job_spec.rb` — delegates +
  cron schedule asserted by reading `sidekiq_cron.yml`.

Request (+24)
: `spec/requests/login/challenges_spec.rb` (9 — happy + sad + GET / POST
  branches),
  `spec/requests/login/pendings_spec.rb` (6 — show + destroy + expired
  + no-marker),
  `spec/requests/sessions_spec.rb` (+3 — trusted dispatch / new-location
  dispatch / blocked dispatch under Phase 25 — 01b),
  `spec/requests/settings/security_spec.rb` (+1 — trusted + pending
  counters surface).

Component (+4)
: `spec/components/login_challenge_choice_component_spec.rb` — bracketed
  labels, no inner whitespace, two POST forms hit `/login/challenge`.

MCP (+7)
: `spec/mcp/tools/login_attempts_pending_spec.rb` — happy (in-window only,
  excludes expired), boundary (yes/no booleans), row shape, scope gate,
  pagination.

Routing (+7)
: `spec/routing/login_challenges_routing_spec.rb` — `/login/challenge`,
  `/login/pending`, `/login/totp`, named-route helpers.

**Migrations applied**

```
== 20260511140000 AddStateToSessions: migrated ==
== 20260511140001 AddSessionIdToLoginAttempts: migrated ==
```

`bin/rails db:migrate:status` confirms both as `up` on dev and test DBs.

**Gates**

- `bundle exec rspec` on touched + adjacent specs: 288 examples, 0 failures.
- Broad regression (`spec/models spec/services spec/jobs spec/components
  spec/mcp spec/routing spec/lib spec/helpers`): 4,039 examples, 0 failures,
  1 pre-existing pending.
- Full `spec/requests` sweep: 1,777 examples, 1 pre-existing failure
  (`auth_concern_spec` intended-URL stash — was already documented in 01a
  log; unrelated to this dispatch).
- `bundle exec rubocop` on all touched files: 570 files clean.
- `bin/brakeman -q -w2`: no new warnings.

**Manual test plan**

1. Restart `bin/dev` so the new migrations take effect.
2. Log in successfully from your current browser. Visit
   `/settings/security` — note "trusted locations: 1, pending: 0".
3. Log out. Switch browser profile (Chrome → Firefox, or use a clean
   incognito with a different UA) so the fingerprint changes. Visit
   `/login` and submit the correct password.
4. Expect redirect to `/login/challenge`. Two bracketed-link choices
   visible: `[enter 2FA code]` and `[ask for approval]`.
5. Click `[ask for approval]`. Expect redirect to `/login/pending` with
   a 10:00 countdown and the attempt detail card (browser / OS / IP /
   fingerprint short).
6. From your trusted browser, visit `/settings/security` → "pending: 1".
7. Wait ~ 11 minutes (or open a Rails console and run
   `Auth::PendingSessionExpirer.call`). Refresh `/login/pending` →
   redirects to `/login` with generic "login failed." copy.
8. Confirm in the console:
   `LoginAttempt.where(reason: :pending_expired).count == 1`.
9. Sidekiq dashboard at `/sidekiq/cron`: confirm
   `pending_session_approval_sweeper` is scheduled at `* * * * *`.
10. Test the cancel flow: repeat 3–5 to land on `/login/pending`. Click
    `[cancel & log out]`. Expect redirect to `/login`; the pending
    Session row should be in `state: revoked` (verify via console).
11. Teardown: `Session.pending.destroy_all` from console.

**Deferred to later sub-specs**

- Notification creation on pending-approval row (01c). Controller TODO
  stub returns the pending row; 01c wires
  `Notifications::Pipeline.deliver(:login_pending_approval, attempt:)`.
- TOTP form at `/login/totp` (01e). Placeholder redirects to `/login`
  for now so the `[enter 2FA code]` link doesn't 404.
- TUI `g s p` pending-list view (01c picks it up alongside the in-TUI
  approval overlay).
- MCP scope swap from `app` → `auth` (01d's job per LD-8 + scope
  catalog update in `docs/mcp.md`).

**Open issues**

- The `auth_concern_spec` intended-URL stash test is still red
  (pre-existing — recorded in 01a log).

## 2026-05-11 — 01c — Notifications integration (Rails web side)

**Dispatch:** `pito-rails` agent against spec
`specs/01c-notifications-integration.md`. Wires the pending-approval
notification pipeline + the approve / block action-screen controllers
into the existing 01b pending-session flow. TUI overlay and MCP
approve/block tools are explicitly out of scope for this dispatch
(TUI belongs to `pito-rust`, MCP tools land in 01d). Locked decisions
LD-7 (notification kind / severity), LD-12 (token rotation),
LD-13 (audit log), LD-15 (yes/no boundary), LD-16 (no JS confirm),
LD-17 (friendly URLs) applied directly. Q-L (one notification per
pending row) resolved here.

**What landed**

Database

- `db/migrate/20260511160500_create_auth_audit_logs.rb` — LD-13
  schema. `acting_user_id` (FK to users, non-null), `source_surface`
  integer enum (web=0 / tui=1 / mcp=2), `action` integer enum (full
  LD-13 vocabulary: approve / block / unblock / purge / totp_enroll /
  totp_disable / backup_code_regenerate), `target_type` + `target_id`
  polymorphic pointer (NOT a `belongs_to :target, polymorphic: true`
  so the audit row never follows the target into deletion),
  `metadata` jsonb. Indexes on (target_type, target_id), action,
  source_surface, created_at. Pre-declares every LD-13 action so
  01d–01f land without further migration.

Migrations applied against dev DB AND test DB.

Models

- `app/models/auth_audit_log.rb` — `AuthAuditLog`. `belongs_to
  :acting_user` (User, required). Two integer enums (source_surface,
  action) with defensive `attribute :col, :integer` locks against
  Rails 8.1 bootsnap autoload races. Scopes `.recent`,
  `.for_target(type, id)`, `.for_acting_user(user)`, `.since(ts)`.
  No `belongs_to :target, polymorphic: true` — audit rows are
  pointer-only by design.
- `app/models/notification.rb` — gains `login_pending_approval: 11`
  on the `kind` enum. Severity stays `urgent` per LD-7.

Services

- `app/services/auth/audit_logger.rb` — single entry point for every
  privileged auth action (approve / block / unblock / purge / TOTP
  enroll / disable / backup-code regenerate). Strict enum guard on
  `source_surface` / `action` (typo surfaces loudly). Accepts either
  `target:` (AR record) OR explicit `target_type:` + `target_id:`.
  Stringifies metadata keys before persisting. Does NOT open an inner
  transaction — caller wraps the audit + the domain mutation in one
  transaction so a domain rollback also drops the audit row.
- `app/services/auth/login_attempt_approver.rb` — `[yeah, it's me]`
  service. Pessimistic lock on the Session row (`Session.lock.find_by`)
  serializes concurrent approve + block. Delegates the active-session
  mint to `Auth::SessionActivator` (existing-row branch — token
  rotates per LD-12), upserts trusted location, resolves the linked
  notification (marks read), audit-logs. Exception contract:
  `PendingExpired` / `AlreadyResolved` / `ArgumentError`. Defense-in-
  depth: ONLY trusts caller-supplied `acting_user:` kwarg, never reads
  request params.
- `app/services/auth/login_attempt_blocker.rb` — `[block the intruder]`
  mirror. Same pessimistic lock + transaction posture. Upserts the
  `BlockedLocation` row (idempotent on the unique partial index),
  revokes the pending session, stamps a fresh `LoginAttempt` row
  with `reason: :blocked_from_<source>` (bypasses
  `Auth::AttemptLogger` so the block-list short-circuit doesn't
  relabel the row as `:blocked_pair`), resolves the notification,
  audit-logs. `reason:` kwarg lets the operator stamp a free-form
  text on the BlockedLocation row.
- `app/services/notification_source/login_pending_approval.rb` —
  source helper. One Notification per pending attempt (dedup key
  `"login-pending-#{login_attempt_id}"`). Stamps the
  `login_attempts.notification_id` FK on the source row via
  `update_columns` (bypasses the model's `before_update` so we don't
  trip `resolved_at`). Severity `:urgent` per LD-7.
- `app/services/notification_formatter/templates/login_pending_approval.rb` —
  renders the in-app body with the two bracketed-link actions
  (`[yeah, it's me](/login/approvals/:id)` /
  `[block the intruder](/login/blocks/:id)`). Graceful placeholders
  for missing geo / UA / fingerprint. Registered in the formatter
  templates `REGISTRY`. Emoji `🔑` added to `EVENT_TYPE_EMOJI` so the
  notification glyph renders in the inbox.
- `app/services/auth/session_pending_approver.rb` — gains the
  notification dispatch immediately after the pending row + attempt
  row commit. Dispatch is deliberately OUTSIDE the transaction so a
  notification-helper failure does NOT roll back the pending row
  (the holding page still works without the notification). Failures
  are logged via `Rails.logger.warn`.

Controllers

- `app/controllers/login/approvals_controller.rb` — two-action
  controller (`show` + `create`). GET renders the action-screen with
  attempt detail. POST consumes the `confirm=yes` form (LD-15) and
  calls `Auth::LoginAttemptApprover.call(source: :web)`. Yes/no
  boundary, friendly URL `/login/approvals/:id`. NO JS confirm
  anywhere (LD-16).
- `app/controllers/login/blocks_controller.rb` — mirror for block.
  Submit button styled destructive (red) via
  `shared/_action_screen` `destructive: true`. POST optionally
  carries a free-form `reason` param stamped on the
  `BlockedLocation` row.

Views

- `app/views/login/approvals/show.html.erb` — action-screen
  confirmation. Renders `login/_attempt_detail` (shared with 01b's
  `/login/pending` holding page so the same card tells the same
  story across surfaces). Submit label `[yeah, it's me]`.
- `app/views/login/blocks/show.html.erb` — mirror. Submit label
  `[block the intruder]`, `destructive: true`.

Routes

- `config/routes.rb` — adds four routes:
  - `GET  /login/approvals/:id` → `login/approvals#show`
    (`login_approval_path`)
  - `POST /login/approvals/:id` → `login/approvals#create`
  - `GET  /login/blocks/:id`    → `login/blocks#show`
    (`login_block_path`)
  - `POST /login/blocks/:id`    → `login/blocks#create`
  All four constrain `:id` to digits.

Factories

- `spec/factories/auth_audit_logs.rb` — basic factory with sensible
  defaults (`acting_user`, `source_surface: :web`, `action: :approve`,
  `target_type: "LoginAttempt"`, sequenced `target_id`).

**Specs added (138 new examples)**

Model (+30 across two files)
: `spec/models/auth_audit_log_spec.rb` (28 — validations, enum
  acceptance/rejection, associations, scopes, jsonb round-trip),
  `spec/models/notification_spec.rb` (+2 — kind acceptance,
  persistence with login_pending_approval).

Service (+86 across five files)
: `spec/services/auth/audit_logger_spec.rb` (13 — happy / sad /
  transactional-posture),
  `spec/services/auth/login_attempt_approver_spec.rb` (16 — happy +
  sad + transactional-integrity + defense-in-depth contract check),
  `spec/services/auth/login_attempt_blocker_spec.rb` (21 — happy +
  idempotency + sad + transactional-integrity),
  `spec/services/notification_source/login_pending_approval_spec.rb`
  (13 — happy / dedupe / sad / template integration),
  `spec/services/notification_formatter/templates/login_pending_approval_spec.rb`
  (12 — title / body / url / registry wiring),
  `spec/services/auth/session_pending_approver_spec.rb` (+4 —
  notification dispatch happy + failure isolation).

Request (+27 across two files)
: `spec/requests/login/approvals_spec.rb` (15 — GET show /
  POST create / unauthenticated / expired / already-resolved),
  `spec/requests/login/blocks_spec.rb` (12 — mirror including
  BlockedLocation persistence + reason-text stamping).

Routing (+8)
: `spec/routing/login_approvals_routing_spec.rb` — both controllers
  GET/POST, non-numeric-id rejection, named-helper paths.

**Migrations applied**

```
== 20260511160500 CreateAuthAuditLogs: migrated ==
```

Both dev and test DBs migrated. `bin/rails db:migrate:status`
confirms `up`.

**Gates**

- `bundle exec rspec` for the dispatched specs (models, services,
  notification source, template, requests, routing): 350 examples,
  0 failures.
- Broad regression — `spec/services spec/models`: 2,866 examples,
  0 failures, 1 pre-existing pending.
- `spec/components spec/helpers`: 660 examples, 0 failures.
- `bundle exec rubocop` on all touched files (14 source + 12 spec):
  no offenses.
- `bin/brakeman -q -w2`: 0 security warnings (one parse error in
  another agent's untracked component file is unrelated).

**Manual test plan**

1. Restart `bin/dev` so the new migration + routes take effect.
2. Log in from your trusted browser, leave it open.
3. In a fresh incognito (different UA → different fingerprint), visit
   `/login` and submit the correct password.
4. On the challenge page, click `[ask for approval]`. Browser B lands
   on the `/login/pending` holding page with the 10-minute countdown.
5. In the trusted browser, expect the unread notifications badge to
   tick. Open `/notifications` — the new urgent row reads
   `new-location login: <your email>`. Click it.
6. On the detail page (or directly from the inbox body), click
   `[yeah, it's me]`. The action-screen confirmation renders. Click
   `[yeah, it's me]` again. Redirect to `/notifications` with a
   `approved.` flash.
7. In browser B, refresh `/login/pending` — server-side state has
   flipped to `:active`, so the next request from B with the rotated
   cookie should resolve as authenticated (the explicit UX flip lives
   in 01b's SSE / poll mechanism).
8. Verify in `bin/rails console`:
   - `AuthAuditLog.recent.first.action == "approve"` and
     `source_surface == "web"`.
   - The linked notification's `in_app_read_at` is non-nil.
9. Teardown / repeat for block: open another fresh browser, submit
   correct password, click `[ask for approval]`. In trusted browser,
   open the new urgent notification → click `[block the intruder]` →
   action-screen → confirm. Expect:
   - `Session.pending.count == 0` (the pending row flipped to
     `:revoked`).
   - `BlockedLocation.active.count == 1` with the matching fingerprint.
   - `AuthAuditLog.recent.first.action == "block"` and
     `source_surface == "web"`.
10. Confirm `/login/approvals/<expired-id>` and
    `/login/blocks/<expired-id>` redirect with the expired-flash copy
    after the 10-minute window has elapsed.

**Deferred to later sub-specs / agents**

- TUI overlay (`extras/cli/src/notifications/login_pending.rs`,
  `overlay.rs`, `api/login_attempts.rs`) — `pito-rust` agent's
  lane. Locked decisions reach the TUI through the API + the
  shared attempt/notification serializers; no behavioural change
  to this Rails dispatch.
- MCP `login_attempt_approve` / `login_attempt_block` tool
  scaffolding — 01d's job per LD-8 scope catalog wiring.
- `notifications.login_attempt_id` FK (mentioned in the spec) was
  intentionally skipped: the existing `LoginAttempt#notification_id`
  + `belongs_to :notification` covers the reverse lookup. If a future
  sub-spec needs a notification-side FK for query convenience, a
  dedicated migration will land then.
- TUI status-line `pending approval` prompt on non-notification
  surfaces.

**Open issues**

- The pre-existing `auth_concern_spec:57` failure carries forward
  (already noted in 01a / 01b).
- Other agents' in-flight work touches `/settings/security/blocks`,
  `/settings/security/attempts/purge`, `/settings/security/blocks/purge`,
  and `/settings/webhooks/help` — those are outside this dispatch's
  scope. Their failing routing / request specs (~33 examples) are
  unrelated to 01c.
