# Security review — Auth refactor (A0 + A1 + A2 combined)

**Branch:** `main` (uncommitted working tree)
**Specs:**

- `docs/plans/beta/29-screen-polish-sweep/specs/channel-read-only-conversion.md` (A0)
- `docs/plans/beta/29-screen-polish-sweep/specs/appsetting-credentials-consolidation.md` (A1)
- `docs/plans/beta/29-screen-polish-sweep/specs/user-auth-refactor.md` (A2)

**Reviewer playbook:** none yet for this combined diff (parallel run)
**Audit run:** 2026-05-15

## Verdict

**MERGE WITH FIX-FORWARD.**

The diff lands a careful, defense-in-depth auth refactor: no oracle on the
login / password-reset surface, throttled at IP + username, replay-safe TOTP
+ backup codes, atomic backup-code consumption under a row lock, pre-auth
nonce mirroring, mandatory-2FA gate, signed reset markers with cache-mirrored
nonces consumed on success. Brakeman `-w1` surfaces no new findings; the
warnings present are all pre-existing patterns (composites SendFile, unscoped
ImportJob finds, Game raw SQL in genre shelf — all out of this diff's scope).

Two items below (**F1 High**, **F2 Medium**) should be fixed before this
ships to a real user with real API tokens / OAuth grants; none are remote-
exploit blockers, but together they leave a gap where a successful password
reset does NOT revoke bearer credentials minted under the prior password.

Everything else is informational or out-of-scope-but-noted. No Critical
findings.

## Findings

### F1. Password reset does not revoke ApiToken / Doorkeeper OAuth access tokens

- **Severity:** High
- **Location:** `app/controllers/password_resets_controller.rb:142`
  (and the rake escape hatch at `lib/tasks/pito.rake:104-113`)
- **Description:** The reset-via-2FA `update` action revokes every `Session`
  row via `@user.sessions.find_each(&:revoke!)` and resets `Rails.session`,
  but does NOT touch:

  - **`ApiToken` rows** — bearer credentials owned by this user. `User` has
    no `has_many :api_tokens` association at all
    (`app/models/user.rb:34-48`), so password reset leaves them live and
    usable indefinitely (until manual revoke at `/settings/tokens`).
  - **`OauthAccessToken` / `OauthAccessGrant`** — Doorkeeper-issued bearer
    credentials whose `resource_owner_id` is this `User`. The Doorkeeper
    initializer is configured for browser-session `resource_owner_authenticator`
    (`config/initializers/doorkeeper.rb:46`); a 2h access-token TTL means a
    captured Doorkeeper token still grants up to ~2 hours of full-scope
    access after a "successful" password reset, plus the 14-day refresh
    token window if `refresh` grant was used.

  The same gap exists on the operator rake task
  `bin/rails pito:user:reset_totp[username]`: it destroys sessions + backup
  codes + TOTP enrollment, but leaves ApiToken / Doorkeeper tokens alive.

  **Exploit scenario.** A user's password is leaked + a `dev`-scope API
  token is exfiltrated. The user notices, completes reset-via-2FA. Their
  cookie session is killed, but the attacker still holds the bearer token
  (full `app` + `dev` scope until manually revoked) and continues to read /
  write the install via `/mcp` or `/api/`. The reset gives a false sense of
  recovery.

- **Recommendation:**
  1. In `PasswordResetsController#update`, after `@user.sessions.find_each(&:revoke!)`, add:
     ```ruby
     ApiToken.where(user_id: @user.id, revoked_at: nil)
             .update_all(revoked_at: Time.current)
     Doorkeeper::AccessToken.where(resource_owner_id: @user.id, revoked_at: nil)
                            .update_all(revoked_at: Time.current)
     Doorkeeper::AccessGrant.where(resource_owner_id: @user.id, revoked_at: nil)
                            .update_all(revoked_at: Time.current)
     ```
     wrapped in the same transactional context as the password write.
  2. Apply the same revocation block to the rake task
     `lib/tasks/pito.rake#:reset_totp`. An operator running it on a
     compromised account expects every credential to die.
  3. Add `has_many :api_tokens` on `User` (with `dependent: :destroy` for
     consistency with `:sessions`) so the association is discoverable from
     the model and a future `dependent: :destroy` reasoning is not surprised
     by the gap.
  4. Add `Auth::AuditLogger.call(... action: :password_reset, metadata: {
     sessions_revoked: N, tokens_revoked: M, oauth_revoked: K })` so the
     audit row carries the revocation tallies — useful for incident
     forensics.

- **References:** OWASP ASVS 3.7.1 (Password recovery must revoke all
  pre-existing credentials of the user), CWE-613 (Insufficient Session
  Expiration).

### F2. Username enumeration via timing on the no-TOTP branch of password reset

- **Severity:** Medium
- **Location:** `app/controllers/password_resets_controller.rb:73-81`
- **Description:** The reset flow gates on three branches: unknown username,
  known username without TOTP, and known username with TOTP-but-wrong-code.
  The first two pay `bcrypt_dummy_compare` and the third pays
  `Auth::TotpVerifier.call` (or `Auth::BackupCodeConsumer.call`). The
  intent is wall-clock symmetry across branches.

  The dummy bcrypt compare (~80–250 ms depending on hardware/cost factor)
  symmetrizes the no-TOTP branch against the unknown-username branch, but
  NOT against the wrong-code branch:

  - **TotpVerifier** does a `ROTP::TOTP#verify` (HMAC-SHA1 over a 30-second
    window with drift_behind=1) — sub-millisecond.
  - **BackupCodeConsumer** iterates `user.totp_backup_codes.unused.find_each`
    and runs BCrypt compare per row. With the default of 10 unused codes,
    that is ~10 × bcrypt-cost. A user with all 10 backup codes paid pays
    ~10× the no-TOTP user's wall-clock; a user with 0 unused codes (all
    consumed) pays 0× bcrypt and the verifier round-trip.

  Mixed-case codes that fail the alphabet/length pre-check
  (`backup_code_consumer.rb:26,33`) short-circuit before bcrypt — making
  the "wrong-shape code" path FAST. An attacker can probe with a known-bad
  short code and measure response time:

  - Long wall-clock (≈ dummy bcrypt) → unknown OR no-TOTP user.
  - Short wall-clock → user EXISTS AND has TOTP enabled.

  The attacker still cannot distinguish "no account" from "no TOTP", which
  is the explicit goal — but they CAN distinguish "has TOTP enabled" from
  "doesn't have TOTP / doesn't exist", which is the smaller information
  leak.

