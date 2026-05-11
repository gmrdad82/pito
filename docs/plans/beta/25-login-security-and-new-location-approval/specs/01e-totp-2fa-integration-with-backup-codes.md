# Phase 25 — 01e: TOTP 2FA Integration with Backup Codes

> **Sub-spec 01e.** Adds standard TOTP 2FA (1Password-compatible) as the primary
> challenge path on new-location logins, plus 10 single-use backup codes. Plain
> `rotp`; no 1Password Connect SDK.
>
> Reads the umbrella spec first. Locked decisions LD-9 / LD-12 / LD-13 / LD-15 /
> LD-17 apply directly. Open questions Q-C, Q-D, Q-H resolve here.

## Goal

After `01b` routes a new-location login to `/login/challenge`, the `[enter 2FA]`
path lands on a TOTP form. The user types a 6-digit code from any
TOTP-compatible authenticator (1Password, Authy, Google Authenticator,
anything). On success, the session activates, the location becomes trusted, the
session token rotates, and NO pending- approval notification is created (LD-9 +
Mobile note).

Enrollment lives at `/settings/security/2fa` (web only). QR code and plaintext
seed are shown ONCE; backup codes are shown ONCE. The user prints / stores them.
Re-display requires a fresh TOTP challenge.

Disable lives at `/settings/security/2fa/disable` and requires a fresh TOTP
code.

## Files touched

### Gem additions

- `Gemfile` — adds `rotp` (TOTP), `rqrcode` (QR rendering).
- `Gemfile.lock` — updated.

### Migrations

- `db/migrate/<ts>_add_totp_to_users.rb` — `totp_seed_encrypted` (encrypted
  string), `totp_enabled_at` (timestamp), `totp_disabled_at` (timestamp).
- `db/migrate/<ts>_create_backup_codes.rb` —
  `BackupCode(user_id, code_digest, used_at, created_at, updated_at)`.

### Models

- `app/models/user.rb` (existing, gains)
  - `encrypts :totp_seed_encrypted` (Active Record Encryption).
  - `has_many :backup_codes`.
  - `def totp_enabled?` returns true iff
    `totp_seed_encrypted.present? && totp_disabled_at.nil?`.
  - `def totp_uri(issuer:)` returns the `otpauth://` URI for QR rendering.
- `app/models/backup_code.rb`
  - validations: `code_digest` presence, `user_id` presence.
  - `scope :unused` (where `used_at IS NULL`).
  - `def matches?(plaintext)` —
    `BCrypt::Password.new(code_digest) == plaintext`.

### Services

- `app/services/auth/totp_enroller.rb` — generates a fresh 32-char base32 seed,
  generates 10 backup codes (8 chars, base32 alphabet minus ambiguous chars: no
  `0` / `O` / `1` / `I` / `L`), persists encrypted seed + hashed code digests,
  returns the seed + plaintext codes ONCE.
- `app/services/auth/totp_verifier.rb` — verifies a 6-digit code against the
  seed (30-sec window + `drift_behind: 1` for clock-skew tolerance). Returns
  `:ok` / `:invalid`.
- `app/services/auth/backup_code_consumer.rb` — finds an unused matching code,
  stamps `used_at`. Returns `:ok` / `:invalid` / `:already_used`.
- `app/services/auth/totp_disabler.rb` — clears `totp_seed_encrypted`, stamps
  `totp_disabled_at`, destroys backup codes, audit-logs.
- `app/services/auth/backup_code_regenerator.rb` — destroys existing codes,
  generates 10 fresh, audit-logs, returns plaintext codes.

### Controllers

- `app/controllers/settings/security/totp_enrollments_controller.rb`
  - `new` — shows enrollment status; offers `[enroll]` link.
  - `create` — calls `Auth::TotpEnroller`, stores seed + codes in flash +
    session (one-shot), redirects to `show`.
  - `show` — displays QR + seed + backup codes (one-time view; if the flash is
    gone, redirects to `new` with a re-enroll notice).
  - `update` — accepts a TOTP code to confirm enrollment; activates on success
    (writes `totp_enabled_at`).
- `app/controllers/settings/security/totp_disablings_controller.rb`
  - `show` — action-screen confirmation.
  - `create` — accepts a fresh TOTP code, calls `Auth::TotpDisabler`.
