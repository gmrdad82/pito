# Phase 32 — dropped

Scope-drift ledger for `/settings` revamp work that was ORIGINALLY scoped or
implied by the plan (sub-specs 01 / 01g / 01h / 01i) but CUT or REPLACED
before the phase closed. Each entry traces back to a log session, ADR, or
user-direction note. Append-only; sorted structural-first, polish-last.

`plan.md` checkbox edits remain forbidden per CLAUDE.md — the checkbox text
itself already encodes most of these cuts (e.g. 01g's "drop OAuth/tokens UI"
language is the dropped-item declaration). This file is the auditable
companion.

## Data + persistence

## 2026-05-15 — `AppSetting` UI-knob columns

- **Item:** `AppSetting.keyboard_navigation_enabled`,
  `AppSetting.timezone`, `AppSetting.voyage_index_project_notes` columns
  + KV rows for `theme`, `max_panes`, `pane_title_length` dropped via
  migration `20260515120000_drop_ux_app_settings_fields.rb`.
- **Rationale:** Sub-spec 01 — install-level knobs moved to
  `config/pito.yml` (see `additions.md`); per-browser knobs (theme)
  moved to localStorage; always-on toggles (keyboard navigation) lost
  their persisted column.
- **Plan link:** ticked under `01 — settings refactor`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-16 — `sessions.remember` column + entire remember-me surface

- **Item:** Migration
  `20260516135916_drop_session_remember_column.rb` drops the
  `sessions.remember` boolean. `Session.create_for!` signature
  collapses to `(user:, ip:, user_agent:)`; `Session::REMEMBER_ME_TTL`
  constant deleted. `Auth::SessionActivator.call` drops `remember:`
  kwarg. `SessionsController` + `Login::TotpChallengesController` +
  `Sessions::TokenRotation` concern drop `remember_me` form param read,
  `remember:` plumbing, and cookie's conditional `expires:` attribute.
  `<input type="checkbox" name="remember_me">` block + "remember me on
  this device (30 days)" label removed from `/login`. Session cookies
  are session-only now.
- **Rationale:** Sub-spec 01i — the remember-me toggle complicated
  every session-minting path for marginal user value; mandatory-2FA
  reframed the security tradeoff against persistent cookies.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — `LoginAttempt` model + MCP tools + digest section

- **Item:** `LoginAttempt` model + its MCP tools + the digest section
  that exposed login-attempt counts dropped entirely (Phase 25
  rollback).
- **Rationale:** Closeout — the surface accreted past its useful
  weight; operator-facing signal is captured via session rows + audit
  logs instead.
- **Plan link:** outside Phase 32 plan (this is a Phase 25 rollback
  that landed in the closeout polish wave).
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## TOTP / 2FA

## 2026-05-16 — TOTP manage page + disable flow + backup-codes management

- **Item:** `Settings::Security::TotpBackupCodesController` + its views
  (`new`, `show`); `Settings::Security::TotpsController#show /
  #destroy_screen / #destroy_confirmed` + their views; routes
  `GET /settings/security/totp/show`,
  `PATCH /settings/security/totp/confirm`,
  `GET|POST /settings/security/totp/disable`, and the three
  `/settings/security/totp_backup_codes` routes all dropped.
  `Sessions::AuthConcern::TOTP_SETUP_ALLOWLIST` shrunk 6 → 4 entries.
- **Rationale:** Sub-spec 01h — collapse the TOTP web surface to a
  single focused enrollment view; disable + backup-code rotation move
  to operator-only rake tasks (`pito:user:reset_totp` +
  `pito:user:regenerate_backup_codes`).
- **Plan link:** ticked under `01h`.
- **Driver:** `2026-05-16 — 01h: 2FA / TOTP web-surface cleanup` log
  entry.

## 2026-05-16 — `[ 2FA / TOTP ]` launcher on Security pane

- **Item:** `[ 2FA / TOTP ]` link removed from `/settings` Row 1 Right.
  The page it opened is gone (no manage page, no disable, no
  backup-codes rotation surface). Security pane row now carries just
  `[ sessions ]` and `[ locations ]`.
- **Rationale:** Sub-spec 01h — the destination page no longer exists;
  the mandatory-enrollment flow uses the auto-open modal on
  `/settings?enroll_totp=1` instead of this link.
- **Plan link:** ticked under `01h`.
- **Driver:** `2026-05-16 — 01h: 2FA / TOTP web-surface cleanup` log
  entry.

## 2026-05-16 — TOTP enrollment breadcrumb + `[ cancel ]` button

- **Item:** Breadcrumb dropped from the enrollment view (the
  configured-user branch is gone; the unconfigured branch never
  carried one). `[ cancel ]` button dropped — atomic finalize means
  there's nothing to cancel mid-flow.
- **Rationale:** Sub-spec 01h — mandatory-2FA means the only exits are
  complete enrollment or log out; cancel left users in a half-state
  under the prior non-atomic flow.
- **Plan link:** ticked under `01h`.
- **Driver:** `2026-05-16 — 01h: 2FA / TOTP web-surface cleanup` log
  entry.

## 2026-05-16 — Logout escape-hatch form on TOTP gate

- **Item:** Logout escape-hatch form removed from the TOTP enrollment
  view (intentional minimization — the gate's allowlist still covers
  the logout route, so the user can still log out via the leader
  menu / direct URL).
- **Rationale:** Closeout polish — visual subtraction in line with
  beta-3 direction; the route stays allowlisted, only the embedded
  form goes.
- **Plan link:** closeout polish on top of 01h.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## OAuth + tokens

## 2026-05-16 — `/settings/oauth_applications/*` web UI

