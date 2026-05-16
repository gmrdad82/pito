# User auth refactor — username login + mandatory 2FA

## Goal

pito's browser login is email + password today (Phase 8). The operator does not
want to run SMTP or any email service, which makes email a dead weight: it backs
no notifications and gates no recovery flow, yet it carries account-existence
risk and forces an email-format contract. This unit drops `email` entirely and
moves login to `username` + `password`. With email gone there can be no
email-based password recovery, so two things change in lockstep: 2FA (TOTP, RFC
6238 — already built in Phase 25 as an optional second factor) becomes
**mandatory from first login**, and password recovery is rebuilt as a
**reset-via-2FA** flow that needs no email. After a fresh seed the seeded owner
has no TOTP configured, so their very first login is gated straight into TOTP
setup before any other page is reachable. The unit also trims `db/seeds.rb` to
stop seeding sample videos, channels, projects, and games.

This matters for the Phase 29 polish sweep because auth is the entry surface for
every other screen; a half-built recovery story and an email field nobody uses
are exactly the kind of incoherence the sweep exists to remove. It is a
security-sensitive change — a `pito-security` `/security-review` pass runs after
implementation, before the master agent commits.

The users of this surface: the single seeded operator today (single-install,
multi-user per ADR 0003), and any future manually-inserted user — every one of
them logs in with a username and is forced through TOTP setup on first login.

## Inventory (current state — what implementation builds on)

This section is the truth the spec was written against; the implementation agent
should treat it as the baseline, not re-discover it.

### `User` model + `users` table

`app/models/user.rb`, `users` table (`db/schema.rb`):

- Columns: `id`, `email` (citext, NOT NULL, unique index
  `index_users_on_email`), `password_digest` (NOT NULL), `last_digest_run_at`,
  `preferred_games_display_mode`, `time_zone`, `totp_disabled_at`,
  `totp_enabled_at`, `totp_last_used_step`, `totp_seed_encrypted` (text,
  AR-encrypted), `created_at`, `updated_at`.
- `has_secure_password`. Password validation `length: { minimum: 8 }` when
  present.
- Email: `before_validation :strip_email_whitespace`; validations are presence,
  `length <= 254`, `format: URI::MailTo::EMAIL_REGEXP`,
  `uniqueness case_sensitive: false`. `EMAIL_MAX_LENGTH = 254`.
- Associations: `totp_backup_codes` (dependent: destroy), `sessions` (dependent:
  destroy), `youtube_connections` (dependent: destroy), `trusted_locations`
  (dependent: destroy), `login_attempts` (dependent: nullify). Concerns:
  `Timezoned`.
- TOTP helpers already exist: `totp_enabled?`
  (`totp_seed_encrypted.present? && totp_disabled_at.nil?`), `totp_uri(issuer:)`
  — both currently call `provisioning_uri(email)`.
- `totp_enabled_at` is the "confirmed enrollment" stamp; it is set by
  `Settings::Security::TotpsController#update` only after a fresh 6-digit code
  verifies.

### Login / session flow

- `SessionsController` (`app/controllers/sessions_controller.rb`): `new` /
  `create` / `destroy`. `create` reads `params[:email]`, does
  `User.find_by(email:)`, `bcrypt_dummy_compare` on the unknown branch,
  `user.authenticate(password)`. Then: **if `user.totp_enabled?` → write
  pre-auth marker, redirect to `/login/totp`** (the TOTP gate runs on EVERY
  login, trusted or new, today). Else `Auth::NewLocationDetector.call` →
  `:trusted` / `:new_location` / `:blocked_pair`.
- `Sessions::AuthConcern` (`app/controllers/concerns/sessions/auth_concern.rb`):
  `before_action :authenticate_session!`, `allow_anonymous` class macro,
  `around_action :reset_current_after_request`, intended-URL stash. Included by
  `ApplicationController`.
- `Login::ChallengesController` — new-location challenge page
  (`[enter 2FA code]` / `[ask for approval]`).
- `Login::TotpChallengesController` — `/login/totp` GET/POST; consumes the
  pre-auth marker + nonce, verifies via `Auth::TotpVerifier` /
  `Auth::BackupCodeConsumer`, activates the session via
  `Auth::SessionActivator`.
- `Login::PendingsController`, `Login::ApprovalsController`,
  `Login::BlocksController` — pending-session holding page + approve / block.
- New-location-approval (Phase 25): `Auth::NewLocationDetector` consults
  `TrustedLocation` + `BlockedLocation`; outcomes are trusted / new_location /
  blocked_pair. Pre-auth marker is a signed cookie
  (`SessionsController::PRE_AUTH_COOKIE`) + a Rails.cache nonce.
- TOTP infrastructure (Phase 25, already built):
  `Settings::Security::TotpsController` (enroll: `new` / `create` / `show` /
  `update` confirm / `destroy_screen` / `destroy_confirmed`),
  `Settings::Security::TotpBackupCodesController` (regenerate),
  `Login::TotpChallengesController` (login challenge), `RecentTotpVerification`
  concern (re-prompt on sensitive writes). Services: `Auth::TotpEnroller`,
  `Auth::TotpVerifier` (returns `:ok` / `:invalid`, replay watermark on
  `totp_last_used_step`), `Auth::BackupCodeConsumer`, `Auth::TotpDisabler`,
  `Auth::BackupCodeRegenerator`. Routes under `/settings/security/totp*`.
- `Settings::UserController` — account self-edit (email / password change,
  current-password gated, `RecentTotpVerification` mixed in).

### Forgot-password / password-reset surface

**Confirmed: none exists.** There is no forgot-password controller, route, or
view. `app/views/sessions/new.html.erb` carries copy that says recovery is "not
yet available — reset via `bin/rails credentials:edit` for now."
`Settings::UserController` and the Phase 12 routes comment both explicitly say
"no password-recovery flow (deferred)." This unit builds the recovery surface
for the first time, as reset-via-2FA.

### `db/seeds.rb`

`db/seeds.rb` currently seeds: AppSettings (`max_panes`, `pane_title_length`,
`monetization_enabled`, Voyage key bootstrap); the owner User from
`Rails.application.credentials.owner.{email, password}`; the dev API token; six
Platform reference rows; **and a project-workspace sample** — one Collection
(`currently playing`), one Game (`Demo Game`, with cover art), one Project
(`Demo Project` with 2 ProjectReferences), one Note, one Timeline; **plus** a
second `now playing` Collection with two Games (`Pragmata`,
`Red Dead Redemption 2`). Channels and videos are already NOT seeded (removed
2026-05-10). The project / game / note / timeline / collection blocks are lines
~118-245.

### `:owner` credentials block

