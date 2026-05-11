# Phase 25 — 01c: Notifications Integration (Web + TUI)

> **Sub-spec 01c.** Wires the new-location pending flow into the Phase 16
> notifications pipeline. Surfaces the pending approval on web, TUI, and
> (read-only here) MCP. Implements the approve / block actions through the
> action-screen framework with NO JS confirm / alert / prompt.
>
> Reads the umbrella spec first. Locked decisions LD-7 / LD-13 / LD-15 / LD-16 /
> LD-17 apply directly. Open questions Q-F and Q-L resolve here.

## Goal

When `01b`'s `Auth::SessionPendingApprover` creates a pending row, this sub-spec
hooks it into the Phase 16 notifications pipeline so:

- A single `Notification(kind: login_pending_approval, severity: urgent)` is
  dispatched (dedupe per pending row).
- The notification renders on the web banner, the TUI notifications surface, and
  the MCP `notifications_list` tool (already shipped).
- Two actions are exposed: `[yeah, it's me]` (approve) and
  `[block the intruder]` (block).
- Both actions flow through the existing action-screen framework
  (`shared/_action_screen.html.erb` + `Confirmable`). No JS confirm.
- TUI actions live in a modal overlay on the notifications surface and in a
  status-line prompt elsewhere (Q-F).
- Approve flips the session to `active`, calls `reset_session`, and resolves the
  notification. Block creates a `BlockedLocation` row, flips the session to
  `revoked`, and resolves the notification.
- Every action is audit-logged (LD-13).

## Files touched

### Models

- `app/models/notification.rb` (existing, gains)
  - `kind: login_pending_approval` added to the enum.
  - `severity: urgent` already exists (Phase 16).
  - `belongs_to :login_attempt, optional: true`.
- `app/models/login_attempt.rb` (existing, gains)
  - `has_one :notification` already wired via `notification_id` FK.

### Migrations

- `db/migrate/<ts>_add_login_attempt_to_notifications.rb` — nullable FK so a
  notification can carry the pending-attempt context.
- `db/migrate/<ts>_create_auth_audit_logs.rb` — table per LD-13 (only the
  schema; the rows in this sub-spec are approve / block; other actions land in
  `01e` / `01f`).

### Services

- `app/services/auth/pending_notification_dispatcher.rb` — creates the
  notification, links to the pending attempt + session.
- `app/services/auth/login_attempt_approver.rb` — performs an approve: flips the
  session to active via `Auth::SessionActivator`, upserts `TrustedLocation`,
  resolves the notification, writes a `LoginAttempt` row with
  `reason: approved_from_<surface>`, audit- logs.
- `app/services/auth/login_attempt_blocker.rb` — performs a block: upserts
  `BlockedLocation`, revokes the pending session, resolves the notification,
  writes a `LoginAttempt` row with `reason: blocked_from_<surface>`, audit-logs.
- `app/services/auth/audit_logger.rb` — single entry point that writes
  `AuthAuditLog` rows. Called by every approve / block / unblock / purge /
  TOTP-_ / backup-code-_ service in this phase.

### Controllers

- `app/controllers/login_attempts/approvals_controller.rb` — new. `show` renders
  the action-screen confirmation ("Approve this new-location login?"); `create`
  performs approve. Uses `Confirmable`.
- `app/controllers/login_attempts/blocks_controller.rb` — new. Mirror shape for
  block.
- `app/controllers/login/pendings_controller.rb` (from 01b, gains)
  - `cancel` action — explicit `[cancel & log out]` link → revokes the pending
    session.

### Views

- `app/views/login_attempts/approvals/show.html.erb` — confirmation screen,
  shows attempt detail, `[yeah, it's me]` submit button.
- `app/views/login_attempts/blocks/show.html.erb` — confirmation screen,
  `[block the intruder]` submit button.
- `app/views/notifications/_login_pending_card.html.erb` — partial for the
  notification body rendered in the notifications surface.
- `app/views/shared/_pending_attempt_summary.html.erb` — shared attempt summary
  (browser, OS, geo, IP, fingerprint short) used by the cards, action screens,
  and pending holding page.

### Components

- `app/components/notification_card_component.rb` (existing, gains a branch for
  `kind: login_pending_approval`).
- `app/components/pending_attempt_summary_component.rb` — shared.

### Routes

```
resources :login_attempts, only: [] do
  resource :approval, only: [:show, :create], controller: "login_attempts/approvals"
  resource :block,    only: [:show, :create], controller: "login_attempts/blocks"
end

post "login/pending/cancel", to: "login/pendings#cancel", as: :login_pending_cancel
```

### Notifications pipeline

- `app/services/notifications/pipeline.rb` (existing, gains a registration for
  `login_pending_approval`).
- `app/services/notifications/formatters/in_app/login_pending_approval.rb` —
  formats the notification body for in-app rendering.
- `app/services/notifications/auto_resolver.rb` — gains a hook so that approve /
  block resolve the linked notification.

### TUI

- `extras/cli/src/notifications/login_pending.rs` — new. Renders the pending
  card with `[a] approve` / `[b] block` keystroke hints.