- **Recommendation:**
  1. Always run `bcrypt_dummy_compare` once on the verify path too, BEFORE
     dispatching the TOTP / backup-code branches:
     ```ruby
     unless verify_recovery_code(user, code)
       bcrypt_dummy_compare  # symmetrize wall-clock with the bail branches
       audit("password_reset.failed", ...)
       render_reset_failed
       return
     end
     ```
     This makes the wrong-code branch pay the same ~bcrypt cost as the
     unknown / no-TOTP branches.
  2. Alternatively (preferred), centralize the symmetrization in a
     `with_constant_wallclock` helper so the same shape applies to
     `SessionsController#create` if/when it grows similar branch asymmetry.
  3. Document the wall-clock invariant in the controller header so a future
     edit doesn't accidentally break it.

- **References:** CWE-208 (Observable Timing Discrepancy), CWE-203
  (Observable Discrepancy).

### F3. Rake task `pito:user:reset_totp` accepts the username verbatim from `argv` — no shell-history hygiene note

- **Severity:** Low
- **Location:** `lib/tasks/pito.rake:91-119`
- **Description:** The escape hatch is correctly gated on shell access to
  the box. There is no command injection — Rake arguments are passed as
  strings, not shelled out. However, the username lands in shell history
  (`~/.bash_history` / `~/.zsh_history`), `ps aux` (visible for the
  duration of the rake invocation), and any centralized command logging.
  This is informational hygiene — operators running this task should be
  aware. The current task description in the rake task already documents
  the usage; consider adding a short security note.

- **Recommendation:**
  1. Add a one-line note in the task description:
     `# NOTE: invocation lands in shell history. acceptable — usernames are not secrets.`
  2. Consider supporting `bin/rails pito:user:reset_totp` (no arg) that
     prompts for the username via `$stdin.gets` so an operator who cares
     about shell-history hygiene has an alternative.

- **References:** CWE-532 (Insertion of Sensitive Information into Log
  File) — informational only; usernames are not secret.

