# Phase 25 — 01g: Rate Limit + Session Hardening Pass + Cross-Cutting System Specs

> **Sub-spec 01g.** The closing pass. Adds `Rack::Attack`-driven rate limiting
> on the login endpoint (per IP + per account, exponential backoff), tightens
> session token rotation across every privileged action, sweeps Brakeman /
> bundler-audit, and lands the cross-cutting
> `spec/system/login_security_journeys_spec.rb`.
>
> Reads the umbrella spec first. Locked decisions LD-11 / LD-12 / LD-13 / LD-14
> apply directly.

## Goal

By the time this sub-spec ships, the login surface has:

- A per-IP throttle (5 attempts / min) and per-account throttle (10 attempts /
  15 min) via `Rack::Attack`.
- Exponential backoff beyond the throttle bucket, capped at 1 hour.
- Throttled requests logged to `LoginAttempt` with `reason: rate_limited`.
- Session token rotated on every successful 2FA AND on every approve / block /
  unblock / purge action that mutates auth state on the acting session (defense
  in depth).
- A Brakeman + bundler-audit pass that catches any new regressions introduced by
  01a–01f.
- A single cross-cutting system spec
  `spec/system/login_security_journeys_spec.rb` that exercises the full stack
  end-to-end across web (Capybara), TUI (shim driver), and MCP (in-process tool
  calls).

## Files touched

### Initializers

- `config/initializers/rack_attack.rb` — new.
- `config/application.rb` — `config.middleware.use Rack::Attack`.

### Gem additions

- `Gemfile` — `rack-attack`.

### Services

- `app/services/auth/rate_limit_logger.rb` — receives Rack::Attack callbacks,
  writes `LoginAttempt` rows with `reason: rate_limited`.
- `app/services/auth/backoff_calculator.rb` — exponential backoff, capped at 1
  hour, persisted via Redis (TTL on each bucket).

### Controllers

- `app/controllers/sessions_controller.rb` — gains a
  `rescue_from Rack::Attack::Throttled` hook so the user sees the same generic
  `Login failed.` flash (LD-14 — don't leak the rate-limit reason). The internal
  log row carries the precise reason.
- Approve / block / unblock / purge controllers — gain `reset_session` after
  `Auth::AuditLogger.call`, mint new token via the same primitive that the 2FA
  controller uses (LD-12 extension).

### Routes

No new routes. This sub-spec hardens existing ones.

### Documentation

- `docs/auth.md` — adds a "Rate limiting" section, the throttle numbers, the
  backoff behavior, the "where to look in the attempt log" pointer.
- `docs/architecture.md` — adds Rack::Attack to the Web Puma stack diagram if
  needed.
- `docs/decisions/0007-login-security-phase-25-locks.md` — new ADR capturing the
  umbrella's 17 locked decisions as durable history. (This is the
  architecturally significant artifact justifying an ADR per project rule.)

### Specs (spec pyramid)

#### Service specs

- `spec/services/auth/rate_limit_logger_spec.rb`
  - happy: Rack::Attack throttle hits → row written with `result: failed`,
    `reason: rate_limited`, IP captured.
  - sad: throttle hits with unknown email → row written with `user_id: nil`,
    `email_attempted` captured.
- `spec/services/auth/backoff_calculator_spec.rb`
  - happy: first trip → 1 min, second → 2 min, ..., capped at 60 min.
  - happy: bucket TTL resets after the window.
  - sad: missing Redis → fail-open with a logged warning (don't deadlock the
    auth path).

#### Request specs

