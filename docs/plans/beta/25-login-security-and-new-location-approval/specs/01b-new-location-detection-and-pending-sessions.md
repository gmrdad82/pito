# Phase 25 — 01b: New-Location Detection + Pending Sessions

> **Sub-spec 01b.** Builds on `01a`. Introduces the `TrustedLocation` behavior
> (upserts), the new-location decision, and the `pending_approval` session state
> with a 10-minute hard expiry.
>
> Reads the umbrella spec first. Locked decisions LD-5 / LD-6 / LD-15 / LD-17
> apply directly. Open questions Q-G and Q-J resolve here.

## Goal

After `01a` logs every attempt, this sub-spec teaches the system to distinguish
trusted locations from new locations. On a correct-password login from a new
location, the user gets a choice:

- `[enter 2FA]` — the 2FA challenge surface (built in `01e`; stub link here).
- `[ask for approval]` — creates a `Notification` (built in `01c`; stub here),
  holds the session in `pending_approval` state for 10 minutes.

Once `01b` ships, the system has the state machine in place. `01c` and `01e`
then wire up the two challenge paths.

## Files touched

### Migrations

- `db/migrate/<ts>_add_state_to_sessions.rb` — `state` enum (active /
  pending_approval / expired / revoked) + `approval_required_until` timestamp on
  the existing `sessions` table.
- `db/migrate/<ts>_add_session_id_to_login_attempts.rb` — nullable FK so an
  attempt row can link back to the session it spawned.

### Models

- `app/models/session.rb` — gains `enum :state, ...`, scope `active`, scope
  `pending`, scope `expired_pending`, method `transition_to_active!`, method
  `expire_if_overdue!`.
- `app/models/trusted_location.rb` — gains
  `.touch_for(user:, fingerprint_hash:, ip_prefix:)` class method (upsert +
  stamp `last_seen_at`).
- `app/models/user.rb` — gains `def trusted_location?(fingerprint:, ip_prefix:)`
  and `def has_pending_session?`.

### Services

- `app/services/auth/new_location_detector.rb` — pure decision. Given user +
  fingerprint + ip_prefix, returns `:trusted` / `:new_location` /
  `:blocked_pair`.
- `app/services/auth/session_pending_approver.rb` — creates a pending session
  row (state = pending_approval, expiry +10 min); returns the row.
- `app/services/auth/session_activator.rb` — flips a pending session to active
  OR creates a fresh active session for a trusted-location login. Calls
  `reset_session` + mints a new token (LD-12 contract; full rotation lives in
  `01e`'s 2FA-success path).
- `app/services/auth/pending_session_expirer.rb` — finds expired pending
  sessions, transitions them to `expired`, optionally logs an attempt row with
  `reason: pending_expired`.

### Jobs

- `app/jobs/session_pending_approval_sweeper_job.rb` — Sidekiq cron, runs every
  1 minute, calls `Auth::PendingSessionExpirer.call`.

### Controllers

- `app/controllers/sessions_controller.rb` — refactored to route to three
  terminal states post-password-check:
  - trusted location → activate + redirect to root.
  - new location → render `/login/challenge` (stub action in this sub-spec;
    `01e` fills the TOTP form, `01c` fills the approval body).
  - blocked pair → render `Login failed.` (LD-14 unchanged).
- `app/controllers/login/challenges_controller.rb` — new. `show` renders the
  choice surface with two bracketed links (`[enter 2FA]` /
  `[ask for approval]`). `create` accepts a `challenge_path` param and routes to
  `01e`'s TOTP form OR creates the pending row via
  `Auth::SessionPendingApprover` and redirects to `/login/pending`.
- `app/controllers/login/pendings_controller.rb` — new. `show` renders the
  holding page (countdown + attempt detail + `[cancel & log out]`).

### Views

- `app/views/login/challenges/show.html.erb` — choice surface, bracketed links
  per LD-17.
- `app/views/login/pendings/show.html.erb` — countdown + attempt detail.
- `app/views/login/_attempt_detail.html.erb` — partial shared with the
  notification card in `01c`.

### Stimulus

- `app/javascript/controllers/pending_countdown_controller.js` — client-side
  countdown timer; reads `data-pending-countdown-deadline-value` (ISO 8601),
  renders `MM:SS`; reloads page when zero.

### Components

- `app/components/login_challenge_choice_component.rb` / `_component.html.erb` —
  renders the two bracketed-link choices in the locked design.

### Routes

```
get  "login/challenge", to: "login/challenges#show",    as: :login_challenge
post "login/challenge", to: "login/challenges#create"
get  "login/pending",   to: "login/pendings#show",      as: :login_pending
```

### MCP

- `app/mcp/tools/login_attempts_pending.rb` — read-only scaffold; the approve /
  block actions live in `01d`. Returns rows whose attempt row carries
  `result: pending_approval` AND whose session is still within the 10-minute
  window. Yes / no boundary on every Boolean.

### TUI

- `extras/cli/src/security/pending.rs` — pending-approval list view.
- `extras/cli/src/security/api.rs` — gains `pending()` fetcher.
- The TUI's approve / block keystrokes are added in `01c` (the notifications
  surface owns the action UX).