- `app/controllers/settings/security/backup_codes_controller.rb`
  - `show` — read-only: shows count of unused codes; never re- displays the
    plaintexts.
  - `new` — action-screen "Regenerate backup codes? Existing codes become
    invalid."
  - `create` — calls `Auth::BackupCodeRegenerator`, displays new codes once.
- `app/controllers/login/totp_challenges_controller.rb`
  - `show` — TOTP form for the new-location-2FA path.
  - `create` — accepts a 6-digit code OR a backup code, calls the verifier or
    the consumer, activates the session on success, rotates the token (LD-12),
    upserts TrustedLocation, writes the success `LoginAttempt`.

### Views

- `app/views/settings/security/totp_enrollments/new.html.erb` — pre-enroll
  status + `[enroll]`.
- `app/views/settings/security/totp_enrollments/show.html.erb` — QR
  - seed + backup codes + `[confirm with code]` form.
- `app/views/settings/security/totp_disablings/show.html.erb` — action-screen.
- `app/views/settings/security/backup_codes/show.html.erb` — count
  - `[regenerate]` link.
- `app/views/settings/security/backup_codes/new.html.erb` — action- screen.
- `app/views/login/totp_challenges/show.html.erb` — 6-digit input
  - backup-code fallback link.

### Components

- `app/components/qr_code_component.rb` / `_component.html.erb` — wraps
  `RQRCode` to emit an `<svg>` payload.
- `app/components/backup_codes_list_component.rb` / `_component.html.erb` —
  bracketed-link [print] action; renders the 10 codes in a fixed-width grid.

### Helpers

- `app/helpers/totp_helper.rb` — issuer string, label format.

### Routes

```
namespace :settings do
  namespace :security do
    resource :totp_enrollment, only: [:new, :create, :show, :update]
    resource :totp_disabling, only: [:show, :create]
    resource :backup_codes, only: [:show, :new, :create]
  end
end

get  "login/totp",  to: "login/totp_challenges#show",  as: :login_totp
post "login/totp",  to: "login/totp_challenges#create"
```

### MCP

Read-only surfaces only in this sub-spec:

- `app/mcp/tools/totp_status.rb` — returns whether 2FA is enabled for the acting
  user (yes/no), enrollment date if any, unused- backup-code count. Auth-scoped.

Enrollment / disable / regenerate are explicitly web-only this phase (the seed
must reach the user's authenticator app, which is not Claude). Confirm in open
questions.

### TUI

- The TUI does NOT enroll 2FA in this phase.
- The TUI's `Login::TotpChallenges#create` endpoint is reachable via the JSON
  API for the TUI to submit a TOTP code if the user is mid-challenge in the
  terminal client (rare; the user is more likely on web). Stub the TUI flow as
  "if 2FA challenge surfaces, status-line prompts for the 6-digit code; on
  submit, POST /login/totp.json".

### Specs (spec pyramid)

#### Model specs

- `spec/models/user_spec.rb` (existing, gains)
  - `totp_seed_encrypted` is encrypted at rest (raw column ≠ plaintext).
  - `totp_enabled?` returns true post-enrollment, false post-disable.
  - `totp_uri` returns a valid `otpauth://` URI.
- `spec/models/backup_code_spec.rb`
  - validations.
  - `matches?` constant-time compare (BCrypt).
  - `scope :unused` excludes used rows.

#### Service specs

- `spec/services/auth/totp_enroller_spec.rb`
  - happy: returns seed + 10 codes; persists encrypted seed + 10 bcrypt digests.
  - happy: backup codes use the 28-char alphabet (no ambiguous chars).
  - happy: re-enroll replaces seed + codes.
  - sad: user already enrolled → raises (must disable first).
  - flaw: returned seed is identical to stored seed when decrypted; no
    off-by-one base32.
  - flaw: returned codes match `BCrypt::Password.new(digest) == code` for each.
- `spec/services/auth/totp_verifier_spec.rb`
  - happy: correct code within window → `:ok`.
  - happy: code from 30 sec ago (drift_behind: 1) → `:ok`.
  - sad: code from 60 sec ago → `:invalid`.
  - sad: incorrect code → `:invalid`.
  - sad: code is not 6 digits → `:invalid`.
  - flaw: doesn't leak which case via timing (`rotp` is constant- time-ish; mark
    as documented).
