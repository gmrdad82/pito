# Phase 25 — Overview: Login Security + New-Location Approval Flow

> **Umbrella spec.** This is the narrative root for Phase 25. It states the
> goal, the threat model, the locked decisions, the cross-cutting contracts
> every sub-spec depends on, and the open questions that must be resolved before
> the implementation lanes are dispatched.
>
> Source of truth:
> `docs/notes/2026-05-11-11-04-57-login-security-new-location-approval-2fa.md`
> (Mobile drop) plus autonomous-architect locks captured here.

## Goal

Build a single coherent login-security stack that:

- Logs every login attempt (success / failure / pending / blocked) with
  fingerprint, IP, IP-prefix, geo, and reason.
- Detects "new location" logins as a `(fingerprint_hash, ip_prefix)` tuple never
  previously associated with a successful login on the target user.
- Challenges new-location logins with TOTP 2FA (primary) or "ask for approval"
  notification (fallback when the authenticator app is unavailable).
- Surfaces pending approvals on web, TUI, and MCP; approve / block from any.
- Tracks blocked locations in an auto-block list and short-circuits future
  attempts from blocked pairs.
- Enforces rate limiting per IP and per account with exponential backoff.
- Rotates the session token on successful 2FA.
- Audit-logs every approve / block / unblock / purge / TOTP-enroll /
  TOTP-disable / backup-code-regenerate action separately from the attempt log.
- Returns the same generic "Login failed." message regardless of which step
  failed (wrong password vs. unknown account vs. blocked fingerprint).

The user is about to start filming pito on camera; the login URL goes public the
moment that footage hits YouTube. The stack has to be honest, layered, and
reviewable.

## Threat model (what we're defending against)

- **Address-bar disclosure** — the login URL appears on screen during videos.
  Mitigation: rate limit + new-location challenge + auto-block list.
- **Credential stuffing** — automated reuse of leaked password pairs.
  Mitigation: rate limit, per-account exponential backoff, generic failure copy
  that doesn't leak account existence.
- **Targeted phishing of a captured-on-camera moment** — adversary harvests the
  URL plus visual cues, then attempts manual login. Mitigation: TOTP 2FA on
  new-location attempts; "ask for approval" fallback surfaces an urgent
  notification on every surface; auto-block on `[block the intruder]`.
- **Compromised browser / device** — adversary gains a session token or cookie.
  Mitigation: session token rotation on 2FA, per-session revocation in
  `/settings/sessions` (already shipped Phase 6), audit log on every privileged
  action.
- **Pending-session squatting** — adversary tries to keep a pending session
  alive while phishing the legitimate user. Mitigation: 10-minute hard expiry on
  `approval_required_until`; expired pending sessions can no longer be approved
  (only purged).

Explicitly out of scope: device-binding via OS-level attestation (Passkeys ship
in a future phase), HSM / hardware-key 2FA (deferred), WebAuthn (Phase 26+).

## Locked decisions (cross-cutting contracts)

These bind every sub-spec. Deviations require a new ADR before dispatch.

### LD-1 — `LoginAttempt` schema

```text
LoginAttempt
  id                         pk
  user_id                    fk, nullable (unknown email → nil; still logged)
  email_attempted            citext, nullable (the raw email submitted)
  result                     enum: success / failed / pending_approval / blocked
  ip                         inet
  ip_prefix                  cidr  (/24 IPv4, /64 IPv6)
  geo_city                   string, nullable
  geo_region                 string, nullable
  geo_country                string, nullable (ISO-3166 alpha-2)
  user_agent                 string, raw
  browser                    string, parsed
  os                         string, parsed
  fingerprint_hash           string (SHA256 hex)
  reason                     enum: wrong_password / unknown_account /
                                   new_location_pending / new_location_2fa_passed /
                                   trusted_location_success / blocked_pair /
                                   rate_limited / 2fa_failed / approved_from_web /
                                   approved_from_tui / approved_from_mcp /
                                   blocked_from_web / blocked_from_tui /
                                   blocked_from_mcp / pending_expired
  notification_id            fk, nullable (links to Phase 16 notification)
  approved_by_user_id        fk, nullable (who acted on the pending row)
  resolved_at                timestamp, nullable
  created_at, updated_at     timestamps
```

Never auto-purged. Manual purge only, via `01d` / `01f`.

### LD-2 — Fingerprint composition

`fingerprint_hash = SHA256(UA + Accept + Accept-Language + Accept-Encoding + "screen=" + screen_hint + "lang=" + locale_hint)`.