### Specs (spec pyramid)

#### Model specs

- `spec/models/session_spec.rb` (existing, gains)
  - state enum mapping + default `:active`.
  - `#expire_if_overdue!` flips pending → expired iff past
    `approval_required_until`.
  - `#transition_to_active!` raises if state is `expired` or `revoked`.
  - `scope :pending` returns pending_approval rows only.
  - `scope :expired_pending` returns pending_approval rows past expiry.
- `spec/models/trusted_location_spec.rb` (existing, gains)
  - `.touch_for` creates on first call, updates `last_seen_at` on repeat.
  - `.touch_for` is idempotent on a unique
    `(user_id, fingerprint_hash, ip_prefix)` index.
- `spec/models/user_spec.rb` (existing, gains)
  - `#trusted_location?` returns true iff a trusted row exists.
  - `#has_pending_session?` returns true iff a pending session is within its
    expiry window.

#### Service specs

- `spec/services/auth/new_location_detector_spec.rb`
  - happy: trusted pair → `:trusted`.
  - happy: untrusted pair → `:new_location`.
  - sad: blocked pair → `:blocked_pair` (precedence over new_location).
  - edge: user with zero trusted locations + first login → still `:new_location`
    (first login is always new; promoted to trusted on success).
- `spec/services/auth/session_pending_approver_spec.rb`
  - happy: creates a session row with state pending_approval,
    `approval_required_until` set to 10 min from now,
    `login_attempt.result == :pending_approval`,
    `login_attempt.reason == :new_location_pending`.
  - sad: user has 3+ active pending sessions → rejects with `TooManyPending`
    error (anti-spam guard; document the threshold here).
  - edge: clock-skew tolerance — `approval_required_until` is measured
    server-side, no client trust.
- `spec/services/auth/session_activator_spec.rb`
  - happy: trusted login → creates fresh active session, calls `reset_session`,
    writes attempt with `reason: trusted_location_success`.
  - happy: pending → active transition (post-approve) — covered in `01c`.
  - sad: expired pending → raises; never activates.
  - sad: revoked pending → raises.
- `spec/services/auth/pending_session_expirer_spec.rb`
  - happy: pending past expiry → flipped to `expired`, attempt row written with
    `reason: pending_expired`.
  - happy: pending within expiry → untouched.
  - edge: already-expired row → no-op.
  - edge: bulk run with 100 rows → all transitioned in one pass.

#### Job spec

- `spec/jobs/session_pending_approval_sweeper_job_spec.rb`
  - happy: sweeper transitions expired rows.
  - happy: scheduled at 1-min cron (`sidekiq-cron` config).
  - sad: when the expirer raises on one row, the rest still process.

#### Request specs

- `spec/requests/sessions_spec.rb` (existing, gains)
  - POST /login with correct password from a trusted location → 302 to root,
    fresh session, `LoginAttempt#result = :success`,
    `reason = :trusted_location_success`.
  - POST /login with correct password from a new location → 302 to
    `/login/challenge`, no session yet.
  - POST /login with blocked pair → 401 with generic flash; no
    `/login/challenge` redirect.
- `spec/requests/login/challenges_spec.rb`
  - GET /login/challenge without a pre-auth marker → 302 to /login.
  - GET /login/challenge with a pre-auth marker → 200, two bracketed-link
    choices visible (`[enter 2FA]`, `[ask for approval]`).
  - POST /login/challenge with `challenge_path: "approval"` → creates pending
    session, redirects to /login/pending.
  - POST with `challenge_path: "totp"` → redirects to /login/totp (stub route
    resolves to `01e`'s controller; here it's a placeholder).
  - POST with `challenge_path: "<unknown>"` → 422.
- `spec/requests/login/pendings_spec.rb`
  - GET /login/pending with a pending session → 200, shows attempt detail +
    countdown.
  - GET when pending has expired → 302 to /login with generic copy.
  - GET when not pending → 302 to /login.
- `spec/requests/settings/security_spec.rb` (existing, gains)
  - Index pane shows count of trusted locations + count of pending sessions.

#### MCP tool spec

- `spec/mcp/tools/login_attempts_pending_spec.rb`
  - happy: returns active pending rows only (not expired).
  - sad: without `auth` scope → scope error (stub here; gated in `01d`).
  - boundary: yes/no Booleans (`"is_expired": "no"`).

#### Component spec

- `spec/components/login_challenge_choice_component_spec.rb`
  - renders the two bracketed-link choices; correct hrefs.
  - bracketed-link format `[label]` (no inner spaces).

#### System spec

Deferred to `01c` (end-to-end pending flow needs the notification surface). The
state machine alone is exercised via request specs.

#### Routing spec