`Rails.application.credentials.owner` is `{ email, password }` per
`docs/setup.md`. Read by `db/seeds.rb` via
`Rails.application.credentials.dig (:owner)`. Per-environment (development +
test edited separately).

## Decisions baked into this spec

The genuinely-blocking forks in earlier drafts have all been resolved by the
user (see "Resolved decisions" below). The remaining items here are the
architect's defaults on low-stakes points; "Open questions" lists what is still
deferrable.

1. **Username format.** `username` is citext, NOT NULL, unique. Validation:
   `format: /\A[a-z0-9_]+(?:[.-][a-z0-9_]+)*\z/i` (alphanumerics + underscore,
   with single internal dot or hyphen separators — no leading / trailing /
   doubled separators), `length: { in: 3..32 }`, presence,
   `uniqueness case_sensitive: false`. `before_validation` strips whitespace and
   downcases (citext makes the column case-insensitive on lookup; downcasing on
   write keeps the stored form canonical). This is a defensible default; the
   user may want a different rule — flagged in Open questions as low-stakes.
2. **Straight column swap, destructive-and-reseed.** No production data exists
   (confirmed by the user and consistent with `docs/setup.md`'s
   destructive-and-reseed posture). The migration drops `email` and its index
   and adds `username` + its unique index in one migration. No data backfill, no
   dual-write window. The canonical recovery path stays
   `bin/rails db:drop db:create db:migrate db:seed`.
3. **"2FA configured" = `totp_enabled_at` present AND `totp_disabled_at` nil** —
   i.e. the existing `User#totp_enabled?` predicate. Backup-code generation is
   already part of `Auth::TotpEnroller` (10 codes minted at `create` time, shown
   once on the `show` one-shot screen). The gate does NOT add a separate "backup
   codes acknowledged" checkbox — confirming the 6-digit code on the enrollment
   `show` screen, which is where the codes are displayed, is the single
   completion signal. Rationale: the codes are already on screen at the moment
   of confirmation; a second acknowledgement step adds friction without adding a
   real guarantee.
4. **Check ordering** (see "Check ordering" section below): password →
   new-location / blocked-pair classification → TOTP login challenge → **2FA
   mandatory-setup gate** → app. The mandatory-setup gate is a post-session
   `before_action`, distinct from the pre-session `/login/totp` challenge.

### Resolved decisions (user-confirmed — no longer open)

These four were "Open questions" in the prior draft. The user has resolved them;
they are now definite spec content and drive the file-by-file table, the
migration outline, and the regression spec list.

R1. **Reset-via-2FA accepts a backup code as well as a live TOTP code.**
`POST /password/reset` succeeds on either
`Auth::TotpVerifier.call(user:,     code:) == :ok` OR
`Auth::BackupCodeConsumer.call(user:, code:) == :ok`. A user who lost their
authenticator device but still has backup codes must have a path; backup codes
already exist for exactly this fallback. The backup code is consumed
(single-use, `used_at` stamped under a row lock — `Auth::BackupCodeConsumer`'s
existing behavior) so it cannot be reused. Consequence: a user who loses BOTH
the device and every backup code is locked out of the browser surface — covered
by R2's rake task and the documented console fallback. R2. **Operator-only
lockout escape hatch: a `bin/rails` rake task.** In addition to the documented
Rails-console snippet (kept as the bare-bones backup), this unit ships
`bin/rails pito:user:reset_totp[username]` — an operator-only task that clears a
user's TOTP enrollment so they re-enroll on next login. See "TOTP reset rake
task" for the exact behavior. This is in the file-by-file table (new task file +
its spec). R3. **The mandatory-2FA gate applies to browser sessions only.** API
tokens and MCP bearer credentials are NOT gated by the mandatory-2FA
`before_action` — they authenticate a bearer credential, not a
user-with-a-browser, and a token cannot "set up TOTP". A token is minted by an
already-authenticated browser user; that browser user is themselves gated, so
the token-minting path is already protected. `Api::AuthConcern` and
`Mcp::RackApp` are untouched by this unit. R4. **First-login bootstrap: a
no-TOTP fresh-seed user skips new-location approval; an active session is
minted; the `LoginAttempt.reason` is a new `first_login_totp_setup_required`
enum value.** On a fresh seed the owner has no TOTP and no `TrustedLocation`
rows. `SessionsController#create`, when the user is **not** `totp_configured?`,
mints an **active** session directly (bypassing the pending-approval branch —
approval is meaningless without an established account) so the post-session
`require_totp_configured!` gate takes over and forces enrollment. That path
records `LoginAttempt.reason = first_login_totp_setup_required` — a new enum
value added for forensic clarity (see "Migration outline" — the enum extension).

## TOTP reset rake task

`bin/rails pito:user:reset_totp[username]` — operator-only, run from a shell on
the box. It is the friendly counterpart to the `docs/auth.md` §1a console
snippet (which stays documented as the no-rake-task fallback).

- **File:** `lib/tasks/user.rake` — a
  `namespace :pito { namespace :user { ... } }` block declaring
  `task :reset_totp, [:username] => :environment`. If a `lib/tasks/pito*.rake`
  or similar already aggregates `pito:` tasks, the implementer may add the task
  there instead for consistency — grep `lib/tasks/` first; either location is
  fine, name it consistently.
- **What it does**, given a `username` argument:
  1. `user = User.find_by(username: username&.strip&.downcase)`. If nil, print a
     clear `user not found: <username>` line to `$stderr` and `exit 1` — no
     stack trace, no oracle concern (this is operator-only, run on the box).
  2. Clear the TOTP enrollment so `totp_enabled?` / `totp_configured?` returns
     false: in a transaction,
     `user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil, totp_disabled_at: nil, totp_last_used_step: nil)`.
     Clearing both stamps (not setting `totp_disabled_at`) returns the user to
     the same "never enrolled" state a fresh seed produces, so the mandatory-2FA
     gate forces a clean re-enrollment on next login rather than leaving them in
     a "disabled" state.
  3. Destroy the user's `totp_backup_codes` (the old codes are meaningless once
     the seed is gone) — `user.totp_backup_codes.delete_all`.
  4. **Revoke the user's sessions.** Destroy all of the user's `Session` rows
     (active and pending) — `user.sessions.destroy_all`. A TOTP reset is a
     credential-state change; any live session must not survive it. The user
     re-logs in fresh and is immediately gated into re-enrollment.
  5. Print an operator-facing confirmation to `$stdout`:
     `TOTP reset for <username> — sessions revoked, backup codes cleared. They will be forced through TOTP setup on next login.`
- **Idempotent.** Running it on a user who already has no TOTP configured is a
  no-op-equivalent (the `update!` writes nils over nils, `delete_all` /
  `destroy_all` on empty relations are harmless) and still prints the
  confirmation. The implementer should not special-case "already clear" — just
  run the same clearing path.
