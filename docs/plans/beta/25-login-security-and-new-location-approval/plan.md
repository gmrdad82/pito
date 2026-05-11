# Phase 25 — Login Security + New-Location Approval Flow

> **Status:** scaffolded by `pito-architect-spec` on 2026-05-10. Source of truth
> for scope:
> `docs/notes/2026-05-11-11-04-57-login-security-new-location-approval-2fa.md`
> (Mobile drop) plus the autonomous architect locks enumerated in the umbrella
> spec.
>
> This phase introduces login-attempt logging, fingerprinting, new-location
> detection with explicit approval, TOTP 2FA with backup codes, an auto-block
> list with purge UI, rate limiting, and session hardening — across web, TUI,
> and MCP.

## Why this phase exists

The user is about to start filming pito on camera. The browser address bar will
be visible, the login URL will be public, and the threat model widens
accordingly. Phase 25 raises defense-in-depth around authentication so that even
with a publicly-known URL and a captured-by-camera login affordance, the account
stays defensible: every attempt is logged + fingerprinted, every new-location
login is challenged (TOTP 2FA primary, "ask for approval" via notification
fallback), and the user can approve / block / unblock / purge attempts from any
surface (web, TUI, MCP).

This is on-camera infrastructure. It has to be right, exhaustively spec'd, and
reviewable end-to-end before any of it ships.

## Sub-spec sequencing

Each sub-spec maps to one dispatchable lane. Lanes ship in order; later lanes
build on earlier ones. Master agent dispatches one (or several parallel where
the file scope is disjoint) per cycle. The umbrella spec (`01-overview`)
narrates the cross-cutting decisions; the seven implementation sub-specs (`01a`
through `01g`) each carry full model/migration/service/job/spec-pyramid
coverage.

- [ ] **01 — Overview (umbrella)** —
      `specs/01-overview-login-security-and-new-location-approval.md`
- [x] **01a — Attempt logging + fingerprinting** —
      `specs/01a-attempt-logging-and-fingerprinting.md`
- [x] **01b — New-location detection + pending sessions** —
      `specs/01b-new-location-detection-and-pending-sessions.md`
- [ ] **01c — Notifications integration (web + TUI)** —
      `specs/01c-notifications-integration.md`
- [x] **01d — MCP tools (pending / list / approve / block / unblock / purge)** —
      `specs/01d-mcp-tools-pending-approve-block-purge.md`
- [ ] **01e — TOTP 2FA + backup codes** —
      `specs/01e-totp-2fa-integration-with-backup-codes.md`
- [ ] **01f — Auto-block list + purge UI** —
      `specs/01f-auto-block-list-and-purge-ui.md`
- [ ] **01g — Rate limiting + session hardening pass + cross-cutting system
      specs** — `specs/01g-rate-limit-and-session-hardening-pass.md`

The eighth Mobile-suggested step ("end-to-end system specs") is folded into the
relevant sub-spec's "Spec pyramid → System" section and a cross-cutting
`spec/system/login_security_journeys_spec.rb` introduced by `01g`. The journeys
covered there exercise the full stack end-to-end across web, TUI shim, and MCP
shim.

## Locked decisions (apply across every sub-spec)

These were established in the source-of-truth Mobile drop plus the autonomous
architect locks. Every sub-spec must respect them; deviations need a fresh ADR
before the implementation lane is dispatched.

1. **LoginAttempt schema** —
   `timestamp, result (enum: success / failed / pending_approval / blocked), ip, ip_prefix, geo_city, geo_region, geo_country, user_agent, browser, os, fingerprint_hash, reason (enum), notification_id (nullable FK), created_at, updated_at`.
2. **Fingerprint hash composition** — SHA256 over
   `UA + accept headers + screen / locale hints`. Stored hashed; raw inputs
   never persisted. Privacy-preserving: no canvas, no AudioContext, no WebGL
   fingerprinting.
3. **IP-prefix matching** — `/24` for IPv4, `/64` for IPv6. Stored as
   `ip_prefix` (CIDR string) on the same row.
4. **Geo enrichment** — MaxMind GeoLite2 free offline DB (recommendation; see
   open question Q-A). Sync enrichment on the auth path; async backfill via
   Sidekiq is an explicit fallback if the offline lookup ever takes >5 ms.
5. **New-location definition** — `(fingerprint_hash, ip_prefix)` combo has never
   had a successful login on this user before. Stored as
   `TrustedLocation(user_id, fingerprint_hash, ip_prefix, first_seen_at, last_seen_at)`
   rows.