- `spec/routing/login_challenges_routing_spec.rb` — confirms the new routes
  resolve.

## Migration shape (illustrative)

```ruby
class AddStateToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :state, :integer, null: false, default: 0
    add_column :sessions, :approval_required_until, :datetime
    add_index :sessions, :state
    add_index :sessions, :approval_required_until
  end
end
```

## Service decomposition

```
SessionsController#create
  ├── Auth::AttemptLogger           (from 01a, every path)
  ├── Auth::NewLocationDetector     (this sub-spec)
  ├── branches:
  │     :trusted     → Auth::SessionActivator
  │     :new_location→ redirect /login/challenge (pre-auth marker set)
  │     :blocked_pair→ render generic Login failed
  └── Auth::AttemptLogger (terminal log row written)

Login::ChallengesController#create
  ├── if challenge_path == "approval"
  │     → Auth::SessionPendingApprover  (this sub-spec)
  │     → Notifications::Pipeline       (01c)
  │     → redirect /login/pending
  └── if challenge_path == "totp"
        → redirect /login/totp (01e)

SessionPendingApprovalSweeperJob (cron, every minute)
  └── Auth::PendingSessionExpirer  (this sub-spec)
```

## Acceptance

- [ ] `sessions.state` and `sessions.approval_required_until` migrated.
- [ ] `login_attempts.session_id` migrated (nullable FK).
- [ ] `Session` model has the four-state enum + scopes + transition methods.
- [ ] `TrustedLocation.touch_for` upserts atomically on the unique index.
- [ ] `Auth::NewLocationDetector` returns `:trusted` / `:new_location` /
      `:blocked_pair` with `:blocked_pair` precedence.
- [ ] `Auth::SessionPendingApprover` writes the pending session + links the
      attempt + bounds pending count per user to prevent spam.
- [ ] `Auth::SessionActivator` is the only surface that mints active sessions;
      calls `reset_session`.
- [ ] `Auth::PendingSessionExpirer` runs idempotently and writes a
      `pending_expired` attempt row.
- [ ] `SessionPendingApprovalSweeperJob` is scheduled via `sidekiq-cron` every
      minute.
- [ ] POST /login routes to one of three terminal states; trusted is the only
      state that mints a session in this sub-spec.
- [ ] GET /login/challenge renders two bracketed-link choices.
- [ ] POST /login/challenge accepts approval-path and creates a pending row.
- [ ] GET /login/pending shows attempt detail + countdown.
- [ ] Pending sessions expire at 10 minutes server-side, regardless of client
      behavior.
- [ ] No JS confirm / alert / prompt.
- [ ] Yes / no boundary on JSON / MCP fields.
- [ ] Friendly URLs locked.
- [ ] `login_attempts_pending` MCP read scaffold returns pending rows.
- [ ] TUI `g s p` opens the pending list (read-only here; actions in `01c`).
- [ ] Full RSpec green; Brakeman clean; bundler-audit clean.

## Manual test recipe

1. `git pull --rebase`, `bin/dev`.
2. Log in successfully from your current browser. Browse to `/settings/security`
   — note "trusted locations: 1, pending: 0".
3. Log out. Open a Chrome → Firefox switch (or different incognito) so the
   fingerprint changes. Submit the correct password.
4. Expect redirect to `/login/challenge`. Two bracketed-link choices.
5. Click `[ask for approval]`. Expect redirect to `/login/pending` with a 10:00
   countdown.
6. In the trusted browser, visit `/settings/security` → count shows "pending:
   1".
7. Open the TUI in a separate terminal → `g s p` lists the pending row.
8. From the trusted browser, MCP-list pending via the dev harness → the row is
   there.
9. Wait 10 minutes (or `Timecop.travel` if testing). Refresh `/login/pending` →
   expired notice + redirect to /login.
10. Verify the attempt log shows `pending_expired` for that row.
11. Sidekiq dashboard: confirm the sweeper cron is scheduled at `* * * * *`.
12. Teardown: `Session.pending.destroy_all` from console.

## Cross-stack scope

| Surface | Status                                                       |
| ------- | ------------------------------------------------------------ |
| Rails   | In scope (full).                                             |
| TUI     | Pending list read-only under `g s p`; actions land in `01c`. |
| MCP     | `login_attempts_pending` read scaffold; actions in `01d`.    |
| Website | Out of scope.                                                |

## Open questions

- **Q-G** (session expiry on suspended pending): locked to option 2
  (stale-token; row stays, state flips to expired). Confirm.
- **Q-J** (pending countdown copy + UX): show countdown + attempt detail +
  `[cancel & log out]` link. Lock here.
- New: pending-spam guard — cap at 3 active pending sessions per user. Above
  that, the third attempt's POST /login/challenge returns 429. Confirm
  threshold.
- New: should the pending list be paginated in TUI / MCP? Cap at 50; expected
  size is single digits.
- New: should `Session#state == :expired` be cleaned up after N days? Recommend
  keeping for audit; the row is cheap.