### F4. Rate-limit responder for `password/` does not write a `LoginAttempt` row

- **Severity:** Low
- **Location:** `config/initializers/rack_attack.rb:249-268`
- **Description:** The `login/` throttle responder at lines 222-247 calls
  `Auth::RateLimitLogger.call(...)` to persist a `LoginAttempt` row with
  `reason: :rate_limited`. The parallel `password/` branch (lines
  249-268) renders the generic `reset failed.` body but does NOT write any
  row. Effect: an attacker who hits the password-reset rate limit produces
  no forensic artifact for the operator's `/settings/security/attempts`
  page. The audit-log JSON (`audit("password_reset.*")`) only fires from
  inside the controller, which is bypassed by the rack_attack short-
  circuit.

- **Recommendation:**
  1. Inside the `match.start_with?("password/")` branch of
     `Rack::Attack.throttled_responder`, call
     `Auth::RateLimitLogger.call(request: ActionDispatch::Request.new(req.env), username: req.params["username"])`.
     The logger already handles the "no fingerprint composer" path with
     a synthesized rate-limit hash and is `rescue StandardError` safe.
  2. Consider adding a `:password_reset_rate_limited` reason value to the
     `LoginAttempt.reason` enum so the row is filterable from the attempt
     log surface; or reuse the existing `:rate_limited` value if the
     surface distinction is captured elsewhere (it is not today).

- **References:** OWASP ASVS 7.1.2 (audit log must capture rate-limit
  events).

### F5. `Sessions::AuthConcern::TOTP_SETUP_ALLOWLIST` is a `"METHOD path"` string list — no canonical-path normalization

- **Severity:** Informational
- **Location:** `app/controllers/concerns/sessions/auth_concern.rb:34-40,117-119`
- **Description:** The allowlist match composes `"#{request.request_method} #{request.path}"`
  and looks for exact-string membership. Edge cases that fail the match (and
  therefore re-redirect the user to the enrollment page):

  - Trailing slash variants (`/settings/security/totp/`).
  - Format suffix in the path (`/settings/security/totp.json`).
  - Mixed-case (`/Settings/Security/TOTP`) — Rails routes are case-sensitive
    by default but some upstream proxies normalize differently.

  None of these is an exploit: an allowlist miss redirects the user back
  to `/settings/security/totp` — which IS allowlisted — and the page
  renders. There is no fail-open variant.

  This is an observation, not a flaw. The current implementation is
  conservatively closed: failed match → redirect to the safe page.

- **Recommendation:** Optional — normalize via `request.path.chomp('/')`
  and explicitly enumerate the format-suffix variants if the future surfaces
  JSON access to the TOTP enrollment endpoints (they currently do not).

### F6. `bcrypt_dummy_compare` is defined twice (sessions + password resets) — copy-paste drift risk

- **Severity:** Informational
- **Location:**
  - `app/controllers/sessions_controller.rb:335-340`
  - `app/controllers/password_resets_controller.rb:235-240`
- **Description:** Both controllers carry the same body that compares the
  boot-time precomputed `Sessions::DUMMY_BCRYPT_HASH` against
  `Sessions::DUMMY_BCRYPT_PLAINTEXT`. Identical implementations; risk is
  a future edit to one and not the other introducing timing asymmetry
  between the two surfaces.

- **Recommendation:** Extract into a shared helper module
  (`Sessions::DummyBcryptCompare`) included by both controllers, or
  promote it to a class method on `Sessions::Authenticator` / a `Pito::Auth`
  PORO. F2's recommended call site reinforces the shared-helper case.

### F7. `User.encrypts :totp_seed_encrypted` exists but the schema column is `:text` — confirm Active Record Encryption envelope size

- **Severity:** Informational
- **Location:** `app/models/user.rb:15`, `db/schema.rb` (user table)
- **Description:** The model declares `encrypts :totp_seed_encrypted` (non-
  deterministic by default). The column comment notes the encrypted
  envelope is larger than the 32-char plaintext seed and `:text` is correct.
  This is fine; flagging because a future migration changing the column
  type (e.g., to `string`/varchar(32)) would silently truncate ciphertext
  and corrupt every TOTP seed.

- **Recommendation:** Add a schema-level guard or model-level comment that
  the column MUST stay `:text`. A future spec touching the users table
  should not casually change the type. Not blocking.