6. **Pending-session state machine** — `sessions.state` enum
   `(active, pending_approval, expired, revoked)` plus `approval_required_until`
   timestamp. 10-minute expiry; expired pending sessions cannot be approved.
7. **Notification integration** — uses the Phase 16 pipeline. Severity `urgent`,
   kind `login_pending_approval`. Actions `[yeah, it's me]` (approve) /
   `[block the intruder]` (block). Bracketed-link convention per project rule.
8. **MCP tools** — `login_attempts_pending`, `login_attempts_list`,
   `login_attempt_approve`, `login_attempt_block`, `login_attempt_unblock`,
   `login_attempt_purge`. All gated on the `auth` MCP scope (new scope; see
   `01d`).
9. **TOTP 2FA** — `rotp` gem, 1Password-compatible TOTP seed. Seed stored
   encrypted at rest via Active Record Encryption. Backup codes generated and
   shown once at setup, hashed at rest, single-use.
10. **Auto-block list** —
    `BlockedLocation(fingerprint_hash, ip_prefix, blocked_at, blocked_by_user_id, reason)`.
    Future attempts from a blocked pair short-circuit to `result: blocked`
    without password check.
11. **Rate limiting** — Rack::Attack: per-IP 5 attempts / min, per-account 10
    attempts / 15 min, exponential backoff thereafter.
12. **Session token rotation on successful 2FA** — `reset_session` + new token
    mint on successful 2FA challenge.
13. **Audit log** —
    `AuthAuditLog(timestamp, acting_user_id, source_surface (enum: web / tui / mcp), action (enum: approve / block / unblock / purge / totp_enroll / totp_disable / backup_code_regenerate), target_id, target_type, metadata jsonb)`.
    Distinct from `LoginAttempt`; never auto-pruned.
14. **Generic failure copy** — Wrong password, unknown account, and blocked
    fingerprint all return the same `Login failed.` copy. Do not leak which step
    failed.
15. **Yes / no boundary** — Every JSON / MCP / form Boolean serializes as
    `"yes"` / `"no"` at the wire (per project hard rule). Internal storage stays
    Boolean. Convert at every boundary.
16. **No JS confirm / alert / prompt** anywhere — approval / block / purge /
    unblock destructive flows go through the existing action-screen framework
    (`shared/_action_screen.html.erb` + `Confirmable` + `DeletionsController` /
    a new `LoginAttempts::*Controller` family).
17. **Friendly URLs preserved** — `/login`, `/login/challenge`,
    `/login/approve/:token`, `/settings/security`, `/settings/security/2fa/*`,
    `/settings/security/blocks/*`, `/settings/security/attempts/*`. URLs are
    locked once introduced.

## Cross-stack scope (per sub-spec)

| Sub-spec | Rails web | TUI       | MCP       |
| -------- | --------- | --------- | --------- |
| 01a      | in scope  | read-only | read-only |
| 01b      | in scope  | in scope  | in scope  |
| 01c      | in scope  | in scope  | in scope  |
| 01d      | n/a       | n/a       | in scope  |
| 01e      | in scope  | n/a (P2)  | in scope  |
| 01f      | in scope  | read-only | in scope  |
| 01g      | in scope  | in scope  | in scope  |

"n/a (P2)" means deferred to a follow-up phase. The TUI does not enroll TOTP
directly — enrollment happens on web; the TUI honors the challenge by delegating
to the user's authenticator app via a copy-paste prompt in the in-TUI overlay.
This is called out explicitly in `01e`'s open questions.

## Quality gates

Every sub-spec ends with the standing Beta gates (per `beta.md`):

1. Plan checkbox flipped or moved to `dropped.md` with rationale.
2. Session `log.md` entry summarizing the completed sub-spec.
3. RSpec green on the new code; existing specs unaffected.
4. Brakeman scan clean (exceptions documented).
5. bundler-audit clean (exceptions documented).
6. Dependabot alerts triaged.
7. Design alignment — `docs/design.md` updated where UI surfaces shift.
8. Manual test instructions live in the session log.
9. User has manually validated before commit.

## Additions / dropped tracking

This phase opens two tracking files when its first additions / drops happen:

- `docs/plans/beta/25-login-security-and-new-location-approval/additions.md`
- `docs/plans/beta/25-login-security-and-new-location-approval/dropped.md`

Neither is created up front — `pito-docs` opens them lazily on first need.

## Phase log

Append-only at:
`docs/plans/beta/25-login-security-and-new-location-approval/log.md`.

`pito-docs` opens it after the first sub-spec implementation lands.