- **Item:** Routes, controller (`Settings::OauthApplicationsController`),
  views (`index`, `new`, `_form`, `create`, `show`, `revoke`), request
  specs, and system spec all dropped. Doorkeeper handshake endpoints
  (`/oauth/authorize`, `/oauth/token`, `/oauth/revoke`,
  `/oauth/introspect`) untouched — Claude Desktop's OAuth flow keeps
  working.
- **Rationale:** Sub-spec 01g — single-user install; operator uses the
  new `bin/rails pito:oauth_apps:*` rake surface instead.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log entry.

## 2026-05-16 — `/settings/tokens/*` web UI

- **Item:** Routes, controller (`Settings::TokensController`), views
  (`index`, `new`, `_form`, `create`, `revoke`), request spec, system
  spec all dropped.
- **Rationale:** Sub-spec 01g — single-user install; operator uses the
  new `bin/rails pito:tokens:*` rake surface (or the pre-existing
  `tokens:*` rake) instead.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log entry.

## 2026-05-16 — Combined `_webhooks_pane.html.erb` partial

- **Item:** `_webhooks_pane.html.erb` (Discord + Slack stacked inside
  one pane with hairline separator) deleted. Replaced by the two
  standalone `_discord_pane.html.erb` + `_slack_pane.html.erb` partials
  rendered as separate `.pane` blocks (LEFT + RIGHT).
- **Rationale:** Sub-spec 01g — denser, more navigable layout when
  each integration owns its own pane.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log entry.

## Sessions

## 2026-05-16 — Standalone `/settings/sessions` page

- **Item:** `Settings::SessionsController` deleted; `app/views/settings/
  sessions/{index,revoke}.html.erb` deleted. Routes
  `resources :sessions, only: %i[index destroy]` + `member { get
  :revoke }` block dropped. Only `/settings/sessions/revokes/:ids`
  (GET + POST → bulk_revokes) survives as the action endpoint.
- **Rationale:** Sub-spec 01i — sessions table moved inline into the
  Security pane (see `additions.md`); the standalone page added a hop
  without adding signal.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — `[ sessions ]` modal launcher + modal-trigger Stimulus action

- **Item:** `[ sessions ]` modal launcher removed from the Security
  pane along with the modal-trigger Stimulus action that opened it.
- **Rationale:** Sub-spec 01i — the table renders inline now; no
  modal-launcher needed.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — Security pane helper copy block

- **Item:** Security pane lost its helper copy block (`2FA: …`, `active
  sessions: …`, the modal-vs-direct prose paragraph).
- **Rationale:** Sub-spec 01i — denser pane; the helper copy
  duplicated information the inline table now surfaces directly.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — `active` + `remember` columns on sessions table

- **Item:** `active` column dropped (visible rows filtered to
  active-only). `remember` column dropped along with the underlying
  database column (see structural drop above).
- **Rationale:** Sub-spec 01i — lighter pane table; revoked + expired
  rows are operator-tier (rake task) audit content.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — Sessions IP column

- **Item:** IP column dropped from the sessions table; replaced by an
  inline `TooltipBadgeComponent`.
- **Rationale:** Closeout polish — IP-as-column took up valuable
  horizontal space; the tooltip badge keeps the info reachable without
  consuming a column.
- **Plan link:** closeout polish on top of 01i. (Note: 01i shipped
  `code.inline-code` styling for the IP cell; closeout swapped the
  cell rendering entirely.)
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## Chrome + global affordances

## 2026-05-15 — `PATCH /settings/theme` route + action

- **Item:** `PATCH /settings/theme` route + controller action dropped.
  Theme persistence moved to localStorage (see `additions.md`). Legacy
  `PATCH /settings` passthrough redirects with the standard notice (no
  500s on scripted callers).
- **Rationale:** Sub-spec 01 — theme is a per-browser preference now.
- **Plan link:** ticked under `01`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-15 — `data-theme-preference` + `data-keyboard-navigation-enabled` attributes

- **Item:** `data-theme-preference` attribute dropped from `<html>`
  layout root; `data-keyboard-navigation-enabled` attribute dropped
  from `<body>`.
- **Rationale:** Sub-spec 01 — theme + keyboard navigation no longer
  read from server state on every request.
- **Plan link:** ticked under `01`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-15 — MCP `manage_settings` tool

- **Item:** MCP `manage_settings` tool + its spec deleted.
- **Rationale:** Sub-spec 01 — matches the paused-MCP cleanup pattern
  (web-polish focus, MCP+TUI on hold). The `pito://status` resource
  still returns the workspace fields the CLI binds to;
  `max_panes` / `pane_title_length` resolve from `config.x.pito.*`
  now, `theme` is the static `"auto"` placeholder.
- **Plan link:** ticked under `01`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-16 — Help modal (`?`-toggled keyboard-shortcuts overlay)

- **Item:** Help modal deleted entirely. Footer `[_]` button no longer
  triggers the help modal — only opens the leader menu.
- **Rationale:** Closeout polish — leader menu is now the sole
  keyboard-discovery affordance; the help modal duplicated content
  and added a second discovery path with different semantics.
- **Plan link:** closeout polish on top of 01.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## Sweep / orphan removals

## 2026-05-16 — Orphan auth code sweep

- **Item:** `Pito::Auth::IpPrefix`, `Pito::Auth::UserAgentParser`,
  `Auth::TotpDisabler` (+ specs) deleted. Stale
  `SESSIONS_ALLOWED_SORTS "ip"` entry trimmed. Dead `seeds.rb` comment
  block (pointing at a removed `pito:drop_seeded_channels` rake)
  deleted. Three stale `Auth::TotpDisabler` doc-comments refreshed.
- **Rationale:** Closeout sweep — once the consumer surfaces (sessions
  page IP column, TOTP disable flow) went away, the helpers that
  served them became orphans.
- **Plan link:** closeout polish on top of 01h + 01i.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.