- **Not gated by anything.** It is a shell task; there is no `Current.user`, no
  2FA challenge. Operator possession of shell access on the box is the
  authorization boundary, exactly like the console snippet.

## Files touched

Rails app — models / migrations:

- `db/migrate/<ts>_swap_user_email_for_username.rb` — new migration. Drops
  `email` column + `index_users_on_email`; adds `username` (citext, null: false)
  - unique index `index_users_on_username`. See "Migration outline".
- `db/migrate/<ts>_add_first_login_totp_setup_required_to_login_attempt_reason.rb`
  — new migration **iff `LoginAttempt.reason` is a database-backed enum**
  (Postgres enum type or an integer column with a model-side mapping that needs
  no migration). The implementer checks `LoginAttempt`'s `reason` definition: if
  it is a Rails `enum` over an integer column, adding the
  `first_login_totp_setup_required` value is a **model-only edit, no
  migration**; if it is a Postgres enum type, this migration `ADD VALUE`s it.
  See "Migration outline" — the enum extension.
- `app/models/user.rb` — remove `email` validations, `EMAIL_MAX_LENGTH`,
  `strip_email_whitespace`; add `username` validations + a `normalize_username`
  `before_validation`. Add `totp_configured?` (alias / thin wrapper over
  `totp_enabled?` for gate-call-site readability — or reuse `totp_enabled?`
  directly; implementer's call, name it consistently). Update `totp_uri` to call
  `provisioning_uri(username)`.
- `app/models/login_attempt.rb` — add the `first_login_totp_setup_required`
  value to the `reason` enum (per R4). If the enum is integer-backed this is the
  only change for the new reason; if it is a Postgres enum type, pair it with
  the migration above.

Rails app — controllers / concerns:

- `app/controllers/sessions_controller.rb` — `create` reads `params[:username]`,
  `User.find_by(username:)`; rename internal `email:` plumbing to `username:`
  (`log_attempt`, `audit`, `backoff_email_key` → `backoff_username_key`,
  `reset_backoff_for_email` → `reset_backoff_for_username`, `@email` →
  `@username`, `bcrypt_dummy_compare` unchanged). The audit-log payload keys
  `email_attempted` become `username_attempted`. **First-login bootstrap (R4):**
  when the authenticated user is NOT `totp_configured?`, the new-location branch
  mints an **active** session directly (no pending-approval detour) and records
  `LoginAttempt.reason = first_login_totp_setup_required`. See "First-login
  bootstrap".
- `app/controllers/concerns/sessions/auth_concern.rb` — add the mandatory-2FA
  `before_action :require_totp_configured!` AFTER `authenticate_session!`. The
  hook redirects an authenticated-but-TOTP-unconfigured user to the TOTP setup
  flow unless the request is on the allowlist (see "2FA mandatory gate"). Add a
  class-level allowlist macro OR a hardcoded path/route allowlist constant
  inside the concern. **Browser-only (R3):** this concern is included by
  `ApplicationController`; `Api::AuthConcern` / `Mcp::RackApp` do not include it
  and are not touched.
- `app/controllers/login/totp_challenges_controller.rb` — `email:` → `username:`
  in the `log_failed_attempt` call and the backoff-reset key; audit payloads
  unchanged in shape but no email reference.
- `app/controllers/login/challenges_controller.rb` — no logic change; verify no
  `email` reference leaks (it does not today).
- `app/controllers/settings/user_controller.rb` — `email` field handling becomes
  `username` field handling (same current-password + recent-TOTP gating;
  username is mutable post-create — implementer keeps the existing change-self
  shape, just swaps the attribute).
- `app/controllers/password_resets_controller.rb` — **new.** The reset-via-2FA
  surface. `new` (form), `create` (verify username + TOTP/backup code, then
  render the set-password step OR stash a short-lived signed reset marker),
  `edit` (set-new-password form, gated by the reset marker), `update` (apply the
  new password). See "Reset-password via 2FA" for the exact shape.
  `allow_anonymous` on every action — the user is not logged in.

Rails app — views:

- `app/views/sessions/new.html.erb` — `email` field → `username` field
  (`type="text"`, `autocomplete="username"`, label `username`, placeholder
  dropped or set to a neutral hint). Replace the "forgot your password? …
  `bin/rails credentials:edit`" lead-paragraph copy with a `[reset password]`
  link to the new reset surface. Lead paragraph one-sentence-per-line per
  architect rule B.
- `app/views/password_resets/new.html.erb` — **new.** Username + TOTP/backup
  code form.
- `app/views/password_resets/edit.html.erb` — **new.** New-password +
  confirmation form.
- `app/views/settings/user/show.html.erb` — `email` field → `username` field
  (path: confirm exact filename during impl; the `Settings::UserController`
  renders `:show`).
- Any TOTP enrollment / challenge view that prints the user's `email` as the
  account label in the QR / provisioning URI context — swap to `username`.
  Likely `app/views/settings/security/totps/show.html.erb` and
  `app/views/login/totp_challenges/show.html.erb`; implementer greps for `email`
  across `app/views/` to catch all of them.

Rails app — routes:

- `config/routes.rb` — add the password-reset routes:
  `get "/password/reset", to: "password_resets#new", as: :password_reset` ;
  `post "/password/reset", to: "password_resets#create"` ;
  `get "/password/reset/edit", to: "password_resets#edit", as: :edit_password_reset`
  ; `patch "/password/reset", to: "password_resets#update"`. Update the Phase 12
  routes comment that says "no password-recovery flow (deferred)". Add the reset
  paths to `LOGIN_PATHS` in `rack_attack.rb` (see below).

Rails app — config:

- `config/initializers/rack_attack.rb` — add `/password/reset` to the throttle
  surface: a per-IP throttle (mirror `login/ip`: 5 POSTs / minute) on
  `POST /password/reset` and `PATCH /password/reset`, and a per-username
  throttle (mirror `login/email`: 10 / 15 minutes, SHA256-hashed username key)
  on `POST /password/reset`. The `throttled_responder` gets a `password/` match
  branch that renders the same generic body as the `login/` branch.
- `config/initializers/sessions_dummy_bcrypt.rb` — no change needed (the dummy
  compare is keyed on a constant hash, not email); the reset controller reuses
  the same dummy-compare pattern for the unknown-username branch — extract or
  reuse `Sessions::DUMMY_BCRYPT_HASH`.

Rails app — rake tasks:

- `lib/tasks/user.rake` — **new** (or add to an existing `pito:`-namespaced task
  file — see "TOTP reset rake task"). Declares `pito:user:reset_totp[username]`:
  clears a user's TOTP enrollment, destroys their backup codes, revokes their
  sessions, prints an operator confirmation. Operator-only, run from a shell.

Cross-cutting:

- `db/seeds.rb` — owner seed reads
  `Rails.application.credentials.owner.{username, password}` instead of
  `{email, password}`. Remove the project-workspace sample block (Collection /
  Game / Project / ProjectReference / Note / Timeline) and the `now playing`
  Collection block. **See "db/seeds.rb coordination" — this file is also touched
  by the parallel AppSetting-consolidation spec.**
- `spec/factories/users.rb` — `email` factory attribute → `username` (sequence
  of valid usernames). This is a fixture / factory file; the implementer updates
  it as part of the same commit. Every spec that builds a `User` with an
  explicit `email:` needs the attribute renamed — the implementer greps `spec/`
  for `email:` against user factories and `User.create` / `build` call sites.
- `lib/tasks/` — any rake task that finds the owner by email (e.g. a `pito:*`
  task). Implementer greps `lib/tasks/` and `bin/` for `find_by(email` /
  `owner.email`.

Docs — **flag for a `pito-docs` pass; this spec does NOT edit them**:

- `CLAUDE.md` — the `User` architecture note (`email (citext…)` →
  `username (citext…)`; "Login is email + password (Phase 8)" → "Login is
  username + password; 2FA mandatory from first login"); the "Configuration
  strategy" section `:owner` block description (`email + password` →
  `username + password`).
- `docs/auth.md` — §1 (login flow: email → username, the mandatory-2FA gate),
  §1a (the console recovery snippet `find_by!(email:)` → `find_by!(username:)`;
  add the reset-via-2FA flow as the primary recovery path; document the new
  `bin/rails pito:user:reset_totp[username]` task as the operator escape hatch;
  the console snippet stays as the bare-bones last resort), §8b
  (`session.create.*` payload `email_attempted` → `username_attempted`), §9 (the
  `login/email` throttle name / key + the new `password/*` throttles), the
  surfaces table row #1.
- `docs/setup.md` — §3 `:owner` block (`email:` → `username:`), §5 (`db:seed` no
  longer creates 100 channels — already stale, also drop the project sample
  mention).

No MCP / CLI / website files. Per the Phase 29 surface pause, any MCP / CLI
consequence of the email→username swap (e.g. `totp_status` tool output, or any
tool that echoes a user identifier) is **deferred** — noted in "Cross-stack
scope", not implemented here.

## Check ordering

The login pipeline has two distinct 2FA touchpoints. Getting them confused is
the main implementation hazard, so the ordering is written out explicitly.

Pre-session (inside `SessionsController#create`, no `Current.user` yet):

1. **Rate-limit / throttle check** — `SessionThrottle` + Rack::Attack.
   Unchanged.
2. **Username lookup** — `User.find_by(username:)`. Unknown →
   `bcrypt_dummy_ compare`, generic `login failed.`
3. **Password check** — `user.authenticate(password)`. Wrong → generic failure.
4. **TOTP login challenge dispatch** — `if user.totp_enabled?` → write pre-auth
   marker, redirect to `/login/totp`. This is the EXISTING Phase 25 behavior and
   stays exactly as is. On a fresh seed the owner does NOT have `totp_enabled?`,
   so they skip this branch.
5. **New-location classification** — for users WITHOUT TOTP enabled:
   `Auth::NewLocationDetector` → `:blocked_pair` (generic failure) /
   `:new_location` / `:trusted`. **Per R4**, a user who is NOT
   `totp_configured?` does not take the pending-approval detour: the
   `:new_location` outcome for such a user mints an **active** session directly
   and records `LoginAttempt.reason = first_login_totp_setup_required`. A
   `:trusted` outcome activates the session as before. The post-session gate
   (step 7) then forces TOTP enrollment.

Post-session (inside `Sessions::AuthConcern`, `Current.user` is now set, runs on
EVERY authenticated HTML request):

6. **`authenticate_session!`** — resolve the `pito_session` cookie, set
   `Current.session` / `Current.user`. Unchanged.
7. **`require_totp_configured!`** (NEW) — `before_action` ordered immediately
   after `authenticate_session!`. If `Current.user` is present and NOT
   `totp_configured?`, and the request path is not on the TOTP-setup allowlist,
   redirect to the TOTP setup entry point. This is the mandatory-2FA gate.
8. App action runs.

Why this ordering. The fresh-seed owner has no TOTP, so at login they pass
through step 4's `if` untaken; step 5 classifies them as a new location (no
`TrustedLocation` rows exist on a fresh seed), and per R4 that no-TOTP user gets
an **active** session minted directly rather than a pending one — so step 7's
post-session gate immediately forces them into TOTP setup. There is no pending
session for a nonexistent approver to approve.