- `extras/cli/src/notifications/overlay.rs` — modal overlay (Q-F option 1) for
  the notifications surface; status-line prompt for other surfaces.
- `extras/cli/src/api/login_attempts.rs` — approve / block client.
- TUI keystrokes:
  - On the notifications surface: `a` → approve overlay, `b` → block overlay.
    Confirm in overlay before action fires (in-TUI two-step pattern).
  - Elsewhere (channels / videos / settings panes): status-line prompt
    `pending approval — [a]pprove [b]lock [l]ater`.

### MCP

- The approve / block tools are scaffolded here as no-ops calling the same
  services. Full scope gating + parameter validation in `01d`.

### Specs (spec pyramid)

#### Model specs

- `spec/models/notification_spec.rb` (existing, gains)
  - `kind: login_pending_approval` enum value.
  - `belongs_to :login_attempt`.
  - `scope :resolved_or_active` returns both when filter is "all".
- `spec/models/auth_audit_log_spec.rb`
  - validations: `acting_user`, `source_surface`, `action`, `target_type`,
    `target_id` presence.
  - source_surface enum (`web` / `tui` / `mcp`).
  - action enum (all LD-13 actions enumerated).

#### Service specs

- `spec/services/auth/pending_notification_dispatcher_spec.rb`
  - happy: creates one notification per pending session (dedupe by
    `login_attempt_id`).
  - sad: pending already has a notification → no-op (idempotent).
  - edge: pending expired between approve call and run → returns a soft error;
    logs the event.
- `spec/services/auth/login_attempt_approver_spec.rb`
  - happy: pending → active session, TrustedLocation upserted, notification
    resolved, audit log written, attempt row marked success.
  - sad: pending expired → raises `PendingExpired`; nothing flips.
  - sad: pending already revoked (someone blocked first) → raises
    `AlreadyResolved`; nothing flips.
  - edge: concurrent approve + block — pessimistic lock on `LoginAttempt`
    ensures one wins; the loser raises.
  - flaw: never trusts request-supplied user; the
    `Auth::Approver.call(user: Current.user, login_attempt:, source:)` contract
    is strict.
- `spec/services/auth/login_attempt_blocker_spec.rb`
  - happy: pending → revoked session, BlockedLocation upserted, notification
    resolved, audit log written, attempt row marked blocked.
  - happy: blocking an already-blocked pair → no duplicate row (unique index on
    `(fingerprint_hash, ip_prefix, unblocked_at IS NULL)`), but a fresh audit
    row.
  - sad: same edge cases as approver.
- `spec/services/auth/audit_logger_spec.rb`
  - happy: writes a row with the right shape, jsonb metadata sealed.
  - sad: missing `acting_user` → raises.
  - sad: invalid `action` → raises.
  - sad: invalid `source_surface` → raises.

#### Request specs

- `spec/requests/login_attempts/approvals_spec.rb`
  - GET show → 200, action-screen with attempt detail.
  - POST create with `confirm: "yes"` → 302, session active, redirect to root.
  - POST without confirm → 422.
  - POST when expired → 422 with generic copy.
  - POST when not signed in → 302 to /login (auth required).
- `spec/requests/login_attempts/blocks_spec.rb`
  - Mirror of approvals.
  - POST → BlockedLocation row created.
  - POST → original pending session revoked.
- `spec/requests/login/pendings_spec.rb` (existing, gains)
  - POST cancel → session revoked, redirect to /login.
- `spec/requests/notifications_spec.rb` (existing, gains)
  - GET /notifications → pending notification renders with two bracketed-link
    actions linking to /login_attempts/:id/approval and
    /login_attempts/:id/block.

#### Component specs

- `spec/components/notification_card_component_spec.rb` (existing, gains)
  - login_pending_approval branch renders the two bracketed-link actions in the
    locked format.
- `spec/components/pending_attempt_summary_component_spec.rb`
  - happy: renders browser / OS / geo / IP / fingerprint short.
  - sad: missing geo → "location unknown".
  - sad: missing UA → "Unknown browser / OS".

#### Helper specs

- `spec/helpers/notifications_helper_spec.rb` (existing, gains tests for the new
  copy strings).

#### MCP tool spec

- `spec/mcp/tools/login_attempt_approve_spec.rb` (scaffold here, full gating in
  `01d`)
  - happy: pending → approve flow, returns yes/no Booleans.
  - sad: missing `confirm: "yes"` → returns the standard two-step-confirm error.

#### System spec

- `spec/system/login_security_journeys_spec.rb` (created in `01g`; this sub-spec
  lists the journeys it will exercise):
  - new-location ask-for-approval → approve from web (this sub-spec).
  - new-location ask-for-approval → block from web (this sub-spec).

#### Routing spec

- `spec/routing/login_attempts_routing_spec.rb` — confirms the approval / block
  routes.

## Migration shape