- `spec/services/auth/backup_code_consumer_spec.rb`
  - happy: unused code → `:ok` + stamps `used_at`.
  - sad: used code → `:already_used`.
  - sad: nonexistent code → `:invalid`.
  - edge: race condition — concurrent consumption of same code → one `:ok`, one
    `:already_used` (pessimistic lock on the row).
- `spec/services/auth/totp_disabler_spec.rb`
  - happy: clears seed + destroys codes + audit-logs.
  - sad: not enrolled → no-op.
- `spec/services/auth/backup_code_regenerator_spec.rb`
  - happy: destroys + regenerates + audit-logs.
  - sad: not enrolled → raises.

#### Component specs

- `spec/components/qr_code_component_spec.rb`
  - renders an `<svg>` for any TOTP URI.
- `spec/components/backup_codes_list_component_spec.rb`
  - renders the 10 codes; `[print]` bracketed link present.

#### Request specs

- `spec/requests/settings/security/totp_enrollments_spec.rb`
  - GET new → 200, shows status.
  - POST create → 302 to show; one-shot flash carries seed + codes.
  - GET show after refresh → 302 to new with "enrollment expired" notice
    (one-shot is gone).
  - PATCH update with correct code → 200, `totp_enabled_at` set, audit-logged.
  - PATCH update with wrong code → 422.
  - All routes require auth.
- `spec/requests/settings/security/totp_disablings_spec.rb`
  - GET show → 200, action-screen.
  - POST create with correct fresh code → disables + redirects.
  - POST without correct code → 422.
- `spec/requests/settings/security/backup_codes_spec.rb`
  - GET show → 200, count visible, no plaintext.
  - GET new → 200, action-screen.
  - POST create → regenerates, one-shot flash.
- `spec/requests/login/totp_challenges_spec.rb`
  - GET show with pre-auth marker → 200.
  - POST with correct TOTP → activates session, rotates token (new session token
    differs from pre-auth marker), upserts trusted, writes success row with
    `reason: new_location_2fa_passed`.
  - POST with correct backup code → activates, stamps backup code used, writes
    success row.
  - POST with wrong TOTP → 422, writes `reason: 2fa_failed`.
  - POST with already-used backup code → 422, writes `2fa_failed`.
  - POST with no pre-auth marker → 401.

#### MCP tool spec

- `spec/mcp/tools/totp_status_spec.rb`
  - happy: returns `"totp_enabled": "yes"` / `"no"`, count of unused codes.
  - sad: scope missing → scope error.

#### System spec

Cross-cutting journey covered in `01g`. End-to-end:

- enrollment → confirm → 2FA challenge on new-location → trusted → disable →
  re-enrollment.

#### Routing spec

- `spec/routing/settings_security_totp_routing_spec.rb` — confirms the new
  routes.

## Service decomposition

```
Settings::Security::TotpEnrollmentsController#create
  └── Auth::TotpEnroller.call(user:)
      ├── persist encrypted seed
      ├── persist 10 bcrypt-digested codes
      └── return { seed, plaintext_codes }  (one-shot)

Settings::Security::TotpEnrollmentsController#update
  ├── Auth::TotpVerifier.call(user:, code:)
  ├── stamp totp_enabled_at
  └── Auth::AuditLogger.call(action: :totp_enroll)

Login::TotpChallengesController#create
  ├── try Auth::TotpVerifier.call(user:, code:)
  │   on :ok →
  │     ├── Auth::SessionActivator (reset_session, mint new token)
  │     ├── TrustedLocation.touch_for
  │     ├── LoginAttempt write (reason: :new_location_2fa_passed)
  │     └── redirect "/"
  ├── else try Auth::BackupCodeConsumer.call(user:, code:)
  │   on :ok → same activation path; code marked used
  └── else write LoginAttempt (reason: :2fa_failed); render 422

Settings::Security::TotpDisablingsController#create
  ├── Auth::TotpVerifier.call(user:, code:)  # require fresh code
  ├── Auth::TotpDisabler.call(user:)
  └── Auth::AuditLogger.call(action: :totp_disable)

Settings::Security::BackupCodesController#create
  ├── Auth::BackupCodeRegenerator.call(user:)
  └── Auth::AuditLogger.call(action: :backup_code_regenerate)
```

## Acceptance

- [ ] `rotp` + `rqrcode` gems added.
- [ ] `users.totp_seed_encrypted` migrated + AR-encrypted.
- [ ] `backup_codes` table migrated.
- [ ] `Auth::TotpEnroller` generates 32-char base32 seed + 10 codes from the
      safe alphabet.