Once the owner has completed TOTP setup, every subsequent login takes step 4
(TOTP challenge), so the post-session gate (step 7) only ever fires in the
narrow window between "password-authenticated, session minted" and "TOTP
confirmed" — i.e. exactly the first-login bootstrap.

## 2FA mandatory gate

### Enforcement mechanism

A `before_action :require_totp_configured!` in `Sessions::AuthConcern`, ordered
immediately after `authenticate_session!`. The hook:

- Returns early (no-op) if `Current.user` is nil — `authenticate_session!`
  already redirected an unauthenticated request.
- Returns early if the action is `allow_anonymous` (the login form, the reset
  surface, etc.) — those have no `Current.user` anyway, but the guard is
  belt-and-suspenders.
- Returns early if `Current.user.totp_configured?` is true.
- Returns early if the current request path / route is on the **TOTP-setup
  allowlist** (below).
- Otherwise:
  `redirect_to settings_security_totp_path, alert: "set up two-factor authentication to continue."`
  (the TOTP `new` page — the enrollment entry point).

**Browser sessions only (R3).** The gate lives in `Sessions::AuthConcern`, which
is included by `ApplicationController`. `Api::AuthConcern` and `Mcp::RackApp`
authenticate bearer credentials, not browser users, and are NOT gated — a token
cannot "set up TOTP", and the browser user who minted the token is themselves
gated. This unit does not touch the API or MCP auth paths.

### TOTP-setup allowlist

The gate must NOT redirect requests that are themselves part of completing TOTP
setup, or the user is trapped in a redirect loop. Allowlisted routes:

- `GET /settings/security/totp` (`totps#new`) — the enrollment landing page.
- `POST /settings/security/totp` (`totps#create`) — generate the seed.
- `GET /settings/security/totp/show` (`totps#show`) — the one-shot QR + codes.
- `PATCH /settings/security/totp/confirm` (`totps#update`) — confirm the code.
- `DELETE /session` (`sessions#destroy`) — the user must be able to log out
  rather than being trapped.
- The asset / health endpoints already excluded by `allow_anonymous` or outside
  the concern (`/up`). Confirm `/up` is not gated.