Inputs:

- `User-Agent` request header.
- `Accept`, `Accept-Language`, `Accept-Encoding` request headers.
- Screen hint:
  `window.screen.width + "x" + window.screen.height + "@" + window.devicePixelRatio`,
  captured by a small Stimulus controller on the login page and POSTed alongside
  email/password.
- Locale hint:
  `Intl.DateTimeFormat().resolvedOptions().timeZone + "/" + navigator.language`.

**Forbidden inputs (privacy-preserving):**

- No canvas fingerprinting.
- No AudioContext fingerprinting.
- No WebGL renderer string.
- No font enumeration.
- No `Battery` / `Network Information` APIs.

Raw inputs are never persisted. Only the hash. The Stimulus controller posts the
screen / locale hints with the form; the server composes and hashes server-side.
This keeps the composition transparent to the user and reviewable from one
place.

### LD-3 — IP-prefix matching

`/24` for IPv4, `/64` for IPv6. Stored as a CIDR string on `LoginAttempt` and
`TrustedLocation` / `BlockedLocation`. The match operation lives in
`Pito::Auth::IpPrefix` (`app/lib/pito/auth/ip_prefix.rb`).

Rationale: residential IPs rotate (especially CG-NAT mobile). Matching on `/24`
keeps a stable household / org boundary; `/64` is the IPv6 analogue.

### LD-4 — Geo enrichment

**Recommendation (locked):** MaxMind GeoLite2 free offline DB. Synchronous
lookup on the auth path. The DB file lives outside the repo (mounted via env var
`PITO_GEOIP_DB_PATH`); `bin/setup` downloads it on first run.

Fallback if the offline lookup is slower than 5 ms or the DB is missing: enqueue
a `LoginAttemptGeoEnrichJob` (Sidekiq) to backfill `geo_*` columns after the row
is created. The auth path proceeds without geo on first hit.

Open question Q-A still flags whether to also support an HTTP geo service as a
secondary option — currently locked to offline-only.

### LD-5 — New-location definition

A login is "new location" iff
`TrustedLocation.where(user_id: u.id, fingerprint_hash: fh, ip_prefix: pp)` has
no rows. On a successful login (whether trusted or new-but-just-trusted), upsert
the row and stamp `last_seen_at`.

### LD-6 — Pending-session state machine

`Session` (existing model from Phase 6) gains:

- `state` enum: `active / pending_approval / expired / revoked` (default
  `active`).
- `approval_required_until` timestamp, nullable.

Transitions:

```text
active                ← created on successful trusted-location login
                      ← created on successful 2FA challenge
                      ← transitioned from pending_approval on approve action
pending_approval      ← created on new-location-correct-password +
                        "ask for approval" path
expired               ← time-based, set by a Sidekiq cron that sweeps
                        approval_required_until < now
revoked               ← user action from /settings/sessions, or
                        block action on the pending session
```

Expired pending sessions cannot transition back to active. The user can purge
them from `01f`'s UI; otherwise they stay in the attempt log indefinitely.

A `SessionPendingApprovalSweeper` Sidekiq cron runs every minute and transitions
expired pending sessions; this keeps the state honest even without user action.

### LD-7 — Notification integration

Phase 16's notifications pipeline is the carrier. New notification:

```text
kind:      login_pending_approval
severity:  urgent
title:     "New-location login pending approval"
body:      "Browser <browser> on <os> at <geo_city>, <geo_country>
            (IP <ip>). Approve if this is you; block otherwise."
actions:   [yeah, it's me]  → POST /login_attempts/:id/approve
           [block the intruder] → POST /login_attempts/:id/block
auto_resolve: on approve or block, notification flips to resolved and
              disappears from the active banner.
```

One notification per pending approval — not per failed attempt. This matches the
channel-diff dedupe pattern. Recommended in open question Q-L; locking here.

### LD-8 — MCP tools

New MCP scope: `auth`. Strictly gated. The `auth` scope is NOT included in the
default Claude-mobile token; the user opts in per-token via the settings/tokens
edit page. The tools:

| Tool                     | Scope | Action                                                                    |
| ------------------------ | ----- | ------------------------------------------------------------------------- |
| `login_attempts_pending` | auth  | List currently-pending approval requests with full detail.                |
| `login_attempts_list`    | auth  | Filterable historical attempts (result, since, IP, fingerprint).          |
| `login_attempt_approve`  | auth  | Approve a pending attempt. Requires `confirm: "yes"`.                     |
| `login_attempt_block`    | auth  | Block a pending attempt + auto-block the pair. Requires `confirm: "yes"`. |
| `login_attempt_unblock`  | auth  | Remove a fingerprint/IP-prefix pair from the auto-block list.             |
| `login_attempt_purge`    | auth  | Bulk-purge by filter. Requires `confirm: "yes"`.                          |