- [ ] `Auth::TotpVerifier` honors `drift_behind: 1` for clock skew.
- [ ] `Auth::BackupCodeConsumer` single-use semantics (`used_at` stamped; row
      stays for audit).
- [ ] `Auth::TotpDisabler` clears seed + codes + audit-logs.
- [ ] `Auth::BackupCodeRegenerator` rotates codes + audit-logs.
- [ ] Enrollment flow: `new` → `create` → `show` (one-shot view) → `update`
      (confirm with code).
- [ ] One-shot seed + codes never re-displayed after the first successful
      confirmation OR on a subsequent page load.
- [ ] `/login/totp` accepts either TOTP code or backup code; success activates
      the session, rotates the token (LD-12), upserts `TrustedLocation`, writes
      a `success` LoginAttempt.
- [ ] `Login failed.` is the only failure copy on TOTP miss (LD-14).
- [ ] No JS confirm / alert / prompt.
- [ ] Action-screen pattern on disable + regenerate-backup-codes.
- [ ] Yes / no Booleans at every external boundary.
- [ ] `totp_status` MCP tool read-only.
- [ ] `docs/auth.md` documents enrollment, recovery procedure (Q-D — Rails
      console only), backup code reuse policy.
- [ ] Friendly URLs locked.
- [ ] Full RSpec green; Brakeman clean; bundler-audit clean.

## Manual test recipe

1. `git pull --rebase`, `bundle install`, `bin/dev`.
2. Visit `/settings/security/2fa` → `[enroll]`.
3. Scan QR with 1Password (or any TOTP app). Note the plaintext secret + 10
   backup codes.
4. Enter a fresh 6-digit code from the app → confirmation.
5. Verify `totp_enabled_at` is set.
6. Log out. From a new-location browser, submit correct password → `[enter 2FA]`
   → `/login/totp` → enter code → activated, redirect.
7. Verify the new session token differs from the pre-auth marker (cookie
   inspection).
8. Verify a row `result: success, reason: new_location_2fa_passed` in
   `/settings/security/attempts`.
9. Log out. From the same new-location browser (cleared cookies), submit correct
   password again → `/login/challenge` shows `[enter 2FA]` and
   `[ask for approval]` even though the location is now trusted? NO — location
   is trusted; trusted-login path skips the challenge. Verify this matches the
   locked behavior.
10. Test backup code path: log out, new browser, correct password → TOTP form →
    enter a backup code instead → activates; mark used.
11. Try the same backup code again on a fresh attempt → fails with
    `Login failed.`; attempt row carries `2fa_failed`.
12. Visit `/settings/security/2fa/disable` → action-screen → enter fresh code →
    disable. `totp_disabled_at` stamped; backup codes destroyed.
13. Re-enroll → confirm 10 fresh backup codes.
14. MCP: call `totp_status` → returns `"totp_enabled": "yes"`,
    `"unused_backup_codes": "10"` (string per yes/no boundary? no — counts stay
    numeric; only Booleans are yes/no. Confirm in open questions).
15. Teardown: disable 2FA again if testing further.

## Cross-stack scope

| Surface | Status                                                       |
| ------- | ------------------------------------------------------------ |
| Rails   | In scope (full enrollment + challenge + disable).            |
| TUI     | Challenge-only via JSON API; no enrollment.                  |
| MCP     | `totp_status` read-only; no enroll/disable tools this phase. |
| Website | Out of scope.                                                |

## Open questions

- **Q-C** (backup code count + reuse policy): 10 codes, single-use. Confirm.
- **Q-D** (TOTP-lost fallback): Rails console only this phase; document
  procedure. Confirm.
- **Q-H** (1Password Connect SDK): plain TOTP — no SDK. Confirm.
- New: should the backup code alphabet exclude `B` / `8`, `O` / `0`, `1` / `I` /
  `L`? Lock: yes.
- New: should `totp_status` return the count as a string (`"10"`) or integer?
  Recommend integer; yes/no is for Booleans only per the hard rule.
- New: should we surface a "Last used backup code at" timestamp on
  /settings/security/2fa? Recommend yes (single line, muted).
- New: should the TUI receive a follow-up to enroll TOTP via paste-the-seed
  flow? Defer to Phase 26.