Everything else — every channel, video, project, settings sub-page, the security
dashboard itself, `/settings/security/totp/disable`, the backup-code regenerate
routes — redirects to the enrollment landing page until `totp_configured?` is
true. Implement the allowlist as an explicit constant set of route names or path
matchers inside the concern; do NOT reuse the `allow_anonymous` macro (different
semantics — those actions skip auth entirely; these require auth but skip the
2FA gate).

### "Configured" definition

`totp_configured?` is true when `totp_enabled_at` is present AND
`totp_disabled_at` is nil — identical to the existing `User#totp_enabled?`. The
implementer either adds `totp_configured?` as a one-line alias for call-site
clarity or uses `totp_enabled?` directly; either is fine, just be consistent.
Backup codes are minted by `Auth::TotpEnroller` during `totps#create` and
displayed on the `totps#show` one-shot screen; there is no separate
"acknowledged backup codes" flag and the gate does not check for one.

### First-login bootstrap (R4 — resolved)

On a fresh seed the owner has no TOTP and no `TrustedLocation` rows. Without an
adjustment, step 5 of the login pipeline classifies their first login as a new
location and routes them to `/login/challenge` → `[ask for approval]` → a
pending session nobody can approve. **The user has confirmed the architect's
proposed fix:**

- A user who is NOT `totp_configured?` does **not** participate in new-location
  approval. In `SessionsController#create`, when the user is not
  `totp_configured?`, the new-location flow mints an **active** session directly
  (not a pending one). The post-session `require_totp_configured!` gate then
  immediately forces them into TOTP setup.
- That active-session-for-an-unconfigured-user path records
  `LoginAttempt.reason = first_login_totp_setup_required` — a **new enum value**
  added for forensic clarity (so the audit trail distinguishes this bootstrap
  path from a normal trusted-location login and from a real new-location
  approval). See "Migration outline" for the enum extension.
- Once TOTP is configured, every future login goes through step 4 (the TOTP
  challenge), so new-location approval is never the gating mechanism for a
  configured user anyway — TOTP is strictly stronger.

## Reset-password via 2FA

A credential-recovery surface with no email. Treated with the same care as
login: throttled, no account-existence oracle, generic failure copy.

### Flow

```
GET  /password/reset        password_resets#new
  → renders the username + code form

POST /password/reset        password_resets#create
  ├── read params[:username], params[:code]
  ├── User.find_by(username: <normalized>)
  ├── unknown username → bcrypt_dummy_compare-equivalent constant-time
  │     work, generic "reset failed." re-render (no oracle)
  ├── user found but NOT totp_configured? → same generic "reset failed."
  │     (do not leak "this account has no 2FA" — and a no-2FA account
  │      genuinely has no reset path; the rake task / console escape
  │      hatch covers it)
  ├── verify code: Auth::TotpVerifier.call(user:, code:) == :ok
  │     OR Auth::BackupCodeConsumer.call(user:, code:) == :ok
  │     (backup code accepted AND consumed — per resolved decision R1)
  ├── on failure → generic "reset failed." re-render, write a
  │     LoginAttempt-style audit row (reason: a new
  │     `password_reset_2fa_failed` reason, or an AuthAuditLog row —
  │     see Open question 1), throttle counter burns
  └── on success → mint a short-lived signed reset marker cookie
        (carries user_id + a Rails.cache nonce, TTL ~10 min, same
         nonce-mirror pattern as PRE_AUTH_COOKIE), redirect to
         /password/reset/edit

GET  /password/reset/edit   password_resets#edit
  ├── load + validate the reset marker (nonce match, not expired)
  │     invalid → redirect to /password/reset, generic alert
  └── render the new-password + confirmation form

PATCH /password/reset       password_resets#update
  ├── load + validate the reset marker again
  ├── read params[:password], params[:password_confirmation]
  ├── mismatch or too short → re-render edit, 422, field error
  ├── on success:
  │     - user.update!(password:, password_confirmation:)
  │     - consume the reset marker (delete cookie + cache nonce)
  │     - reset_session (defense-in-depth — no half-state carries over)
  │     - revoke all of the user's active + pending Session rows
  │       (a password reset invalidates every existing session — the
  │        user re-logs in fresh; this is the standard "reset kills
  │        sessions" guarantee)
  │     - write an AuthAuditLog row (action: a new `password_reset`
  │       action — see Open question 1)
  │     - reset the per-username backoff bucket
  └── redirect_to login_path, notice: "password reset. log in with your
        new password."
```

Note: the reset flow deliberately does **not** auto-log-the-user-in. After a
reset they go to `/login` and authenticate fresh — which, for a TOTP-configured
user, means they also pass the TOTP login challenge. That is the correct
posture: a reset proves possession of the second factor, but the new password
should still be exercised through the normal login path.

### Abuse / hardening considerations

- **No account-existence oracle.** Unknown username,
  known-username-without-TOTP, and wrong-code all produce the identical generic
  `reset failed.` response and the identical wall-clock cost (constant-time
  dummy work on the unknown-username branch, same as
  `SessionsController#bcrypt_dummy_compare`).
- **Throttling.** `rack_attack.rb` gains a per-IP throttle (5 POSTs / minute on
  `POST` and `PATCH /password/reset`) and a per-username throttle (10 / 15
  minutes, SHA256-hashed username key) on `POST /password/reset`. The
  `throttled_responder` renders the same generic body.
- **Replay defense.** `Auth::TotpVerifier`'s `totp_last_used_step` watermark
  already prevents a code consumed in the reset flow from being replayed at
  login (or vice versa) inside the drift window. Backup codes are single-use via
  `Auth::BackupCodeConsumer` (`used_at` stamp under a row lock) — a backup code
  spent on a reset cannot be reused (this is the consumption guarantee behind
  R1).
- **Reset marker.** Signed cookie + Rails.cache nonce, same pattern and TTL as
  `PRE_AUTH_COOKIE`. The nonce is consumed on a successful `update`; the marker
  cannot be replayed to reset the password twice.
- **Session invalidation.** A successful reset revokes every `Session` row for
  the user — a captured cookie cannot survive a password reset.

### Lockout consequence

A user who loses BOTH their authenticator device AND every backup code has no
_self-service_ browser-side recovery path — by design, since there is no email.
The operator escape hatch (resolved decision R2) is the new
`bin/rails pito:user:reset_totp[username]` rake task: an operator with shell
access on the box clears the user's TOTP enrollment and revokes their sessions,
after which the user logs in with their password and is forced through fresh
TOTP enrollment by the mandatory-2FA gate. The Rails-console snippet in
`docs/auth.md` §1a stays documented as the bare-bones fallback (updated to
`User.find_by!(username:)`).

## Migration outline

### Migration 1 — `swap_user_email_for_username`