- `spec/requests/sessions_rate_limit_spec.rb`
  - happy: 5 attempts within 1 minute from one IP → 6th returns 429,
    LoginAttempt row written.
  - happy: 6th attempt is generic `Login failed.` flash (no rate- limit leak).
  - happy: per-account: 10 attempts on `me@example.com` within 15 min →
    11th 429.
  - edge: alternating IPs against same email → per-account bucket trips before
    per-IP.
  - edge: exponential backoff — after first 429, next allowed attempt is 1 min
    away; after second consecutive 429, 2 min; etc.
  - edge: backoff window expires → bucket resets.
  - flaw: a successful login resets the per-account bucket immediately (so a
    legitimate user who typo'd a few times is not locked out indefinitely).

#### Initializer spec

- `spec/initializers/rack_attack_spec.rb`
  - throttle definitions exist with the correct keys and limits.
  - allowlist for 127.0.0.1 in development only (NOT in production or test).

#### Cross-cutting system spec

- `spec/system/login_security_journeys_spec.rb` — Capybara-driven, plus
  in-process drivers for TUI and MCP. Covers:

  **Journey A — Trusted-location happy path:**
  1. User signs in from a trusted browser.
  2. `LoginAttempt` row with
     `result: success, reason: trusted_location_success`.
  3. Redirect to root; session active.

  **Journey B — New-location → 2FA → trusted:**
  1. User enrolls 2FA from web (precondition; helper).
  2. User logs out, re-opens with a different fingerprint (helper).
  3. Correct password → `/login/challenge` → `[enter 2FA]` → correct TOTP →
     activated.
  4. `LoginAttempt` row with `reason: new_location_2fa_passed`.
  5. `TrustedLocation` row exists for the new pair.
  6. Session token rotated (cookie differs from pre-auth marker).

  **Journey C — New-location → ask-for-approval → approve from MCP:**
  1. User logs in from a new fingerprint, picks `[ask for approval]`.
  2. Pending session created; notification dispatched.
  3. From the existing trusted session, call `login_attempt_approve` via MCP
     with `confirm: "yes"`.
  4. Pending → active; trusted-location upserted; notification resolved; audit
     logged.
  5. The browser at `/login/pending` advances to root on its next poll.

  **Journey D — New-location → ask-for-approval → block from TUI:**
  1. Same pending setup as C.
  2. From the TUI notifications surface, press `b` → confirm overlay → block.
  3. Pending → revoked; BlockedLocation created; notification resolved; audit
     logged.
  4. A subsequent login attempt from the same pair short-circuits to
     `result: blocked`.

  **Journey E — Wrong block → unblock → recover:**
  1. Block a pair (as in D).
  2. From web /settings/security/blocks/:id/unblock → confirm → unblocked.
  3. A login attempt from the same pair no longer short-circuits; it routes to
     `/login/challenge` again as a new location.

  **Journey F — Rate limit trip → backoff → recovery:**
  1. 6 fast failed attempts from one IP → 6th returns 429 (generic copy).
  2. Wait 1 min → next attempt allowed.
  3. Trip again → 429, backoff doubles to 2 min.
  4. Wait 2 min → recover.

  **Journey G — 2FA disable round trip:**
  1. User disables 2FA via /settings/security/2fa/disable (with fresh TOTP
     code).
  2. Re-enroll → new seed + new backup codes.
  3. Audit log captures both events.

  **Journey H — Purge cycle:**
  1. After accumulating ~20 attempts, run a web purge.
  2. After accumulating blocked rows, run an MCP purge with
     `auth_audit_log_list` confirming the action.

  System spec uses `js: true` Capybara for the web steps, an in-process Ratatui
  driver helper for TUI steps, and direct MCP tool calls (the existing pattern)
  for the MCP steps.

#### Security gate

- Brakeman run on the post-`01f` codebase → clean, exceptions documented in
  `docs/security.md`.
- bundler-audit run → clean.
- `rack-attack` does NOT introduce new advisories.

## Service decomposition

```
Rack::Attack
  ├── throttle "login/ip"
  │     5 reqs / min keyed on req.ip; only POST /login
  ├── throttle "login/email"
  │     10 reqs / 15 min keyed on params[:email].downcase
  ├── throttle "login/backoff"
  │     dynamic limit driven by Auth::BackoffCalculator
  └── on throttled request:
      Auth::RateLimitLogger.call(request:)
      → LoginAttempt(result: :failed, reason: :rate_limited)

SessionsController#create  (existing, gains)
  └── rescue_from Rack::Attack::Throttled
      → render :new, alert: "Login failed."  (LD-14)

ApprovalsController / BlocksController / UnblockingsController /
PurgesController (existing, gains)
  └── after AuditLogger:
      reset_session
      mint new session token
```

## Acceptance

- [ ] `rack-attack` gem added.
- [ ] `config/initializers/rack_attack.rb` defines per-IP, per- account, and
      backoff throttles on POST /login (and POST /login/challenge, /login/totp,
      /login/pending/cancel).
- [ ] `Auth::RateLimitLogger` writes `LoginAttempt` rows on every throttle hit.
- [ ] `Auth::BackoffCalculator` doubles per consecutive trip, capped at 60 min,
      TTL'd in Redis.
- [ ] Successful login resets the per-account bucket.
- [ ] Rate-limited responses surface the generic `Login failed.` flash (LD-14).
- [ ] Approve / block / unblock / purge controllers rotate the session token
      after the action.
- [ ] `docs/auth.md` documents the rate limits + the recovery behavior.
- [ ] ADR `docs/decisions/0007-login-security-phase-25-locks.md` created,
      mirroring the umbrella's 17 locked decisions.
- [ ] Cross-cutting system spec `spec/system/login_security_journeys_spec.rb`
      covers all eight journeys (A–H).
- [ ] Brakeman clean (or documented exceptions).
- [ ] bundler-audit clean (or documented exceptions).
- [ ] Dependabot alerts triaged.
- [ ] No JS confirm / alert / prompt in any of the new surfaces.
- [ ] Yes / no boundary preserved on all JSON / MCP / form fields.
- [ ] Friendly URLs preserved.
- [ ] Full RSpec green at suite count.

## Manual test recipe

1. `git pull --rebase`, `bundle install`, `bin/dev`.
2. Open an incognito window. Submit 6 wrong passwords rapidly → 6th gets
   `Login failed.` with the SAME copy as the first five. Internally,
   /settings/security/attempts shows the 6th row with `reason: rate_limited`.
3. Wait 1 minute. One more attempt → routes normally.
4. Try the per-account throttle: 11 attempts on `you@example.com` from rotating
   IPs (use curl with `-H "X-Forwarded-For: ..."` if `Rack::Attack` is
   configured to trust it in dev) within 15 minutes → 11th rate-limited.
5. Approve a pending session from web → confirm session cookie changed before
   vs. after the action (rotation).
6. Run Brakeman: `bundle exec brakeman -A` → clean.
7. Run bundler-audit: `bundle exec bundle-audit check --update` → clean.
8. Run the full system spec:
   `bundle exec rspec spec/system/login_security_journeys_spec.rb` → 8 journeys
   green.
9. Teardown: optional `Redis.flushdb` on `pito-redis-data` to clear throttle
   buckets if iterating.

## Cross-stack scope

| Surface | Status                                                      |
| ------- | ----------------------------------------------------------- |
| Rails   | In scope (rate limit + token rotation + ADR + system spec). |
| TUI     | System-spec driver only; no new TUI surfaces.               |
| MCP     | System-spec driver via tool calls; no new tools.            |
| Website | Out of scope.                                               |

## Open questions

- New: should the rate-limit allowlist include the Cloudflare tunnel IP range
  (production) so legitimate traffic isn't accidentally throttled? Recommend:
  allowlist Cloudflare's published IP set in production; localhost in
  development. Lock here.
- New: should the rate-limit numbers be exposed via an `AppSetting` row for
  tuning without redeploy? Recommend yes; add three columns:
  `login_throttle_per_ip`, `login_throttle_per_account`,
  `login_backoff_cap_minutes`. Confirm with master agent before dispatch.
- New: should the per-account throttle key be the email (Q-K precedent leaks
  account existence in timing) OR a hashed email (`Digest::SHA256`)? Recommend
  hashed email; document the trade-off.
- New: do we want to alert (via Phase 16 notifications) on a significant
  rate-limit trip (e.g., > 50 throttled requests in 1 hour)? Recommend yes;
  opens a "security event" notification kind in a Phase 25.5 follow-up. Out of
  scope here.
- New: system-spec drivers for TUI — do we already have a Ratatui test harness
  in `extras/cli`? If not, this sub-spec adds one under
  `extras/cli/tests/security_journey_helper.rs`. Confirm current state of
  `extras/cli/tests/` before dispatching.