All inputs / outputs use `"yes"` / `"no"` strings at the boundary, per the
project hard rule.

### LD-9 — TOTP 2FA + backup codes

- Library: `rotp` (Ruby TOTP), `rqrcode` (QR code rendering at setup).
- Seed: 32-char base32, stored encrypted at rest via Active Record Encryption on
  `User#totp_seed_encrypted`.
- Backup codes: **10 codes** (recommended; Q-C), 8 chars each (`a-z 0-9`, no
  ambiguous chars), single-use, hashed at rest with `BCrypt`.
- Enrollment surface: `/settings/security/2fa` (web). Show QR + plaintext secret
  once; show backup codes once; require user to confirm a fresh TOTP code before
  activating.
- Challenge surface: `/login/challenge` (web). Same form accepts either a TOTP
  code OR a backup code; backup code consumes (`used_at` stamped).
- Disable: `/settings/security/2fa/disable` (web). Requires fresh TOTP code to
  disable. Audit-logged.

### LD-10 — Auto-block list

```text
BlockedLocation
  id                         pk
  fingerprint_hash           string
  ip_prefix                  cidr
  blocked_at                 timestamp
  blocked_by_user_id         fk
  source_surface             enum: web / tui / mcp
  reason                     text, nullable
  last_attempt_at            timestamp, nullable
  attempt_count              integer, default 0
  unblocked_at               timestamp, nullable (soft-unblock)
  unblocked_by_user_id       fk, nullable
  created_at, updated_at     timestamps
```

A row with `unblocked_at` set is treated as not-blocked at match time, but the
audit trail survives. Hard purge happens via `01f` and `01d`'s purge action.

### LD-11 — Rate limiting

`Rack::Attack` (new initializer `config/initializers/rack_attack.rb`):

- Per IP: 5 attempts / minute on `POST /login`. Excess → 429.
- Per account (keyed by lowercase email param): 10 attempts / 15 minutes. Excess
  → 429.
- Exponential backoff beyond the throttle: backoff window doubles with each
  bucket trip, capped at 1 hour.
- Block list short-circuits before Rack::Attack so blocked-pair attempts log to
  `LoginAttempt` with `result: blocked` rather than being silently rate-limited.

Throttled requests log a `LoginAttempt` row with `reason: rate_limited`.

### LD-12 — Session token rotation on 2FA

On successful 2FA challenge, the controller calls `reset_session` (Rails) and
mints a new session token. The pre-2FA session is destroyed; the new active
session is created in its place. This narrows the window for session fixation.

### LD-13 — Audit log

```text
AuthAuditLog
  id                         pk
  acting_user_id             fk
  source_surface             enum: web / tui / mcp
  action                     enum: approve / block / unblock / purge /
                                   totp_enroll / totp_disable /
                                   backup_code_regenerate / backup_code_used
  target_type                string (LoginAttempt, BlockedLocation, User)
  target_id                  bigint
  metadata                   jsonb (per-action shape)
  created_at, updated_at     timestamps
```

Never auto-purged. Surfaced at `/settings/security/audit` (web) and via
`auth_audit_log_list` MCP tool (covered in `01g`).

### LD-14 — Generic failure copy

Every failed login response (wrong password, unknown account, blocked
fingerprint, rate-limited) returns:

```
Login failed.
```

With HTTP 401 (or 429 for rate limit) and the same flash. No "user not found",
no "wrong password", no "account locked". The internal `LoginAttempt` row
carries the precise reason; the UI does not.

### LD-15 — Yes / no boundary

Every JSON / MCP / form Boolean is `"yes"` / `"no"` at the boundary. Examples:

- MCP `login_attempt_block(confirm: "yes")`.
- Form `2fa_enabled: "yes"` / `"no"` on `/settings/security/2fa`.
- JSON `{"totp_enabled": "yes"}` on settings JSON responses.

Internal storage stays Boolean. Convert at every boundary.

### LD-16 — No JS confirm / alert / prompt

Approve / block / unblock / purge all flow through the existing
`shared/_action_screen.html.erb` framework. Two-step on every destructive
action. The TUI uses its in-TUI confirmation overlay (existing pattern). MCP
uses two-step `confirm: "yes"` on every destructive tool (existing pattern).