```ruby
def up
  # Destructive-and-reseed posture (ADR 0003 / docs/setup.md): no
  # production data, so a straight drop + add is correct. No backfill.
  remove_index  :users, name: "index_users_on_email"
  remove_column :users, :email
  add_column    :users, :username, :citext, null: false
  add_index     :users, :username, unique: true,
                 name: "index_users_on_username"
end

def down
  remove_index  :users, name: "index_users_on_username"
  remove_column :users, :username
  add_column    :users, :email, :citext, null: false
  add_index     :users, :email, unique: true,
                 name: "index_users_on_email"
end
```

Caveat for the implementer: `add_column ... null: false` on a table that may
have an existing owner row will fail without a default or a backfill. Because
the canonical path is destructive-and-reseed
(`db:drop db:create db:migrate db:seed`), the migration assumes an empty `users`
table at migrate time. If the implementer wants the migration to also survive a
non-empty table, add the column nullable, backfill from `id` (e.g.
`"user_#{id}"`), then add the NOT NULL constraint — but the spec's position is:
destructive-and-reseed is the supported path, keep the migration simple. No
TOTP-column changes — the Phase 25 TOTP columns (`totp_*`) are reused as-is;
mandatory-2FA is a behavior change, not a schema change.

### Migration 2 (conditional) — `LoginAttempt.reason` enum extension (R4)

R4 adds a `first_login_totp_setup_required` value to `LoginAttempt.reason`. How
this is applied depends on how `reason` is defined:

- **Integer-backed Rails `enum`** (a plain integer column with the mapping in
  `LoginAttempt`): adding the value is a **model-only edit** in
  `app/models/login_attempt.rb` — **no migration**. Pick the next free integer.
- **Postgres enum type**: a migration `ADD VALUE`s
  `'first_login_totp_setup_required'` to the type
  (`db/migrate/<ts>_add_first_login_totp_setup_required_to_login_attempt_reason.rb`).
  Note `ALTER TYPE ... ADD VALUE` cannot run inside a transaction —
  `disable_ddl_transaction!`.

The implementer inspects `LoginAttempt`'s `reason` definition first and applies
whichever path matches. The regression specs assert the value exists and is
recorded on the first-login bootstrap path either way.

If the implementer also adds enum values to resolve Open question 1 (the
reset-flow audit-row shape), that is folded into the same enum-extension change
(`LoginAttempt.reason` for the failure, `AuthAuditLog.action` for the success).
Scope that only after Open question 1 is answered.

## db/seeds.rb coordination

`db/seeds.rb` is edited by **two parallel Phase 29 Lane A specs** — this one
(unit A2) and the AppSetting-consolidation spec (the parallel unit). To let the
two implementations sequence or merge without conflict, here is exactly what
THIS unit touches in `db/seeds.rb`:

- **Owner block, lines ~46-65** — `owner_creds&.dig(:email)` →
  `owner_creds&.dig(:username)`; `owner_email` /`owner_password` local vars →
  `owner_username` / `owner_password`; `User.find_or_initialize_by(email:)` →
  `find_or_initialize_by(username:)`; the placeholder fallback
  `"owner@example.test"` → a valid placeholder username (e.g. `"owner"`); the
  `puts` line. The WARNING copy that says "populate :owner with email and
  password" → "username and password".
- **Project-workspace sample block, lines ~155-215** — DELETE entirely (the
  `puts "seeding project workspace sample..."` block: Collection
  `currently playing`, Game `Demo Game` + cover art, Project `Demo Project`, two
  `ProjectReference` rows, the `Note`, the `Timeline`).
- **`now playing` collection block, lines ~217-245** — DELETE entirely (the
  second Collection + `Pragmata` / `Red Dead Redemption 2` Games).

This unit does **not** touch: the AppSettings block (lines ~8-44), the Platform
reference seeds block (lines ~129-153), or the dev-token block (lines ~67-116).
The AppSetting-consolidation unit owns the AppSettings block. If both land in
the same wave, the AppSettings block and the owner/sample-removal edits are in
disjoint line ranges — a clean merge. If they land sequentially, whichever lands
second rebases trivially. The master agent should still sequence them (one
`pito-rails` dispatch finishes and commits before the other starts) to keep the
diff legible — flag this to the master agent.

## Acceptance

- [ ] `users.email` and `index_users_on_email` are gone; `users.username`
      (citext, NOT NULL) and `index_users_on_username` (unique) exist. Schema
      reflects it.
- [ ] `User` validates `username`: presence, length 3..32, the
      alphanumeric/underscore + single-internal-separator format,
      case-insensitive uniqueness. Whitespace is stripped and the value
      downcased before validation. No `email` validation or `EMAIL_MAX_LENGTH`
      remains.
- [ ] `User#totp_uri` provisions against `username`. No `app/` code references
      `user.email` / `User.find_by(email:)` / `params[:email]` in an auth path.
- [ ] `/login` renders a `username` text field (not an `email` field); the lead
      paragraph links `[reset password]` to `/password/reset` and no longer
      mentions `bin/rails credentials:edit`.
- [ ] `SessionsController#create` authenticates by `username`; unknown username
      pays the constant-time dummy compare and returns the generic
      `login     failed.` with no oracle.
- [ ] `Sessions::AuthConcern` runs `require_totp_configured!` after
      `authenticate_session!`. An authenticated user without TOTP configured is
      redirected to `/settings/security/totp` from every non-allowlisted route.
- [ ] The mandatory-2FA gate is browser-only: `Api::AuthConcern` /
      `Mcp::RackApp` are not gated and are untouched by this unit.
- [ ] The TOTP-setup allowlist (`totps#new` / `create` / `show` / `update`
      confirm, plus `DELETE /session`) is NOT redirected by the gate — no
      redirect loop.
- [ ] Completing TOTP enrollment (`totps#update` stamps `totp_enabled_at`)
      immediately unblocks the gate — the next request to any route succeeds.
- [ ] On a fresh seed, the seeded owner logging in for the first time gets an
      **active** session minted directly (no pending-approval detour), lands in
      the TOTP setup flow, and cannot reach any other screen until they finish.
      That login records
      `LoginAttempt.reason = first_login_totp_setup_required`.
- [ ] `LoginAttempt.reason` has a `first_login_totp_setup_required` value
      (model-only edit or enum-type migration, per the `reason` definition).
- [ ] `/password/reset` exists: `new` form, `create` verifies username + a live
      TOTP code OR a backup code, `edit` set-password form behind the reset
      marker, `update` applies the new password. A backup code used in the reset
      flow is consumed (`used_at` stamped) and cannot be reused.
- [ ] Reset flow has no account-existence oracle: unknown username,
      known-username-without-TOTP, and wrong-code all return the identical
      generic `reset failed.` response with the same wall-clock cost.