```ruby
class CreateAuthAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_audit_logs do |t|
      t.references :acting_user, null: false, foreign_key: { to_table: :users }
      t.integer :source_surface, null: false  # enum
      t.integer :action, null: false          # enum
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :auth_audit_logs, [:target_type, :target_id]
    add_index :auth_audit_logs, :created_at
  end
end
```

## Service decomposition

```
Login::PendingsController#show
  └── reads pending session

Notifications::Pipeline (Phase 16)
  └── on pending-approval dispatch:
      → Auth::PendingNotificationDispatcher
          → Notification(kind: login_pending_approval, severity: urgent)

LoginAttempts::ApprovalsController#create
  ├── verify Confirmable
  ├── Auth::LoginAttemptApprover.call(login_attempt:, acting_user:, source: :web)
  │     ├── Auth::SessionActivator   (01b)
  │     ├── TrustedLocation.touch_for
  │     ├── Notification#resolve!
  │     └── Auth::AuditLogger.call(action: :approve, ...)
  └── redirect "/" with flash

LoginAttempts::BlocksController#create
  ├── verify Confirmable
  ├── Auth::LoginAttemptBlocker.call(login_attempt:, acting_user:, source: :web)
  │     ├── BlockedLocation.upsert
  │     ├── Session#revoke!
  │     ├── Notification#resolve!
  │     └── Auth::AuditLogger.call(action: :block, ...)
  └── redirect "/settings/security" with flash
```

## Acceptance

- [ ] `notifications.login_attempt_id` migrated.
- [ ] `auth_audit_logs` table created.
- [ ] `Notification#kind` enum gains `login_pending_approval`.
- [ ] `Notifications::Pipeline` dispatches one notification per pending session
      (dedupe by `login_attempt_id`).
- [ ] Notification card renders the two bracketed-link actions
      (`[yeah, it's me]` / `[block the intruder]`) with the correct hrefs.
- [ ] `Auth::LoginAttemptApprover` and `Auth::LoginAttemptBlocker` are the sole
      entry points for approve / block.
- [ ] Both actions audit-log via `Auth::AuditLogger`.
- [ ] Approve flow flips pending → active, calls `reset_session`, upserts
      `TrustedLocation`, resolves the notification.
- [ ] Block flow upserts `BlockedLocation`, revokes pending session, resolves
      the notification.
- [ ] Action-screen confirmation per project framework — NO JS confirm / alert /
      prompt.
- [ ] Yes / no Booleans at every external boundary.
- [ ] TUI notifications surface renders the pending card; `a` / `b` keystrokes
      trigger in-TUI confirmation overlay.
- [ ] TUI status-line prompt on non-notification surfaces shows pending approval
      availability.
- [ ] MCP `notifications_list` already returns the new kind (Phase 16); confirm
      wire shape.
- [ ] MCP approve / block tools are scaffolded (full gating in `01d`).
- [ ] Friendly URLs locked.
- [ ] Full RSpec green; Brakeman clean; bundler-audit clean.

## Manual test recipe

1. `git pull --rebase`, `bin/dev`.
2. From browser A (trusted), log in; from browser B (untrusted + different
   fingerprint), submit the correct password; click `[ask for approval]`.
   Pending session in place.
3. In browser A, expect an urgent banner with the new-location notification.
   Click `[yeah, it's me]`.
4. Confirmation screen renders (action-screen pattern). Click `[yeah, it's me]`
   again. Redirect to root with success flash.
5. In browser B, the pending holding page should advance to root (refresh; the
   SSE / poll mechanism here is whatever Phase 16 shipped).
6. Verify `/settings/security/audit` shows the approve event.
7. Repeat from a third fresh browser: this time click `[block the intruder]` in
   browser A. Action-screen → confirm → redirect.
8. Verify `/settings/security/blocks` shows the new blocked entry (read-only in
   this sub-spec; full UI in `01f`).
9. Open the TUI. Trigger another pending. On the notifications surface, press
   `a` → overlay → `y` confirm → approve.
10. Open the MCP harness; call `notifications_list` → the pending item carries
    `"actions"` with two yes/no-typed entries.
11. Teardown: `Notification.where(kind: :login_pending_approval).destroy_all` if
    needed.

## Cross-stack scope

| Surface | Status                                                                  |
| ------- | ----------------------------------------------------------------------- |
| Rails   | In scope (full).                                                        |
| TUI     | In scope (notifications surface overlay + status-line prompt).          |
| MCP     | Notifications-list rendering only; approve / block tools land in `01d`. |
| Website | Out of scope.                                                           |

## Open questions

- **Q-F** (TUI approval UX): in-TUI overlay on the notifications surface,
  status-line prompt elsewhere. Confirm.
- **Q-L** (notification dedupe): one notification per pending approval (not per
  failed attempt). Confirm.
- New: should the TUI display the pending count in the status bar globally?
  Recommend yes; small badge `! 1 pending`.
- New: should approve / block be reversible within N seconds? Out of scope here;
  if implemented, the audit log carries the reversal.
- New: do we want push notifications (email / SMS / mobile push) at this phase,
  or just in-app? Lock to in-app only for Phase 25. Email push is a Phase 25.5 /
  26 follow-up.
