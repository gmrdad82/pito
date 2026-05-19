# Auth

The single source of truth for pito's authentication and authorization model.
pito is a **single-install, multi-user** application (ADR 0003): the whole
database belongs to one install, every authenticated user has install-wide
read/write access, and there is no per-user data isolation. Authentication is
mandatory at every endpoint, every MCP tool, and every controller action.

Four surfaces gate access to the install:

- **Browser → Rails (Web Puma)** — cookie + DB-backed sessions; login is
  **username + password + mandatory TOTP** (Phase 8 + Phase 29 Unit A2).
- **MCP / `pito` CLI → Rails (MCP Puma + API routes)** — bearer `ApiToken`s
  (HMAC-digested, scoped, revocable). NOT gated by the mandatory-2FA flow
  (bearer credentials are not user-with-a-browser sessions).
- **Third-party clients → Rails** — Doorkeeper-issued OAuth 2.0 tokens
  (Authorization Code + PKCE; Phase 6B).
- **pito → Google (outbound delegation)** — OAuth-delegated `YoutubeConnection`
  for YouTube API access (Phase 7; channel-only OAuth per ADR 0006, renamed from
  `GoogleIdentity` in Phase 9).

If you came here looking for something specific:

- "How do I log in?" → §1 (login flow).
- "How do I enroll 2FA?" → §1a (totp 2fa + backup codes).
- "What happens on a new-location login?" → §1b (new-location detection +
  pending sessions).
- "Where do I unblock a fingerprint / ip pair?" → §1c (auto-block list).
- "How do I reset my password?" → §1d (reset-via-2FA).
- "How do I unstick a user who lost their TOTP and every backup code?" → §1e
  (operator-only `pito:user:reset_totp` rake task).
- "How do I generate a dev token?" → §7.
- "Which scope does my MCP tool require?" → §4.
- "How does a request flow through auth?" → §5.
- "What runs on the production proxy boundary?" → §11 (production hardening +
  Cloudflare drift watchdog).

## Auth surfaces overview

This document is authoritative for **username + password + mandatory TOTP
login** (surface #1, §1 below) and **bearer ApiTokens** (surface #2, the rest of
the document — the original Phase 5 Auth Foundation). Surfaces #3 and #4 are
documented elsewhere.

| #   | Surface                   | Mechanism                                                | Authoritative reference                                                                                                                                                                                                                                                                                                                 |
| --- | ------------------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Browser → Rails           | Cookie + DB-backed sessions (username + password + TOTP) | §1 below for the login flow + rate-limit + audit shape; §1a for TOTP enrollment + challenge; §1b for new-location detection; §1d for reset-via-2FA; §1e for the operator escape hatch. Live code: `app/controllers/sessions_controller.rb`, `app/controllers/concerns/sessions/auth_concern.rb`. Revocation UI at `/settings/sessions`. |
| 2   | MCP / `pito` CLI → Rails  | Bearer ApiTokens (HMAC-digested, scoped, revocable)      | The rest of this document (`docs/auth.md`). Live code: `app/lib/api/token_authenticator.rb`, `app/models/api_token.rb`.                                                                                                                                                                                                                 |
| 3   | 3rd-party clients → Rails | Doorkeeper-issued OAuth (Authorization Code + PKCE)      | Spec: `docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6b-doorkeeper-oauth-server.md`. Live config: `config/initializers/doorkeeper.rb`. Tokens are 2h access / 14d refresh. Stays per ADR 0005.                                                                                                                                  |
| 4   | pito → Google (YouTube)   | OAuth-delegated `YoutubeConnection` (encrypted at rest)  | `docs/architecture.md` "Google OAuth + YouTube API foundation (Phase 7, renamed Phase 9)" section. Live code: `app/models/youtube_connection.rb`. Channel-only OAuth per ADR 0006 (no "Sign in with Google"); renamed from `GoogleIdentity` in Phase 9.                                                                                 |