### F8. Operator-level credential rotation requires a Puma restart (already documented; this diff codifies it)

- **Severity:** Informational
- **Location:** `config/initializers/omniauth.rb:38-75`,
  `app/services/youtube/token_refresher.rb:28-37`,
  `app/services/youtube/public_client.rb:75-82`,
  `app/jobs/notes/embed_job.rb:83-89`
- **Description:** This diff explicitly closes the prior follow-up (#3) by
  accepting "credential rotation requires Puma restart" as the design
  posture. The omniauth initializer reads `Rails.application.credentials.google_oauth`
  at boot; rotating the credential without a restart will leave the
  middleware bound to the old client_id/secret until restart.

  This is operationally fine for pito's single-install posture. No
  security implication — a rotated credential is still active during the
  in-flight token-refresh window. The risk is operator confusion
  ("I rotated, why is it still using the old one?"), addressed in the
  initializer's comment.

- **Recommendation:** Document the restart requirement at the top of
  `docs/setup.md` or `docs/auth.md` so a credentials rotation runbook
  exists. (Docs-agent territory; out of this auditor's writeable scope.)

## Out-of-scope but noted

These are NOT new in this diff and NOT blockers — listing so the master
agent can decide whether to file follow-up specs.

- **`Settings::UserController#update`** (`app/controllers/settings/user_controller.rb`)
  uses `params.dig(:user, ...)` and assigns `attrs[:username]` / `attrs[:password]`
  individually rather than `params.require(:user).permit(...)`. Effect: the
  controller is parameter-by-parameter explicit, which is safe — no mass-
  assignment risk. Stylistic note only.
- **`app/controllers/channels/stars_controller.rb:16`** skips CSRF when
  `request.format.json?` — project-wide pattern (8 other controllers do
  the same) and motivated by the cookie-authed CLI consumers. Bearer-
  authed JSON callers come through `/api/` (separate `Api::AuthConcern`).
  Re-verifying this lane is fine post-A0 since the new controller is
  small and the only mutable channel field is `star`.
- **`docs/auth.md`** still references "email + password login" in §1 and
  the auth-surface table. Stale post-A2. Docs-agent should refresh.
- **Brakeman `-w1` warnings** that pre-date this diff:
  - `RESET_PASSWORD_PATH` flagged as a "hardcoded secret" — false positive,
    it's a URL path constant, not a credential. Recommend inline
    `# brakeman:ignore Secrets` annotation.
  - `app/queries/games/genre_shelf_batch.rb:82` raw SQL with `to_i` cast
    inputs — safe in this case, but a `Game.find_by_sql` interpolation
    pattern is brittle. Out of scope.
  - `app/views/settings/security/totps/show.html.erb:31` — SVG QR code
    is generated from internal data (cached enrollment seed), not user
    input. Safe; brakeman cannot prove it.

## Quality gate evidence

- **Security static analysis (strict — brakeman -w1 -A):** 12 warnings
  total, **0 new in this diff**. All Medium-Weak confidence findings are
  pre-existing patterns out of scope for the A0/A1/A2 changes.
- **Dependency audit:** not re-run; reviewer playbook owns the
  `bundler-audit` lane. The diff adds no new gems (Gemfile unchanged).
- **`/security-review` summary:** The auth refactor is well-defended in
  depth. Generic `login failed.` / `reset failed.` copy is consistent
  across surfaces; rate limiting covers both `login/` and `password/`
  surfaces with per-IP + per-username buckets. The pre-auth nonce mirror
  (cookie + Rails.cache) is correctly applied on TOTP challenge AND
  reset marker, with `ActiveSupport::SecurityUtils.secure_compare` on
  both. TOTP replay defense is correct (monotonic step watermark).
  Backup-code consumption is atomic (row-locked transaction). The
  mandatory-2FA gate is correctly browser-only — `Api::AuthConcern` and
  `Mcp::RackApp` are bearer-credential surfaces and do not include
  `Sessions::AuthConcern`, so the gate cannot deny API requests, which
  is the right posture (a bearer cannot "set up TOTP").

  The single behavior gap worth fixing-before-merge is **F1** — password
  reset must revoke bearer credentials, not only sessions. **F2** is a
  smaller leak (TOTP-enabled-or-not enumeration via timing) worth
  closing in the same patch.