- [ ] A successful reset revokes every `Session` row for the user, consumes the
      reset marker, resets the per-username backoff bucket, writes an audit row,
      and redirects to `/login` (does NOT auto-log-in).
- [ ] `rack_attack.rb` throttles `/password/reset` per-IP (5/min) and
      per-username (10 / 15min, hashed key); the throttled responder renders the
      generic body.
- [ ] `bin/rails pito:user:reset_totp[username]` exists: it finds the user by
      username, clears their TOTP enrollment (`totp_seed_encrypted` /
      `totp_enabled_at` / `totp_disabled_at` / `totp_last_used_step` all nil so
      `totp_configured?` is false), destroys their backup codes, revokes all
      their sessions, and prints an operator confirmation. An unknown username
      prints a clear error to `$stderr` and exits non-zero. The task is
      idempotent.
- [ ] `db/seeds.rb` owner seed reads `credentials.owner.{username, password}`;
      the project-workspace sample and the `now playing` collection blocks are
      removed. Channels / videos / projects / games are not seeded.
- [ ] `:owner` credentials block expectation is `{ username, password }` (docs
      flagged for `pito-docs`; the seed reads the new key).
- [ ] All regression specs below are green in CI in the same commit.
- [ ] A `pito-security` `/security-review` pass has run against the implemented
      diff (master-agent-coordinated, post-impl, pre-commit).
- [ ] `CLAUDE.md`, `docs/auth.md`, `docs/setup.md` are flagged for a `pito-docs`
      pass (NOT edited by this unit).

## Regression spec list (per the Phase 29 mandate)

Additive, never substitutive. Every layer touched carries its specs. The impl
agent reports back green before the master agent commits.

### Model specs — `spec/models/user_spec.rb`

- `username` presence: blank / nil rejected.
- `username` length: 2 chars rejected, 3 accepted, 32 accepted, 33 rejected.
- `username` format: accepts `abc`, `a_b`, `a.b`, `a-b`, `user_1`; rejects
  leading / trailing separator, doubled separators (`a..b`), spaces, `@`,
  uppercase-only-after-normalize check (assert it is stored downcased).
- `username` uniqueness is case-insensitive (citext):
  `User.create!(username: "Owner")` then `build(username: "owner")` is invalid.
- whitespace is stripped before validation (`"  owner  "` → `"owner"`).
- `email` is no longer a column / no longer validated (assert
  `User.column_names` excludes `"email"`; assert a `User` with no `email=`
  setter still saves).
- `totp_configured?` / `totp_enabled?` truth table: no seed → false; seed +
  `enabled_at` + nil `disabled_at` → true; seed + `disabled_at` set → false.
- `totp_uri` includes the `username` in the provisioning URI.

### Model spec — `spec/models/login_attempt_spec.rb`

- `LoginAttempt.reason` accepts `first_login_totp_setup_required` (the value
  added per R4) — assert a `LoginAttempt` can be created / persisted with that
  reason.

### Migration spec — `spec/migrations/` or a focused schema assertion

- After migrate: `users` has `username` (citext, null: false) with a unique
  index; does NOT have `email` or `index_users_on_email`. (A lightweight
  `ActiveRecord::Base.connection`-based assertion spec is acceptable; a full
  migration spec is optional.)

### Request specs

`spec/requests/sessions_spec.rb` (update existing):

- happy: valid `username` + `password` for a TOTP-configured user → routed to
  `/login/totp` (existing behavior, just keyed on username now).
- happy: valid `username` + `password` for a user WITHOUT TOTP → an **active**
  session minted directly (not pending),
  `LoginAttempt.reason == first_login_totp_setup_required` recorded, and the
  next request is redirected to `/settings/security/totp`.
- sad: wrong password → generic `login failed.`, 422.
- sad: nonexistent username → generic `login failed.`, 422, no oracle (same
  status + body as wrong-password).
- sad: blank username → generic failure.

`spec/requests/totp_gate_spec.rb` (new):

- an authenticated user without TOTP configured is redirected to
  `/settings/security/totp` from `/`, `/channels`, `/videos`, `/projects`,
  `/settings`, `/settings/security`.
- the allowlisted routes (`GET /settings/security/totp`,
  `POST /settings/security/totp`, `GET /settings/security/totp/show`,
  `PATCH /settings/security/totp/confirm`, `DELETE /session`) are NOT redirected
  by the gate.
- after `totp_enabled_at` is stamped (simulate a confirmed enrollment), a
  request to `/channels` (or any previously-blocked route) succeeds (200 / not
  redirected to the TOTP page).
- an unauthenticated request is still redirected to `/login` (the gate does not
  change unauthenticated behavior).

`spec/requests/password_resets_spec.rb` (new):

- `GET /password/reset` renders the form (200, anonymous-allowed).
- happy: valid username + live TOTP code → reset marker set, redirect to
  `/password/reset/edit`; `GET /password/reset/edit` renders;
  `PATCH /password/reset` with matching passwords → password changed, all the
  user's `Session` rows revoked, redirect to `/login`.
- happy: valid username + a valid backup code → same success path; the backup
  code is marked `used_at` and a second reset attempt with the same backup code
  fails (per resolved decision R1 — backup codes are accepted and consumed).
- sad: nonexistent username → generic `reset failed.`, no marker set, no oracle.
- sad: known username without TOTP configured → generic `reset failed.`, no
  marker set (same response shape as nonexistent username).
- sad: valid username + wrong code → generic `reset failed.`, no marker.
- sad: `GET /password/reset/edit` without a valid reset marker → redirected back
  to `/password/reset`.
- sad: `PATCH /password/reset` without a valid marker → redirected back.
- sad: `PATCH /password/reset` with mismatched / too-short passwords → 422,
  re-render, marker NOT consumed (user can retry).