The four surfaces are independent. A request from a browser session (#1) cannot
authenticate as an ApiToken (#2); a Doorkeeper access token (#3) does not grant
Google API access (#4). Each surface has its own credential type, lifetime, and
revocation path.

Surface #1 (browser → Rails) is the only path that authenticates a user TO pito.
Google OAuth (#4) is exclusively an outbound delegation that authorizes pito to
talk to YouTube on the user's behalf — it never produces a session, never gates
a login, and never replaces a password (ADR 0006). Phase 9 retired the dormant
"Sign in with Google" branch from the callback controller; the surviving
`/auth/google/callback` flow exists solely to mint and refresh
`YoutubeConnection` rows.

## 1. Login flow (username + password + mandatory TOTP)

The login form at `/login` accepts a single `username` field plus `password` and
submits to `SessionsController#create`. There is no "email" path and no "Sign in
with Google" alternative — Phase 29 Unit A2 dropped the `email` column from
`users` and re-introduced `username`; ADR 0006 narrowed Google OAuth to channel
connection only. Email is not part of pito's data model — no SMTP, no
transactional mail, no forgot-password-via-email anywhere in this project.

After a correct password, the login pipeline has **two distinct 2FA
touchpoints** — getting them confused is the main implementation hazard:

1. **Pre-session TOTP login challenge** (`/login/totp`) — runs on a new-location
   login when the user already has 2FA enrolled. The user is not yet
   authenticated; a pre-auth marker carries them through the form.
2. **Post-session mandatory-2FA gate**
   (`Sessions::AuthConcern# require_totp_configured!`) — runs on every
   authenticated browser request for a user who has never enrolled. Redirects to
   the enrollment flow until the user confirms a fresh code. Browser-only (Phase
   29 R3): API tokens and MCP bearer credentials are NOT subject to the gate.

### Model

- `User` — auth-only model. Columns:
  `id, username (citext, unique, NOT NULL), password_digest, created_at, updated_at`,
  plus the four TOTP columns (`totp_seed_encrypted`, `totp_enabled_at`,
  `totp_disabled_at`, `totp_last_used_step`). No `email`, no `tenant_id`, no
  `admin`. `has_secure_password`.
  - **Username format:** `/\A[a-z0-9_]+(?:[.-][a-z0-9_]+)*\z/i`,
    `length: 3..32`, case-insensitive uniqueness; citext column,
    `normalize_username` downcases on write.
  - `User#totp_configured?` — alias for `totp_enabled?`
    (`totp_seed_encrypted.present? && totp_disabled_at.nil?`). The mandatory-2FA
    gate calls `totp_configured?`.
- `Session` — DB-backed session record (Phase 6A). Carries the cookie's session
  id, the user reference, IP / user-agent metadata, and supports per-session
  revocation via `/settings/sessions`.

### Flow

```
POST /login (username, password)
   │
   ├── User.find_by(username: <stripped, downcased>)
   ├── If found: user.authenticate(password)        → bcrypt compare
   │   If not found: bcrypt_dummy_compare(password) → constant-time, same wall-cost
   │
   ├── Both branches return the same generic
   │   "login failed." flash on failure
   │   (no oracle on whether the username exists, the password was wrong,
   │    the pair is blocked, or the request was rate-limited — LD-14).
   │
   ▼ on correct password — classify the login location (§1b)
     │
     ├── trusted pair (fingerprint + ip prefix) → activate session
     │     │
     │     └── post-session: require_totp_configured! gate (§1a — mandatory)
     │           ├── totp_configured? = true  → app
     │           └── totp_configured? = false → /settings/security/totp/new
     │
     ├── new pair + totp_configured? = true → redirect to /login/totp (§1a)
     │     │
     │     └── on success: activate session → post-session gate passes
     │
     ├── new pair + totp_configured? = false → first-login bootstrap (R4)
     │     │  (no-TOTP fresh-seed user — pending-approval would be meaningless
     │     │   without an established account; mint an ACTIVE session directly)
     │     │
     │     └── LoginAttempt.reason = first_login_totp_setup_required
     │           post-session gate forces enrollment
     │
     └── new pair + totp_configured? = false AND TrustedLocation rows exist
         → /login/pending, spawn pending session + notification
   │
   ▼ on session activation
   Session.create_for!(user:) — issues cookie + rotates token on 2FA path
   LoginAttempt row written (reason: trusted_location_success |
                             new_location_2fa_passed | new_location_pending |
                             first_login_totp_setup_required)
   redirect_to <intended_path> || root_path
```

**Check ordering** for a single login: password → new-location / blocked-pair
classification → TOTP login challenge → mandatory-2FA setup gate → app. The
pre-session challenge (touchpoint #1) and the post-session gate (touchpoint #2)
are independent — a user with TOTP enrolled hits #1 on a new location and #2
never fires; a user without TOTP hits #2 every authenticated browser request and
#1 never fires.

The bcrypt-dummy-compare on the no-such-username branch closes the timing oracle
that previously distinguished "no such account" from "wrong password" via
wall-clock latency (Phase 8 F1 fix; Phase 29 Unit A2 ported it to username).
Phase 25 broadened the generic-copy rule — wrong password, unknown account,
blocked pair, and rate-limit all surface the same `login failed.` flash (LD-14).
The internal `LoginAttempt` row carries the precise reason; the UI does not.
`LoginAttempt.email_attempted` column remains for historical rows but is
populated with the typed username for new attempts.

### Rate limit

Throttles defend `POST /login`, the challenge surfaces, and the reset-via-2FA
surface (§1d):

- **Per-IP — login** — 5 attempts / minute on `/login`, `/login/challenge`,
  `/login/totp`, and `/login/pending`. Keyed on `req.ip` after Rack walks the
  `X-Forwarded-For` chain past the trusted Cloudflare CIDRs (§11).
- **Per-account — login** — 10 attempts / 15 minutes keyed on
  `Digest::SHA256.hexdigest("login-username:#{username.downcase}")`. The hash
  keeps the raw username out of `Rack::Attack`'s cache store. (Phase 29 Unit A2
  re-keyed the throttle from email to username; the throttle name in
  `rack_attack.rb` is unchanged for ergonomic continuity but the hashed input is
  now the typed username.)
- **Per-IP — password reset** — 5 attempts / minute on `POST /password/reset`
  and `PATCH /password/reset` (§1d).
- **Per-account — password reset** — 10 attempts / 15 minutes keyed on
  `Digest::SHA256.hexdigest("password-username:#{username.downcase}")` on
  `POST /password/reset`.
- **Exponential backoff** — `Auth::BackoffCalculator` doubles the window on each
  consecutive trip (60s → 120s → 240s → … → capped at 3600s) and stores the bump
  in `Rack::Attack.cache.store` (Redis) with a TTL. A successful login resets
  the per-account bucket so a legitimate user who typo'd a few times is never
  locked out indefinitely.
- **Generic copy on throttle** — the `throttled_responder` renders the same
  `login failed.` flash (or `reset failed.` for the password-reset surface) as a
  wrong-password reply (LD-14) and writes a `LoginAttempt` row with
  `reason: rate_limited` via `Auth::RateLimitLogger`.

The legacy `SessionThrottle` (10 failures / 5 min, per-IP) survives as a
defense-in-depth blocklist alongside `Rack::Attack`; both buckets land in the
attempt log via `Auth::RateLimitLogger.call`. A `development?`-only safelist on
`127.0.0.1` keeps the maintainer's dev environment usable.

Bearer-token surfaces have an independent throttle (§9).

### Audit log

Every login attempt — success or failure — writes a `LoginAttempt` row (see
§1b). Every privileged auth action (approve / block / unblock / purge / totp
enroll / disable / backup-code regenerate, plus the YouTube / Voyage credentials
updates) writes an `AuthAuditLog` row via `Auth::AuditLogger` (§8). The legacy
`log/auth_audit.log` file still receives bearer-token outcomes from
`Api::TokenAuthenticator`; the JSON-line catalog lives in §8.

## 1a. TOTP 2FA + backup codes (mandatory)

Phase 25 added standard RFC 6238 TOTP as the primary challenge on new-location
logins. Phase 29 Unit A2 made TOTP **mandatory from first login**: every
authenticated browser user must have a confirmed TOTP enrollment before any
non-allowlisted page is reachable. The library is `rotp` (verification) +
`rqrcode` (enrollment QR). Plain TOTP — no 1Password Connect SDK; 1Password is
just one of many compatible authenticator apps.

### Mandatory-2FA gate (browser-only)

`Sessions::AuthConcern` runs `require_totp_configured!` as a `before_action`
immediately after `authenticate_session!`. When the authenticated user's
`totp_configured?` predicate is false AND the request is not in the allowlist,
the gate redirects to `/settings/security/totp/new` and short-circuits the rest
of the controller chain. The allowlist (`TOTP_SETUP_ALLOWLIST`) covers exactly
the endpoints needed to reach the enrollment confirmation screen plus the logout
escape hatch:

- `GET /settings/security/totp/new` — enrollment form.
- `POST /settings/security/totp` — enrollment create.
- `GET /settings/security/totp` — show / one-shot reveal screen.
- `PATCH /settings/security/totp` — confirm the 6-digit code.
- `DELETE /session` — logout.

Every other authenticated browser route 302s back to the enrollment flow until
the user confirms.

**Scope is browser-only** (Phase 29 R3). The concern is included only by
`ApplicationController`. `Api::AuthConcern` and `Mcp::RackApp` do NOT include it
— bearer credentials authenticate a token, not a user-with-a-browser; a token
cannot "set up TOTP". The browser user who minted the token IS gated, so the
token-minting path is protected upstream.

The gate fires on every browser request, not just login. A user who logs in on
Monday, configures TOTP, then has their TOTP cleared by the operator's
`pito:user:reset_totp` rake task (§1e) will be redirected into the enrollment
flow on their very next browser request — the operator's clearing call also
revokes their sessions, so in practice the user re-logs in and the gate catches
the post-login redirect.

### Enrollment

`/settings/security/totp/new` (web only — the seed must reach the operator's
authenticator app, which is not Claude). The flow:

1. `Auth::TotpEnroller.call(user:)` generates a fresh 32-char base32 seed and 10
   single-use backup codes. The seed is encrypted at rest on
   `users.totp_seed_encrypted` via Active Record Encryption. Backup codes are
   stored as BCrypt digests on the `backup_codes` table.
2. The seed plaintext, QR code, and the 10 backup codes are shown ONCE on the
   confirmation screen (one-shot flash). Reload re-renders an "enrollment
   expired" notice; the codes cannot be recovered.
3. The user confirms a fresh 6-digit code from their app. On success,
   `totp_enabled_at` is stamped and `Auth::AuditLogger` writes a `totp_enroll`
   row.

Backup code shape:

- **10 codes**, **8 characters each** (locked: Q-C).
- Alphabet: `A-Z` + `2-9` minus the visually-confusable characters `O`, `I`,
  `L`, `B`, `8`, `1` (and digit `0`). Drawn with
  `SecureRandom.random_number(...)` so the cryptographic guarantee is explicit
  at the source (Phase 25 F10 hardening).
- Single-use. `Auth::BackupCodeConsumer` stamps `used_at` inside a pessimistic
  row lock; the row stays for audit.

### Login challenge (`/login/totp`)

On a new-location login with 2FA enabled, the correct-password branch redirects
to `/login/totp` with a pre-auth marker on the session. The form accepts EITHER
a 6-digit TOTP code OR an 8-char backup code:

1. `Auth::TotpVerifier.call(user:, code:)` runs ROTP `verify` with
   `drift_behind: 30` (allows one window of clock skew). On a hit it captures
   the matched 30-second step (`matched_at.to_i / 30`) and writes it to
   `users.totp_last_used_step` via `update_columns`. RFC 6238 §5.2 replay
   defense — the same code cannot be replayed inside its window, and an older
   drift step cannot be accepted after a newer one (Phase 25 F9).
2. If verification fails, `Auth::BackupCodeConsumer.call(user:, code:)` tries
   the backup-code path. The consumer:
   - Rejects any input whose length is not exactly 8 characters (Phase 25 F4 —
     `< 4` was tightened to exact-equal).
   - Rejects any character outside the safe alphabet before any BCrypt
     round-trip (closes the alphabet-leak timing oracle).
   - Iterates `user.totp_backup_codes.unused.find_each` so used rows never
     re-enter the BCrypt loop (closes a timing-oracle leg between "wrong
     plaintext" and "used plaintext").
3. On success, the controller calls `reset_session` (Rails) AND the
   `Sessions::TokenRotation` concern to mint a fresh `pito_session` cookie plus
   a fresh DB-session token (LD-12 — session fixation defense). The
   `TrustedLocation` row is upserted; a `success` `LoginAttempt` is written with
   `reason: new_location_2fa_passed`; the per-account backoff bucket is reset.
4. On failure, the controller writes a `LoginAttempt` row with
   `reason: 2fa_failed` and renders `login failed.` (LD-14).

### Disable + regenerate backup codes

Both flows go through the action-screen pattern at
`/settings/security/totp/edit` (disable) and
`/settings/security/totp/backup_codes/new` (regenerate). Each requires the
user's password AND a fresh TOTP code on the same form; the failure copy is the
generic `credentials don't match.` flash (no oracle on which field failed).
Successful disable destroys the encrypted seed and every backup code; successful
regenerate destroys the existing codes and mints 10 fresh ones. Both write an
`AuthAuditLog` row (`totp_disable`, `backup_code_regenerate`) and rotate the
session token.

### `RecentTotpVerification` gate

Sensitive write actions that don't already require 2FA at login (user account
edit, Voyage indexing-toggle update, Slack / Discord webhook saves) include the
`RecentTotpVerification` concern. (The YouTube credentials surface no longer
exists in the Settings UI per ADR 0012 / Phase 29 Unit A1.) When the acting user
has 2FA enabled, the controller calls `require_recent_totp_if_enabled!` before
the write. The helper:

- Returns `true` immediately when the user has no 2FA enrolled.
- Otherwise verifies the submitted `params[:totp_code]` via
  `Auth::TotpVerifier`. The verifier's replay-defense watermark applies — a code
  consumed here cannot be replayed against a different sensitive action in the
  same drift window.
- On failure, renders the generic `credentials don't match.` flash (matching the
  disable / regenerate copy) and short-circuits the action.

Read-only views are never gated; only the writes.

### Recovery (TOTP-lost fallback)

Three recovery paths, in increasing order of disruption:

1. **Backup code at login** — if the user has any unused backup code, the
   `/login/totp` challenge accepts it in place of a live TOTP code
   (`Auth::BackupCodeConsumer` consumes it under a row lock, single-use).
2. **Operator rake task** — if the user has lost both the authenticator app AND
   every backup code, the operator runs
   `bin/rails pito:user:reset_totp[<username>]` from a shell on the box. The
   task clears the TOTP enrollment, destroys backup codes, and revokes all
   sessions. The user re-logs in fresh and the mandatory-2FA gate forces
   re-enrollment. See §1e.
3. **Rails console snippet** — bare-bones last resort (if the rake task is
   unavailable for some reason — e.g. a botched deploy mid-task). Open a console
   on the host, then:

   ```ruby
   user = User.find_by!(username: "owner")
   user.update_columns(totp_seed_encrypted: nil,
                       totp_enabled_at: nil,
                       totp_disabled_at: nil,
                       totp_last_used_step: nil)
   user.totp_backup_codes.destroy_all
   user.sessions.destroy_all
   ```

   The rake task is preferred — it is the friendly idempotent counterpart to
   this snippet.

Email-based reset is permanently out of scope; there is no SMTP and no email
column. The single-install, single-operator posture (Q-D) makes operator shell
access the authorization boundary.

## 1b. New-location detection + pending sessions

Phase 25 redefined "trusted" as a `(fingerprint_hash, ip_prefix)` tuple that has
previously authenticated successfully on the target user.

### Fingerprint composition

```text
fingerprint_hash = SHA256(
  User-Agent + Accept + Accept-Language + Accept-Encoding +
  "screen=" + screen_hint + "lang=" + locale_hint
)
```

A small Stimulus controller on the login form posts the screen hint
(`window.screen.width × height @ devicePixelRatio`) and the locale hint
(`Intl.DateTimeFormat().resolvedOptions().timeZone + "/" + navigator.language`)
alongside email + password; the server composes the hash. **Privacy-preserving
omissions** (LD-2): no canvas / AudioContext / WebGL / font enumeration /
Battery / Network Information APIs. Raw inputs are never persisted — only the
hash.

### IP-prefix matching

`/24` for IPv4, `/64` for IPv6 (LD-3). Residential and mobile IPs rotate inside
a stable household / org boundary; matching on the prefix keeps the boundary
stable. The helper is `Pito::Auth::IpPrefix`.

### Outcome classification

```text
TrustedLocation.where(user_id:, fingerprint_hash:, ip_prefix:).any?
   │
   ├── yes → activate session immediately
   │         (reason: trusted_location_success)
   │
   └── no  → classify "new location":
              ├── 2FA enrolled → redirect to /login/totp
              │                  (reason at success: new_location_2fa_passed)
              └── 2FA absent   → mint pending session
                                 (reason: new_location_pending,
                                  state: pending_approval,
                                  approval_required_until: now + 10 minutes)
```

A successful trusted or new-but-just-trusted login upserts a `TrustedLocation`
row and stamps `last_seen_at`.

### Pending-session state machine

`Session` (Phase 6) gained two columns:

- `state` enum — `active` / `pending_approval` / `expired` / `revoked`.
- `approval_required_until` timestamp.

Transitions:

```text
active             ← trusted-location login, 2FA-passed login,
                     or approve-on-pending action
pending_approval   ← new-location-correct-password without 2FA
expired            ← time-based, SessionPendingApprovalSweeper Sidekiq cron
                     transitions rows whose approval_required_until < now
revoked            ← user action from /settings/sessions, or block on the
                     pending session, or SessionStaleSweeperJob (30-day
                     idle cutoff on active sessions)
```

Expired pending sessions cannot transition back to active. They survive in the
attempt log indefinitely; the operator can purge them from the §1c block list UI
or the attempt log UI.

Two Sidekiq cron sweepers keep the state honest:

- `SessionPendingApprovalSweeper` — runs every minute, expires pending-approval
  sessions past their deadline.
- `SessionStaleSweeperJob` — runs every 15 minutes (`*/15 * * * *`), revokes
  `state: active` sessions whose `last_activity_at` (or `created_at` when nil)
  is older than 30 days.

### Approve / block surfaces

Pending sessions surface a `login_pending_approval` notification (urgent,
deduped one-per-pending — Phase 16 carrier). The notification body and action
links route to:

- **Web** — `/login_attempts/:id/approve` / `/login_attempts/:id/block`
  (action-screen confirmation, two-step).
- **TUI** — in-TUI modal overlay on the notifications surface (`a` approve / `b`
  block, two-stage confirmation; `Login::ApprovalsController` and
  `Login::BlocksController` accept `confirm=yes` form-encoded POSTs).
- **MCP** — `login_attempt_approve` and `login_attempt_block` tools (auth scope,
  `confirm: "yes"` parameter; see §4).

Approve flips `state: pending_approval → active`, upserts the `TrustedLocation`,
resolves the notification, writes an `AuthAuditLog` row (`action: approve`), and
rotates the session token on the acting session. Block flips the pending session
to `revoked`, creates a `BlockedLocation` row, resolves the notification, writes
`AuthAuditLog` (`action: block`), and rotates the token.

### `LoginAttempt` schema

`LoginAttempt` carries the full forensic record of every authentication attempt
(success, failed, pending, blocked, rate-limited). Never auto-purged; manual
purge only via `/settings/security/attempts/purge` (web) or
`login_attempt_purge` (MCP). The `reason` enum is the precise classification:

```text
wrong_password / unknown_account / blocked_pair / rate_limited /
new_location_pending / new_location_2fa_passed / 2fa_failed /
trusted_location_success / pending_expired /
approved_from_{web,tui,mcp} / blocked_from_{web,tui,mcp} /
first_login_totp_setup_required
```

`first_login_totp_setup_required` (value 15, added by Phase 29 Unit A2) marks
the R4 first-login bootstrap branch — a no-TOTP user successfully passed
password verification on a new location and was minted an active session
directly so the mandatory-2FA gate could force enrollment (see §1 flow diagram).

Browse the log at `/settings/security/attempts` (paginated) or via the
`login_attempts_list` / `login_attempts_pending` MCP tools (§4).

## 1c. Auto-block list

Blocking a pending session — or invoking `login_attempt_block` against any
attempt row — creates a `BlockedLocation`:

```text
BlockedLocation
  fingerprint_hash, ip_prefix, blocked_at, blocked_by_user_id,
  source_surface (web|tui|mcp), reason, last_attempt_at, attempt_count,
  unblocked_at, unblocked_by_user_id
```

A subsequent login attempt whose `(fingerprint_hash, ip_prefix)` matches a
non-soft-unblocked row short-circuits before the password check and writes a
`LoginAttempt` row with `result: blocked, reason: blocked_pair`. The UI surfaces
the same generic `login failed.` flash (LD-14).

### Block list UI

`/settings/security/blocked_locations` lists every blocked pair (paginated).
Per-row actions:

- `/settings/security/blocks/:block_id/unblocking` — action-screen confirmation,
  soft-unblock (stamps `unblocked_at` + `unblocked_by_user_id`; the row stays in
  the audit trail).
- `/settings/security/blocks/purge` — bulk purge by filter (action-screen
  confirmation; `safe_audit_purge` writes an `AuthAuditLog` row with
  `target_type: "BlockedLocation"` + `target_id: 0` representing the collection
  scope).

Auto-block decay is intentionally absent (Q-E) — decaying blocks would silently
reopen old threats. Purge is operator-driven.

The `blocked_locations_list` MCP tool (auth scope) returns the same surface for
cross-stack ops.

## 1d. Reset-via-2FA password recovery

Phase 29 Unit A2 built the password-recovery surface for the first time, as a
**reset-via-2FA** flow. Email is permanently absent from this project; the
second factor (TOTP code OR backup code) substitutes for the email link that a
conventional reset flow would send.

### Routes

- `GET /password/reset` — username + TOTP/backup-code form
  (`PasswordResetsController#new`).
- `POST /password/reset` — verifies the username + factor, mints a short-lived
  signed reset marker, redirects to the set-password step (`#create`).
- `GET /password/reset/edit` — new-password + confirmation form, gated by the
  reset marker (`#edit`).
- `PATCH /password/reset` — applies the new password, revokes every session for
  the user, redirects to `/login` (`#update`).

Every action is `allow_anonymous` — the user is not logged in.

### Flow

```
GET /password/reset
   │
   ▼
POST /password/reset (username, totp_or_backup_code)
   │
   ├── User.find_by(username: <stripped, downcased>)
   ├── If found:
   │     ├── Auth::TotpVerifier.call(user:, code:)     → :ok | :invalid
   │     └── OR Auth::BackupCodeConsumer.call(user:, code:) → :ok | :invalid
   │         (backup code consumed on :ok — single-use, R1)
   ├── If not found: constant-time dummy bcrypt + dummy TOTP verify
   │   (no username-existence oracle)
   │
   ├── Both branches return the same generic
   │   "reset failed." flash on any failure
   │   (no oracle on whether the username exists, the factor was wrong,
   │    or the request was rate-limited)
   │
   ▼ on success
   mint short-lived signed reset marker:
     ├── cookie: PasswordResetsController::RESET_MARKER_COOKIE (signed)
     └── nonce:  Rails.cache.write("pw_reset:<id>", token, expires_in: 10.min)
   redirect to GET /password/reset/edit
   │
   ▼
GET /password/reset/edit
   │  (reset marker required — anonymous request without it 302s to /login)
   ▼
PATCH /password/reset (password, password_confirmation)
   │
   ├── verify reset marker (signed cookie + Rails.cache nonce match)
   ├── apply new password via has_secure_password
   ├── user.sessions.destroy_all   (revokes every existing session)
   ├── Auth::AuditLogger row: action: password_reset
   ├── clear reset marker (cookie + cache nonce)
   │
   ▼
   redirect to /login (NO auto-login — the user re-types credentials,
                       hits the TOTP login challenge, gets a fresh session)
```

### Properties

- **Accepts live TOTP OR backup code (R1).** A user who lost their authenticator
  but kept their backup codes still has a path; the backup code is consumed.
- **No username-existence oracle.** The unknown-username branch runs a
  constant-time dummy bcrypt + dummy TOTP verify so the wall-clock latency of
  the response carries no signal. Generic `reset failed.` flash regardless of
  which step failed.
- **Rate-limited.** Per-IP 5/min and per-username 10/15min on
  `POST /password/reset` (see §1 "Rate limit" above and §9). The
  `throttled_responder` `password/` branch matches the `login/` branch: generic
  `reset failed.` flash, no information leak.
- **Revokes every session on reset.** A successful reset destroys every
  `Session` row for the user, including the device the operator is reading this
  doc on. Defensive — if the password was compromised the live sessions must die
  with it.
- **No auto-login.** After the reset the user redirects to `/login` and
  re-authenticates from scratch (username + new password, then the TOTP login
  challenge). Defensive — auto-login after a recovery flow lets a marker-replay
  attack walk straight into the app.
- **`AuthAuditLog.action = password_reset`** (slot 9) writes the reset row with
  `target: User`,
  `metadata: { source_ip:, fingerprint_hash:, factor: "totp" | "backup_code" }`.

### Failure modes that DO short-circuit

- Username not found → constant-time dummy verify → `reset failed.`
- Username found, factor invalid (TOTP code wrong AND backup code wrong) →
  `reset failed.`
- Reset marker absent / expired / forged on `GET /edit` or
  `PATCH /password/reset` → 302 to `/login`.
- Rate-limit trip → `reset failed.` + `LoginAttempt.reason: rate_limited`.

### Failure mode that does NOT short-circuit

The new password failing `User`'s `password_digest` validations (too short,
mismatch with confirmation, etc.) re-renders `#edit` with the validation errors
— the reset marker stays valid until it expires, so the user can fix the mistake
without restarting the flow.

## 1e. Operator escape hatch — `pito:user:reset_totp` rake task

For the lockout scenario reset-via-2FA cannot cover — the user lost BOTH their
authenticator app AND every backup code — the operator runs a rake task from a
shell on the box. Operator shell access is the authorization boundary; there is
no in-product surface for this escape hatch (Q-D — single-install,
single-operator).

### Invocation

```bash
bin/rails 'pito:user:reset_totp[<username>]'
```

The square-bracket form with quotes is the canonical Rake argument shape;
without quotes, the shell may eat the brackets.

### What it does

For the named user (case-insensitive lookup against the citext `username`
column):

1. Clears all four TOTP columns: `totp_seed_encrypted: nil`,
   `totp_enabled_at: nil`, `totp_disabled_at: nil`, `totp_last_used_step: nil`.
   Returns the user to the same "never enrolled" state a fresh seed produces;
   the mandatory-2FA gate (§1a) forces clean re-enrollment on the next login.
2. Destroys every `TotpBackupCode` row for the user — the old codes are
   meaningless once the seed is gone.
3. Destroys every `Session` row for the user (active and pending). A TOTP reset
   is a credential-state change; no live session may survive it.
4. Prints a `$stdout` confirmation:
   `TOTP reset for <username> — sessions revoked, backup codes cleared. They will be forced through TOTP setup on next login.`

### Properties

- **Idempotent.** Running it on a user who already has no TOTP configured is a
  no-op-equivalent (writing nils over nils, `destroy_all` on empty relations are
  harmless) and still prints the confirmation.
- **No `Current.user`, no 2FA challenge.** It is a shell task; operator
  possession of shell access on the box is the authorization boundary, exactly
  like the legacy Rails-console snippet at §1a.
- **Non-zero exit on unknown username.** Prints `user not found: <username>` to
  `$stderr` and exits 1 — no stack trace, no oracle concern (operator-only
  context).
- **Does NOT write an `AuthAuditLog` row.** The task runs without
  `Current.user`; the audit logger requires an acting user. The session
  revocation and TOTP clearance are recorded implicitly by the absent enrollment
  state on next login (the user's next `LoginAttempt` will fire
  `first_login_totp_setup_required` again, which is the durable forensic trace).

## 2. ApiToken model overview

Three moving parts:

```
User ──< ApiToken
              │
              └── scopes: ["dev", "app"]   # subset of Scopes::ALL

Current   (ActiveSupport::CurrentAttributes)
  ├── user
  ├── session
  └── token         ← set by Api::TokenAuthenticator on every API request
```

- `User` — owner of tokens (see §1). Seeded from the `:owner` credentials block
  (`{ username, password }` per Phase 29 Unit A2).
- `ApiToken` — bearer credential. Stored as an HMAC-SHA256 digest with a
  server-side `:tokens.pepper` credential; plaintext is shown once at creation
  and never persisted. Has a `name`, a `scopes` jsonb array, optional
  `expires_at`, and a soft-revoke `revoked_at`.
- `Current` — `ActiveSupport::CurrentAttributes`. Carries `user`, `session`,
  `token` for the duration of a request (or job, or rake task). Reset on every
  response and between every spec example. There is no `Current.tenant`.

## 3. Scope catalog

Authoritative source: `app/lib/scopes.rb`. Listed below as a reference; if the
two diverge, the file wins. Per ADR 0004 the catalog was simplified to a small
set of values; Phase 25 added the `auth` scope alongside the original `dev` /
`app` split (locked decision LD-8 in the Phase 25 umbrella spec at
`docs/plans/beta/25-login-security-and-new-location-approval/specs/01-overview-login-security-and-new-location-approval.md`;
an ADR capturing the Phase 25 locks is an open docs follow-up).

| Scope  | Description                                                                                      |
| ------ | ------------------------------------------------------------------------------------------------ |
| `dev`  | read and capture developer docs.                                                                 |
| `app`  | application access. manage channels, videos, projects, and the calendar.                         |
| `auth` | auth + login security. list pending attempts, approve / block / unblock / purge, read audit log. |

A token has any subset of the three. The trade-off is intentional — catalog
stability over fine-grained authorization. The `auth` scope is opt-in per token
via the settings/tokens edit page; it is NOT included in the default
Claude-mobile token (LD-8).

### Strip-on-release

`Scopes::ALL` is computed against two strip-on-release flags:

- `Rails.application.config.x.mcp.expose_auth_scope` — gates the `auth` scope
  and its nine tools (§4).

Per environment:

- Development / test → `["dev", "app", "auth"]` (both flags default to `true`).
- Production → `["app"]` (both flags are `false`). The `dev`-scoped and
  `auth`-scoped tools are dropped from the MCP tool registry, and `ApiToken`
  rejects any save whose `scopes` array contains `"dev"` or `"auth"`.
  Defense-in-depth: even a token whose `scopes` jsonb literally carries the
  stripped value cannot reach a gated tool because the tool isn't registered AND
  the scope isn't in the catalog.

The strip-on-release flags are the security boundary equivalent of the Sidekiq
Web auth: dev tooling and remote auth-administration both stay behind the
operator boundary on a productized release.

### Soft-revoke migration posture

ADR 0004 implementation revoked every existing `ApiToken`,
`Doorkeeper::AccessToken`, and `Doorkeeper::AccessGrant` row in a single
migration
(`db/migrate/20260510110333_revoke_tokens_for_scope_simplification.rb`). Rows
stayed in the database with `revoked_at` set — soft-revoke matches the existing
audit posture. `OauthApplication.scopes` strings were rewritten in-place using
the legacy → new mapping (`dev:*` / `website:*` → `dev`; `yt:*` / `project:*` →
`app`). Users re-pair Claude Mobile + Web MCP once after the deploy; the consent
screen displays the two new scopes.

### Soft-clip monkey-patch

`config/initializers/doorkeeper_scope_clip.rb` survives the simplification. The
patch's math (`requested ∩ application.scopes ∩ server.scopes`) is
catalog-agnostic. Under the new 2-scope catalog its behavior is:

- A request for `scope=dev app` against an application whitelisted for both →
  succeeds; the consent screen renders.
- A request that names a legacy string (`scope=dev:read`, `scope=yt:write`, …) →
  rejected with `error=invalid_scope`. Legacy strings are not in `Scopes::ALL`,
  so the patch clips them out and Doorkeeper's standard `validate_scopes` step
  rejects what remains.
- A request for `scope=dev` under `expose_dev_scope=false` (production) →
  rejected the same way; the server catalog drops `dev` so the request has no
  overlap.

Legacy scope strings are clipped, not rejected outright — the failure surfaces
as a normal `invalid_scope` redirect rather than a 500. The implementation
agent's `spec/requests/oauth_scope_clip_spec.rb` covers each branch.

Adding a new scope means editing `Scopes::ALL` and `Scopes::DESCRIPTIONS` and
ticking the corresponding tools' `require_scope!` calls. New tool surfaces
(calendar, notifications, IGDB, etc.) all use `Scopes::APP`; the namespace
choice is structural (dev tooling vs. application data), not per-domain.

## 4. Tool / endpoint scope map

Every MCP tool's `call` method opens with `Mcp::ToolAuth.require_scope!(...)`.
Every JSON controller action declares its required scope via `require_scope!`
from `Api::AuthConcern`.

### MCP tools

| Tool                     | Required scope |
| ------------------------ | -------------- |
| `list_channels`          | `app`          |
| `get_channel`            | `app`          |
| `list_videos`            | `app`          |
| `get_video`              | `app`          |
| `get_dashboard`          | `app`          |
| `search`                 | `app`          |
| `list_saved_views`       | `app`          |
| `manage_settings`        | `app`          |
| `create_channel`         | `app`          |
| `update_channel`         | `app`          |
| `create_video`           | `app`          |
| `update_video`           | `app`          |
| `create_saved_view`      | `app`          |
| `delete_saved_view`      | `app`          |
| `sync_records`           | `app`          |
| `delete_records`         | `app`          |
| `login_attempts_pending` | `auth`         |
| `login_attempts_list`    | `auth`         |
| `login_attempt_approve`  | `auth`         |
| `login_attempt_block`    | `auth`         |
| `login_attempt_unblock`  | `auth`         |
| `login_attempt_purge`    | `auth`         |
| `auth_audit_log_list`    | `auth`         |
| `blocked_locations_list` | `auth`         |
| `totp_status`            | `auth`         |

`manage_settings` lost its read-vs-write scope branching when the catalog
collapsed; both view-only and update calls require `app`.

The nine `auth`-scoped tools form the cross-stack auth-administration surface
(LD-8). `login_attempt_approve`, `login_attempt_block`, `login_attempt_unblock`,
and `login_attempt_purge` require `confirm: "yes"` on every call (two-step
pattern, LD-15 / LD-16). `totp_status` and `auth_audit_log_list` and
`blocked_locations_list` are read-only. Per ADR 0004 (dev-scope
strip-on-release) and the Phase 25 LD-8 lock (auth-scope strip-on-release),
production builds strip both the `dev` and `auth` scopes from `Scopes::ALL` AND
drop the corresponding tools from the MCP registry.

### JSON HTTP endpoints

| Endpoint                                  | Required scope |
| ----------------------------------------- | -------------- |
| `GET /api/projects/:project_id/footages`  | `app`          |
| `POST /api/projects/:project_id/footages` | `app`          |

HTML routes (`/channels`, `/videos`, `/projects`, `/settings`, etc.) are gated
by `Sessions::AuthConcern`: an authenticated cookie session is required, and
unauthenticated requests redirect to `/login` with the intended URL stashed.
Bearer tokens are for surfaces #2 and #3 only.

## 5. Request flow (bearer tokens)

Both Pumas (Web on 3027, MCP on 3028) share the same auth engine
(`Api::TokenAuthenticator`).

```
Bearer header arrives
   │
   ▼
Api::TokenAuthenticator.authenticate(env)
   │
   ├── extract `Authorization: Bearer <plaintext>` header
   ├── digest = HMAC_SHA256(:tokens.pepper, plaintext)
   ├── ApiToken.where(token_digest: digest).take
   ├── verify usable? (not revoked, not expired)
   ├── secure_compare on the digest
   │
   ├── on FAILURE:
   │     env["pito.auth_failed"] = true
   │     ApiAuthThrottle.record_failure(env)
   │     AUTH_AUDIT_LOGGER.info(<reason>)
   │     return Result.failure(<reason>)
   │
   ▼ on SUCCESS
   token.touch_used!                    # update_columns(last_used_at: now)
   Current.token = token
   Current.user  = token.user
   AUTH_AUDIT_LOGGER.info(auth.success)
   return Result.success(token)
   │
   ▼
controller action / MCP tool
   │
   require_scope!(Scopes::APP)          # raises Api::Forbidden if missing
   │
   ▼
work happens
   │
   ▼
response sent → Current.reset (controller after_action / Rack ensure block)
```

### Web Puma (`Api::AuthConcern`)

`Api::AuthConcern` is mixed into every controller under the `Api::` namespace
(today: `Api::FootagesController`). The concern adds:

- `before_action :authenticate_api_token!` — runs the authenticator, raises
  `Api::Unauthorized` on failure.
- `require_scope!(scope)` helper — raises `Api::Forbidden` when the resolved
  token's scopes don't include the required one.

Errors are translated to JSON envelopes by `ApplicationController`:

- `401 {"error": "missing_token" | "invalid_token" | "revoked_token" | "expired_token" | "auth_misconfigured"}`
- `403 {"error": "insufficient_scope", "required": "<scope>"}`

### MCP Puma (`Mcp::RackApp`)

The rack app calls the authenticator inline in `#call`, populates `Current`,
delegates to the streamable HTTP transport, and resets in an `ensure` block.
Per-tool scope enforcement happens inside each tool's `call` method via
`Mcp::ToolAuth.require_scope!`.

## 6. Token lifecycle

```
Settings::TokensController#create   |   bin/rails 'tokens:create[name,...]'
                              │
                              ▼
            ApiToken.generate!(user:, name:, scopes:, expires_at: nil)
              ─ generates SecureRandom.urlsafe_base64(32) plaintext
              ─ stores HMAC-SHA256 digest + last 4 chars
              ─ returns [record, plaintext]
              ─ plaintext is shown once, never re-displayed
                              │
                              ▼
                      ┌──── used ────┐
                      │              │
              Api::TokenAuthenticator.authenticate
                  ─ on success: touch_used! (last_used_at)
                              │
                              ▼
              Settings::TokensController#destroy   |   bin/rails 'tokens:revoke[id]'
                              │
                              ▼
                      record.revoke!  →  revoked_at = Time.current
                      (the row stays in the database forever for audit)
```

There is no automatic expiry sweep yet. `expires_at` is honored on every
`authenticate` call (rejected as `expired_token`), but no background job deletes
or marks expired rows. Phase 12 / 15 add automated expiry handling.

## 7. Bootstrap ceremony

First install on a fresh machine:

1. Set the pepper credential. The pepper is the secret HMAC key the auth engine
   uses to digest plaintext tokens. Without it, no token can be minted or
   authenticated.

   ```bash
   bin/rails credentials:edit
   ```

   Add:

   ```yaml
   tokens:
     pepper: <64-char hex>
   ```

   Generate the value with `openssl rand -hex 32`.

2. Run `bin/setup`. The script pre-flights the pepper credential and exits 1
   with a walkthrough if it's absent. With it set, `db:prepare` runs migrations
   and triggers `db:seed`.

3. The seed mints a default `dev` token (idempotent — second runs are no-ops)
   under development / test only. The scope set mirrors `Scopes::ALL`:

   ```
   dev, app
   ```

   In production (`Rails.env.production?`) the seed skips the dev-token mint
   entirely; production operators mint their own via `/settings/tokens`.

   Plaintext is printed to STDOUT inside a banner. **Save it now** — it cannot
   be retrieved later. If you lose it, revoke it via `/settings/tokens` and mint
   a new one.

4. Configure clients with the captured plaintext:
   - `pito` CLI: `export PITO_API_TOKEN=<plaintext>` (the binary reads it).
   - MCP HTTP transport: include `Authorization: Bearer <plaintext>` on every
     POST to `/mcp`.
   - Claude Mobile: configure the MCP connector to point at `mcp.pitomd.com`
     with the bearer token.

5. Mint additional scoped tokens via `/settings/tokens` (one per client, one per
   scope set). Revoke unused tokens periodically.

## 8. Audit log

Two complementary surfaces capture auth events:

### 8a. `AuthAuditLog` table (privileged actions)

Phase 25 added a durable, queryable audit trail for every privileged auth action
(LD-13). Schema:

```text
AuthAuditLog
  acting_user_id     fk
  source_surface     enum: web / tui / mcp
  action             enum: approve / block / unblock / purge /
                           totp_enroll / totp_disable /
                           backup_code_regenerate /
                           voyage_credentials_updated /
                           password_reset
  target_type        string  (LoginAttempt, BlockedLocation, User)
  target_id          bigint  (0 for collection-scoped purges)
  metadata           jsonb   (per-action shape)
  created_at, updated_at
```

Single entry point:
`Auth::AuditLogger.call(acting_user:, source_surface:, action:, target: | target_type: + target_id:, metadata: {})`.
The service raises on a missing `acting_user`, an unknown surface, or an unknown
action — a controller bug surfaces loudly rather than silently dropping the row.
Callers are expected to wrap the audit-log call inside the same transaction as
the underlying state change so the audit row and the domain mutation
succeed-or-fail together.

The `voyage_credentials_updated` action (Phase 25 F3 extension; survives ADR
0012 because the Voyage indexing toggle is still a Settings-UI-managed write
even after the Voyage API key moved back to credentials) captures
`SettingsController#update_voyage`. The row's `metadata["changed_fields"]` lists
the column NAMES the update mutated; plaintext values are NEVER recorded.

The `password_reset` action (Phase 29 Unit A2 / §1d) captures
`PasswordResetsController#update`. `target: User`,
`metadata: { source_ip:, fingerprint_hash:, factor: "totp" | "backup_code" }`.

The `youtube_credentials_updated` enum value (slot 7) is **reserved** in the
schema for historical rows but removed from `Auth::AuditLogger`'s active
allowlist — the YouTube credentials surface no longer exists in the Settings UI
(ADR 0012; Phase 29 Unit A1).

Never auto-purged. Surfaced at `/settings/security/audit` (web) and via the
`auth_audit_log_list` MCP tool.

### 8b. `log/auth_audit.log` (bearer-token + legacy events)

`config/initializers/auth_audit_logger.rb` configures `AUTH_AUDIT_LOGGER`
against `log/auth_audit.log`. Format: one JSON line per event. This file covers
the bearer-token + Google OAuth callback events that predate `AuthAuditLog`;
`LoginAttempt` rows (§1b) are the durable record for login attempts.

Event types still written to the file:

- `auth.success` — successful bearer authenticate.
- `auth.missing_token` — no Authorization header (or no Bearer prefix).
- `auth.invalid_token` — digest didn't match any row.
- `auth.revoked_token` — row found, but `revoked_at` is set.
- `auth.expired_token` — row found, but `expires_at <= Time.current`.
- `auth.misconfigured` — `:tokens.pepper` credential absent.
- `token.created` — Settings UI minted a new token.
- `token.revoked` — Settings UI revoked a token.
- `session.create.success` — successful login. Payload includes
  `username_attempted` (Phase 29 Unit A2 renamed from `email_attempted`; the
  underlying column on `LoginAttempt` is still named `email_attempted` for
  historical-row continuity but now carries the typed username).
- `session.create.failure` — failed login. Payload includes `username_attempted`
  and a generic failure reason. The reason does NOT distinguish "no such
  username" from "wrong password", "blocked pair", or "rate-limited" — every
  failure branch produces the same outcome shape (Phase 8 F1 fix + Phase 25
  LD-14 + Phase 29 Unit A2 username swap).
- `session.destroy` — logout.
- `youtube_connection.callback.succeeded` — successful Google OAuth callback; a
  `YoutubeConnection` row was minted or refreshed (Phase 9).
- `youtube_connection.callback.failed` — Google OAuth callback failed (OmniAuth
  error, missing `Current.user`, or downstream error during the upsert). Payload
  includes a generic failure reason (Phase 9).
- `youtube_connection.callback.stale_intent` — callback hit
  `/auth/google/callback` without the `youtube_connect` intent in session. Phase
  9 added the event when the dormant sign-in branch was removed; any callback
  without the connect intent is treated as a stale / replayed request and
  redirected to the failure path.

Rotation is host-side (logrotate); out of scope for this phase.

Both Pumas write to the same file. The MCP rack app writes from outside the
Rails request cycle; the controllers write from inside.

## 9. Throttling

`config/initializers/rack_attack.rb` is the single rate-limit surface. It
declares the login throttles described in §1 plus the bearer-token and OAuth
throttles below.

- **`login/ip`** — 5 POSTs / 1 minute on `/login`, `/login/challenge`,
  `/login/totp`, `/login/pending`. See §1.
- **`login/email`** — 10 POSTs / 15 minutes keyed on SHA256(username). Throttle
  name unchanged for ergonomic continuity; the hashed input is the typed
  username after Phase 29 Unit A2's username swap. See §1.
- **`login/backoff`** — exponential backoff via `Auth::BackoffCalculator`. See
  §1.
- **`password/ip`** — 5 POSTs / 1 minute on `POST /password/reset` and
  `PATCH /password/reset`. See §1d.
- **`password/username`** — 10 POSTs / 15 minutes keyed on SHA256(username) on
  `POST /password/reset`. See §1d.
- **Bearer-token throttle** — blocklists IPs that fail bearer authentication
  more than 10 times in 5 minutes; incremented from inside
  `Api::TokenAuthenticator` whenever it returns a failure. A blocklisted request
  returns `429 {"error": "too_many_requests"}`. Gates `/api/*` and `/mcp` only.
- **`oauth/token`** — protects Doorkeeper's token-grant endpoint with a JSON 429
  response shape.
- **`SessionThrottle`** (legacy, surviving as defense-in-depth) — blocklists IPs
  that fail login more than 10 times in 5 minutes. Every hit is mirrored to
  `LoginAttempt` via `Auth::RateLimitLogger.call` so the attempt log remains the
  single source of truth.

A `development?`-only safelist on `127.0.0.1` keeps the maintainer's dev
environment usable. Production safelist is implied by the Cloudflare trusted
proxies (§11) — Rack walks `X-Forwarded-For` past the trusted edges so `req.ip`
resolves to the actual client.

## 10. Session token rotation

`Sessions::TokenRotation` (concern at `app/controllers/concerns/sessions/`) is
included by every controller that mutates auth state on the acting session:

- `Login::ApprovalsController`, `Login::BlocksController`
- `Settings::Security::Blocks::UnblockingsController`
- `Settings::Security::Blocks::PurgesController`
- `Settings::Security::Attempts::PurgesController`
- `Settings::Security::TotpsController` (enroll + disable)
- `Settings::Security::TotpBackupCodesController` (regenerate)
- `Login::TotpChallengesController` (on successful 2FA)

`PasswordResetsController#update` (§1d) destroys every session for the user
rather than rotating — a successful reset is a credential-state event that the
existing session must not survive. No rotation, no carry-over; the user re-logs
in fresh.

After the destructive action's audit-log write, the controller calls
`rotate_session_token!` which mints a fresh plaintext token, recomputes the
digest, stamps it on `Current.session`, calls `reset_session`, and writes a new
`pito_session` signed cookie. The session id / user / metadata stay; only the
token bytes rotate. The helper never raises — a rotation failure logs and falls
through so the destructive action remains visible to the operator.

This narrows the window for session fixation: a captured cookie cannot be
replayed after the user has performed any sensitive auth-state action (LD-12).

## 11. Production hardening + Cloudflare trusted proxies

Phase 25 F1 + F2 pinned the production environment to expect Cloudflare in front
of every request:

- **`config.force_ssl = true`** — every HTTP request redirects to HTTPS; HSTS is
  enabled; session + auth cookies are marked `Secure`.
- **`config.assume_ssl = true`** — Rails honors `X-Forwarded-Proto: https` from
  the upstream so `request.ssl?` is `true` even when the proxy-to-Puma hop is
  plaintext over loopback.
- **`config.ssl_options = { redirect: { exclude: → req.path == "/up" } }`** —
  the health-check endpoint is exempt from the redirect.
- **`config.action_dispatch.trusted_proxies`** — hardcoded list of Cloudflare's
  published IPv4 + IPv6 edge CIDRs (manually encoded 2026-05-11) plus the
  loopback addresses. By default Rack walks `X-Forwarded-For` from the right and
  stops at the first IP that is NOT in `trusted_proxies`. With an empty list any
  client could spoof `request.remote_ip` by setting the header themselves,
  defeating the `Rack::Attack` login throttle (LD-11) and any IP-based audit
  logging.

### `CloudflareTrustedProxiesRefresherJob` — drift watchdog

Cloudflare's published edge ranges change rarely but they DO change. A drift
between the pinned list and the advertised ranges means either:

- a legitimate client at a new Cloudflare edge has its `request.remote_ip`
  pinned to the proxy hop (breaking IP-based audit + Rack::Attack), OR
- a removed Cloudflare range still appears in the trusted list (potentially
  trusting an IP Cloudflare no longer owns).

`CloudflareTrustedProxiesRefresherJob` runs weekly via sidekiq-cron (`0 9 * * 1`
— Monday 09:00 UTC). The job:

1. Fetches `https://www.cloudflare.com/ips-v4` and `.../ips-v6` with a 5s open
   timeout / 10s read timeout. Failures log and bail; the next week's run
   retries (a Cloudflare endpoint outage must not crash the cron).
2. Re-parses the pinned list directly out of `config/environments/production.rb`
   (regex scan for CIDR tokens) — no duplicate source of truth.
3. Diffs the two sets. On drift, creates a `Notification` row with
   `kind: :sync_error`, `severity: :warn`,
   `event_type: "cloudflare_trusted_proxies_drift"`, and a `dedup_key` bucketed
   on the UTC date so same-day reruns collapse to one row. The body carries the
   precise lists of added / removed CIDRs so the operator sees exactly what to
   edit.

The fix is **operator-actionable, not auto-fixable**: the trusted list is
compiled into a Rails initializer at boot, so the job CANNOT mutate the runtime
configuration. It surfaces the drift; the operator edits
`config/environments/production.rb` and redeploys.

## 12. Future phase hooks

| Phase    | What it adds                                                                                                                          |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 12 | Hardens auth UI: token expiry automation, session management improvements, multi-user readiness on top of the single-install posture. |
| Phase 26 | TUI 2FA enrollment via paste-the-seed flow (deferred from Phase 25 per LD-9).                                                         |

When a phase touches the auth surface, the `Scopes` module is the place to add
new entries; `Api::AuthConcern` and `Mcp::ToolAuth.require_scope!` are the
gates. For login-security extensions, the locked decisions live in the umbrella
spec at
`docs/plans/beta/25-login-security-and-new-location-approval/specs/01-overview-login-security-and-new-location-approval.md`.