### LD-17 — Friendly URLs

Locked URL set:

```text
GET    /login                            login form
POST   /login                            authenticate
GET    /login/challenge                  TOTP form (after correct password,
                                         new-location)
POST   /login/challenge                  submit TOTP / backup code
GET    /login/pending                    "we sent an approval notification"
                                         holding page
GET    /login_attempts/:id/approve       confirmation page (action-screen)
POST   /login_attempts/:id/approve       perform approve
GET    /login_attempts/:id/block         confirmation page (action-screen)
POST   /login_attempts/:id/block         perform block

GET    /settings/security                index pane (2FA status, recent
                                         attempts summary, block list count)
GET    /settings/security/2fa            enroll / status
POST   /settings/security/2fa            enroll submit
GET    /settings/security/2fa/disable    action-screen
POST   /settings/security/2fa/disable    perform disable
GET    /settings/security/2fa/backup_codes  view / regenerate
POST   /settings/security/2fa/backup_codes  regenerate (action-screen)

GET    /settings/security/attempts       paginated attempt log
GET    /settings/security/attempts/:id   detail

GET    /settings/security/blocks         block list
GET    /settings/security/blocks/:id     detail / unblock action
POST   /settings/security/blocks/:id/unblock
POST   /settings/security/blocks/purge   bulk purge by filter (action-screen)

GET    /settings/security/audit          audit log
```

## Cross-stack scope

| Surface | Scope                                                                                |
| ------- | ------------------------------------------------------------------------------------ |
| Web     | All sub-specs in scope. Primary surface for enrollment, settings, approvals.         |
| TUI     | Sub-specs 01a (read), 01b (read), 01c (in-TUI approval overlay), 01f (read), 01g     |
| MCP     | Sub-specs 01a (read), 01b (read), 01c (notif read), 01d (full), 01e (read), 01f, 01g |
| Website | Not in scope.                                                                        |

The TUI does NOT enroll TOTP in this phase. Enrollment is web-only. The TUI
handles the challenge by displaying a status-line prompt that says "enter TOTP
from your authenticator" (or "enter backup code"); the TUI submits the code via
the existing JSON API. See `01e` open questions.

## Spec pyramid (umbrella-level)

Each sub-spec carries its own full pyramid (model + service + job + component +
helper + request + system). At the umbrella level, the cross-cutting integration
spec is:

- `spec/system/login_security_journeys_spec.rb` — end-to-end across web + shim
  drivers for TUI / MCP. Owned by `01g`. Covers:
  - new location → 2FA happy path
  - new location → ask-for-approval → approve from MCP
  - new location → ask-for-approval → block from TUI
  - wrong-block → unblock + purge
  - rate limit trip → recovery after backoff window
  - 2FA disable + re-enroll round trip

## Open questions (resolve before dispatch)

### Q-A — GeoIP data source

Options:

1. MaxMind GeoLite2 free offline DB only (current lock).
2. HTTP geo service (e.g., ipinfo.io, ipapi.co) only — adds outbound dependency
   on the auth path.
3. Both: offline primary, HTTP fallback on miss / staleness.

**Recommendation:** option 1. The auth path stays offline-only; no third party
sees IPs on every login. The async backfill job covers the case where the DB is
missing or out of date.

### Q-B — Fingerprint composition (which signals are stable enough)

Current lock includes: UA, Accept headers, screen hint, locale hint. Open
sub-questions:

- Should `Accept-Encoding` be included? Browsers vary, but the set is small.
  Marginal entropy.
- Should `Sec-Ch-Ua-*` client hints (Chromium) be included? They're more stable
  across UA freezes but Chromium-only.
- Should the timezone hint be year-month-stamped (so DST transitions don't
  rotate the fingerprint)?

**Recommendation:** include `Accept-Encoding`; include `Sec-Ch-Ua-Platform` and
`Sec-Ch-Ua-Mobile` if present; canonicalize timezone to its IANA name only (no
DST stamp). Lock in `01a`.

### Q-C — Backup code count + reuse policy

Options: 8 / 10 / 12 codes. Single-use vs. multi-use.

**Recommendation:** 10 codes, single-use (`used_at` stamped on consumption, row
stays for audit). 1Password's default is 10 for most services; matches user
expectation. Lock in `01e`.

### Q-D — TOTP-lost fallback

If the user loses both their authenticator app AND their backup codes, what's
the recovery path?

Options:

1. No recovery; must restore from DB backup.
2. Email-based reset token (adds email-as-second-factor; weakens the model).
3. Admin override via Rails console.

**Recommendation:** option 3 in this phase. Single-user install; the user has
Rails console access. Document the recovery procedure in `docs/auth.md` as part
of `01e`. Email-based reset is an explicit Theta / multi-user concern.

### Q-E — Auto-block decay

Should blocked pairs expire after N days, or persist forever until manually
purged?

**Recommendation:** persist forever; rely on the `01f` purge UI for cleanup.
Decaying blocks would silently reopen old threats. Document this in `01f`.

### Q-F — TUI approval UX

Options:

1. In-TUI modal overlay (blocks input until approve / block).
2. Status-line prompt with `a` / `b` keystrokes.
3. Both — overlay on the notifications surface, status-line elsewhere.

**Recommendation:** option 1 on the notifications surface (where the user is
already focused on the pending approval), option 2 on every other surface so the
user can act fast without context switch. Lock in `01c`.

### Q-G — Session expiry on suspended pending_approval

When a pending session expires (10 minutes elapsed, no approve / block):

1. Explicit force-logout — destroy the pending session row immediately.
2. Stale-token — leave the row, mark `state: expired`, refuse to upgrade on any
   subsequent action.

**Recommendation:** option 2. The audit trail survives; the pending session
cannot be approved retroactively. Lock in `01b`.

### Q-H — 1Password Connect API vs. plain TOTP

The Mobile note says "Use TOTP standard — 1Password just stores the seed."
Confirmation: no 1Password Connect SDK. Plain `rotp`. 1Password is just one of
many compatible authenticator apps.

**Recommendation:** locked plain TOTP. Confirm in `01e`.

### Q-I — Geo enrichment timing

Synchronous on the auth path (locked) vs. async via Sidekiq.

**Recommendation:** synchronous primary with async fallback when the DB read
takes >5 ms or the file is missing. Already locked in LD-4. Confirm in `01a`.

### Q-J — Pending-approval timeout copy + UX

What does the user see at `/login/pending` while waiting?

**Recommendation:** show a countdown timer ("10 minutes to approve from your
phone / TUI / MCP"), the pending attempt's detail (browser, OS, geo), and a
`[cancel & log out]` link that revokes the pending session immediately. Lock in
`01b`.

### Q-K — Cross-account purge

In `login_attempt_purge` and the web purge action, does the operation scope to
the acting user's rows only, or system-wide?

**Recommendation:** system-wide (single-install + multi-user, per ADR 0003). Any
authenticated user can purge any attempt. Audit-log every purge with the acting
user. Lock in `01d` and `01f`.

### Q-L — Notification dedupe

One notification per pending approval, or one per failed attempt-after- failure?

**Recommendation:** one per pending approval. This matches the channel-diff
dedupe pattern from Phase 16. Failed-but-not-pending attempts (wrong password,
blocked pair) do NOT spawn notifications; they live in the attempt log only.
Lock in LD-7. Confirm in `01c`.

## What this umbrella does NOT decide

- Exact column types per database (delegated to each sub-spec).
- Per-component visual layout details (delegated to each sub-spec; pane
  primitives per project rule).
- Sidekiq queue names / priorities (delegated to each sub-spec).
- Specific test data fixtures (delegated to each sub-spec).

## Reviewer checklist for the umbrella

- [ ] All 17 locked decisions are referenced in at least one sub-spec.
- [ ] All 12 open questions have a recommendation; none are unaddressed.
- [ ] The cross-stack table matches each sub-spec's stated scope.
- [ ] The URL set in LD-17 is reproduced verbatim in the appropriate sub-spec's
      routes section.
- [ ] No JS confirm / alert / prompt is implied anywhere.
- [ ] Yes / no boundary applies at every external boundary in every sub-spec.
- [ ] Friendly URLs are present and unchanged.

## Open questions for master agent

1. Confirm Q-A through Q-L recommendations (or flip any).
2. Confirm phase numbering — `25-login-security-and-new-location-approval` slot
   is the next available; user to confirm against the latest realignment doc.
3. Confirm the `auth` MCP scope is acceptable (new scope; not part of the
   existing `dev` / `app` split). If yes, add to the scope catalog in
   `docs/mcp.md` during `01d`.
4. Confirm rate-limit numbers (5/min IP, 10/15min account). Tune if too tight
   for legitimate use.
5. Confirm 10 backup codes is the right count (vs. 8 or 12).