- abuse: throttling — the 6th `POST /password/reset` from one IP inside a minute
  gets the generic 429 body; the 11th for one username inside 15 minutes
  likewise. (Mirror the existing `login` throttle specs' structure.)
- a successful reset does NOT establish a session (assert no `pito_session`
  cookie / `Current.user` after the redirect).

`spec/requests/settings/user_spec.rb` (update existing): the account-edit form
changes `username` (not `email`); current-password + recent-TOTP gating still
applies.

### Rake task spec — `spec/tasks/pito_user_reset_totp_spec.rb` (new)

- happy: given a user with TOTP configured (`totp_seed_encrypted` set,
  `totp_enabled_at` stamped) plus backup codes and at least one `Session` row,
  running `pito:user:reset_totp[<username>]` leaves the user with
  `totp_configured?` false (all four `totp_*` columns nil), zero
  `totp_backup_codes`, zero `Session` rows, and prints the operator confirmation
  to stdout.
- sad: an unknown username prints a clear error and exits non-zero (`SystemExit`
  with a non-zero status); no record is modified.
- idempotent: running the task twice on the same user (already cleared after the
  first run) does not raise and still prints the confirmation.
- (Use the standard Rake-task spec harness for the project — load
  `Rails.application` + the tasks, `Rake::Task[...].reenable` between
  invocations.)

### System specs (thin — critical journeys only)

`spec/system/fresh_seed_first_login_spec.rb` (new): seed the owner (factory or a
`db:seed`-equivalent setup) → visit `/login` → sign in with username + password
→ asserted to land on the TOTP setup page → attempting to visit `/channels` in
the same session bounces back to the TOTP page → complete enrollment (generate
seed, confirm a code computed from the seed via `ROTP`) → `/channels` now loads.

`spec/system/password_reset_via_2fa_spec.rb` (new): a TOTP-configured user →
visit `/password/reset` → enter username + a `ROTP`-computed code → land on the
set-password page → submit a new password → redirected to `/login` → sign in
with the NEW password (and pass the TOTP challenge) → reach the app.

### Seed spec — `spec/seeds_spec.rb` (or wherever seed coverage lives)

- running the seed creates one `User` from
  `credentials.owner.{username, password}` with the expected `username`.
- the seed does NOT create `Channel`, `Video`, `Project`, `Game`, `Collection`,
  `Note`, or `Timeline` rows (assert counts are zero after seed, except where
  another seed block legitimately creates them — none should after this unit).
- the seed remains idempotent (run twice, still one owner, no duplicates).
- if the existing seed spec asserts the project-workspace sample exists, that
  assertion is removed / inverted.

### Routing specs

- only if the password-reset routes need non-trivial constraints — they do not
  (plain `get` / `post` / `patch`), so a routing spec is optional. The request
  specs cover route resolution.

## Manual test recipe

Fresh terminal, fresh database.

1. **Set the `:owner` credentials to a username.**
   `bin/rails credentials:edit --environment development` and set:
   ```yaml
   owner:
     username: owner
     password: <your-password>
   ```
   Repeat for `--environment test`.
2. **Destructive reseed.** `bin/rails db:drop db:create db:migrate db:seed`.
   Confirm the seed output: one owner user with `username: owner`, no
   project-workspace sample lines, platform rows present.
3. **Confirm the schema.**
   `psql -h 127.0.0.1 -p 54327 -U pito pito_development -c "\d users"` — `email`
   absent, `username` present with a unique index.
4. **Start the stack.** `bin/dev`.
5. **First login forces TOTP.** Open `http://127.0.0.1:3027/login`. The form
   shows a `username` field. Sign in with `owner` + the password. You land on
   the TOTP setup page. Try to navigate to `http://127.0.0.1:3027/channels` —
   you are bounced back to the TOTP setup page.
6. **Complete TOTP setup.** On the setup page, enroll: scan the QR (or paste the
   seed) into an authenticator app, save the backup codes shown, confirm a
   6-digit code. After confirmation, navigate to `/channels` — it now loads.
7. **Log out and back in.** `DELETE /session` via the logout link. Log in again
   with `owner` + password — this time you are routed to `/login/totp` and must
   enter a code. Enter one; you reach the app.
8. **Reset password via 2FA.** Log out. On `/login`, click `[reset password]`.
   On `/password/reset`, enter `owner` + a current 6-digit code from your
   authenticator (or one of the backup codes you saved). You land on the
   set-password page. Set a new password. You are redirected to `/login` with a
   success notice — you are NOT logged in.
9. **Log in with the new password.** Sign in with `owner` + the NEW password,
   pass the TOTP challenge, reach the app. Confirm the OLD password no longer
   works (generic `login failed.`).
10. **Oracle check.** On `/login`, try a nonexistent username (`doesnotexist`) —
    the failure response is byte-identical to a wrong-password failure. On
    `/password/reset`, try a nonexistent username — same generic `reset failed.`
    as a wrong-code failure.
11. **Throttle check.** POST `/password/reset` 6 times in under a minute from
    the same client (curl in a loop) — the 6th returns a generic 429.
12. **Operator TOTP-reset escape hatch.** In a separate terminal, run
    `bin/rails pito:user:reset_totp[owner]`. Confirm the printed confirmation
    ("TOTP reset for owner — sessions revoked …"). Back in the browser, any open
    session is now dead; log in again with `owner` + password — you are forced
    through fresh TOTP enrollment (as in step 5). Then run the task with a bogus
    username (`bin/rails pito:user:reset_totp[nosuchuser]`) and confirm it
    prints a clear "user not found" error and exits non-zero.

Teardown: `bin/rails db:drop db:create db:migrate db:seed` to return to a clean
fresh-seed state.

## Cross-stack scope

- **MCP** — skipped (paused per the Phase 29 roadmap "Surface pause status").
  Deferred consequence: any MCP tool that echoes a user identifier, and the
  `totp_status` tool's relationship to a now-mandatory 2FA posture, get their
  own architect spec on MCP un-pause. No MCP code is touched in this unit. Per
  resolved decision R3, MCP bearer credentials are not subject to the
  mandatory-2FA browser gate regardless.
- **`pito` CLI / TUI** — skipped (paused). The CLI authenticates with a bearer
  `ApiToken`, not a username + password, so the email→username swap does not
  reach the CLI's auth path; no deferred item beyond "the CLI never logs in with
  a username".
- **Cloudflare website (`extras/website/`)** — not in scope (not touched by Lane
  A at all).
- **Bearer-token / Doorkeeper / Google-OAuth surfaces** — out of scope. The
  mandatory-2FA gate is browser-session-only (resolved decision R3); bearer
  surfaces are unaffected. The Google OAuth callback (`YoutubeConnection`) does
  not authenticate a user and is untouched.

## Open questions

1. **(NON-BLOCKING, architect will pick a default if unanswered) Audit-row shape
   for the reset flow.** A successful password reset and a failed reset-code
   attempt should leave an audit trail. Options: (a) add a `password_reset`
   action to `AuthAuditLog.action` and a `password_reset_2fa_failed` reason to
   `LoginAttempt.reason`; (b) reuse existing rows loosely; (c) log only to
   `log/auth_audit.log`. The architect will default to (a) — a new
   `AuthAuditLog` action for the success and a new `LoginAttempt` reason for the
   failure, matching the Phase 25 forensic posture — unless the user prefers
   otherwise. This drives a small enum-extension change folded into Migration 2;
   scoped only once decided.
2. **(NON-BLOCKING) Username format rule.** Decision 1 picks `length 3..32`,
   `[a-z0-9_]` plus single internal `.`/`-` separators, downcased on write. If
   the user has a preference (e.g. allow longer, allow uppercase-preserving,
   forbid dots), say so — otherwise the spec's rule stands.
