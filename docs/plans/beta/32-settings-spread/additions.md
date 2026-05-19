# Phase 32 — additions

Scope-drift ledger for `/settings` revamp work that SHIPPED but was NOT part
of the original `plan.md` scope statement (which named the index reorg + per-
sub-surface ergonomic polish; everything below is a structural addition
beyond that). Each entry traces back to a log session or commit. Append-only;
sorted structural-first, polish-last.

## Configuration + persistence

## 2026-05-15 — `config/pito.yml` install-knobs file + initializer + rake surface

- **Item:** New `config/pito.yml` (gitignored) +
  `config/pito.yml.example` (committed) carrying `max_panes`,
  `pane_title_length`, `timezone`. Loaded once at boot via
  `config/initializers/pito_config.rb` into
  `Rails.application.config.x.pito.*`. New rake surface
  `bin/rails pito:config:*` (`show`, `max_panes:{get,set[N]}`,
  `pane_title_length:{get,set[N]}`, `timezone:{get,set[IANA]}`) with
  range + IANA validation and a Puma-restart reminder on every `set`.
- **Rationale:** Sub-spec 01 moved install-level knobs out of the
  `AppSetting` table + UI surface entirely. The original plan scope
  statement spoke of "polish + collapse" rather than naming a YAML
  install-knob file.
- **Plan link:** ticked under `01 — settings refactor` (the checkbox
  text now mentions `config/pito.yml`).
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-15 — Theme persistence moved to localStorage

- **Item:** `theme_controller.js` no longer PATCHes the server; the
  layout's inline bootstrap script reads `pito-theme` from localStorage
  with system-preference fallback. `PATCH /settings/theme` route +
  controller action dropped.
- **Rationale:** Sub-spec 01 — theme is a per-browser preference, not
  install state; moving it to localStorage shaves a DB hit on every
  setting-toggle and removes a server round-trip.
- **Plan link:** ticked under `01 — settings refactor`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-15 — Keyboard navigation always-on

- **Item:** `keyboard_controller.js` registers its keydown listener
  unconditionally; `data-keyboard-navigation-enabled` body attribute
  dropped from the layout. `AppSetting.keyboard_navigation_enabled`
  column dropped via migration
  `20260515120000_drop_ux_app_settings_fields.rb`.
- **Rationale:** Sub-spec 01 — the disable toggle had no audience;
  always-on simplifies the keyboard contract across the app.
- **Plan link:** ticked under `01 — settings refactor`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## Layout + navigation

## 2026-05-15 — 3-row dashboard layout

- **Item:** `/settings` rebuilt as a 3-row dashboard. Row 1: profile
  inline form + security launchers (TOTP / sessions / locations) opening
  a layout-positioned `<dialog>` via Turbo Frame. Row 2: OAuth
  applications + tokens (inline) + Discord + Slack webhooks (stacked
  with hairline). Row 3: stack pane (`pane--wide`) covering Postgres +
  Redis + Meilisearch + Voyage + assets + notes probes.
- **Rationale:** This IS the 01 checkbox's "3-row dashboard" — captured
  here for the audit trail because every downstream addition layered on
  top.
- **Plan link:** ticked under `01 — settings refactor`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## 2026-05-15 — Settings modal Stimulus controller

- **Item:** New `settings-modal` Stimulus controller mirroring the
  notification-modal / calendar-entry-modal pattern. Three
  modal-eligible views (`/settings/security/totp`, `/settings/sessions`,
  `/settings/security/blocks`) wrapped in
  `turbo_frame_tag "settings_modal_frame"` so direct hits still render
  full pages while modal opens swap into the frame.
- **Rationale:** 01 — security launchers open modals rather than
  navigating away; the modal needs a controller to drive open/close.
- **Plan link:** ticked under `01 — settings refactor`.
- **Driver:** `2026-05-15 — 01 settings refactor end-to-end` log entry.

## TOTP / 2FA flow

## 2026-05-15 — Mandatory-TOTP auto-open modal on /settings

- **Item:** `Sessions::AuthConcern#require_totp_configured!` redirects
  every non-allowlisted authenticated route to
  `settings_path(enroll_totp: 1)` (was `settings_security_totp_path`).
  `_settings_modal` accepts `auto_open_url:` + `non_dismissible:`
  locals; auto-opens the dialog on `connect()`; suppresses Escape +
  click-outside dismiss in mandatory mode. New
  `.settings-panes--muted` CSS rule (opacity 0.45, grayscale 0.4,
  pointer-events: none, user-select: none) for the gated context.
- **Rationale:** Polish pass after 01 — the focused-dialog full-page
  enrollment-landing flow was disorienting; auto-open modal on the
  settings hub gives the user context while gating the rest of the
  page.
- **Plan link:** outside plan (polish on top of 01); spec slug
  `settings-refactor-followup`.
- **Driver:** `2026-05-15 — Settings refactor polish (Concern 1 + 2)`
  log entry.

## 2026-05-16 — Atomic-finalize TOTP enrollment + draft cache

- **Item:** Sub-spec 01h — `users.totp_seed_encrypted` no longer
  persists until the user confirms a 6-digit code. Seed + 10 plaintext
  backup codes live in `Rails.cache` keyed on user id (5-minute TTL)
  during GET; the database row is touched only inside a single
  transaction on POST after a correct 6-digit verify. Non-resumable:
  every fresh GET regenerates the draft.
- **Rationale:** Previous flow left users in a half-state when the tab
  closed mid-enrollment (the column populated, the user unable to log
  in without backup codes). User direction locked atomic finalize.
- **Plan link:** ticked under `01h` (the checkbox text describes
  non-resumable enrollment).
- **Driver:** `2026-05-16 — 01h: 2FA / TOTP web-surface cleanup` log
  entry.

## 2026-05-16 — `pito:user:regenerate_backup_codes` rake task

- **Item:** New `pito:user:regenerate_backup_codes[username]` task in
  `lib/tasks/pito.rake`. Calls `Auth::BackupCodeRegenerator`, prints 10
  fresh codes once with a "save them now — cannot be retrieved later"
  header, idempotent, exits non-zero on unknown username and on a
  not-enrolled target.
- **Rationale:** Sub-spec 01h dropped the web-side backup-codes
  rotation surface; operators still need a way to issue fresh codes.
- **Plan link:** ticked under `01h`.
- **Driver:** `2026-05-16 — 01h: 2FA / TOTP web-surface cleanup` log
  entry.

## OAuth / tokens operator surface

## 2026-05-16 — `pito:oauth_apps:*` rake task surface

- **Item:** New `lib/tasks/pito_oauth_apps.rake` with `list`,
  `mint[name,redirect_uri,scopes?]`, `show[id_or_client_id]`,
  `revoke[id_or_client_id,force?]`. Mint prints `client_id` +
  `client_secret` + `redirect_uri` + `scopes` once behind a clear
  header. Revoke destroys app + revokes outstanding tokens + grants in
  a single transaction.
- **Rationale:** Sub-spec 01g dropped the web-side OAuth app
  management UI for the single-user install; operators use the rake
  surface instead.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log
  entry.

## 2026-05-16 — `pito:tokens:*` rake task surface

- **Item:** New `lib/tasks/pito_tokens.rake` with `list`,
  `mint[name,scope1+scope2+...]`, `revoke[id_or_name]`. Mint prints
  plaintext once behind a "save now" header. Revoke is idempotent;
  already-revoked tokens exit 0.
- **Rationale:** Sub-spec 01g dropped the web-side tokens management
  UI; namespace-consistent operator surface replaces it. The
  pre-existing `lib/tasks/tokens.rake` (`tokens:create / list /
  revoke`) is intentionally left in place.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log
  entry.

## 2026-05-16 — Claude Desktop OAuth seed (`claude-mcp` app)

- **Item:** `db/seeds.rb` mints a `claude-mcp` Doorkeeper application
  on first seed with
  `redirect_uri: https://claude.ai/api/mcp/auth_callback`,
  `confidential: true`, `scopes: Scopes::ALL`. Idempotent on re-seed —
  create branch prints client_id + client_secret once; re-runs print a
  presence acknowledgement.
- **Rationale:** Claude Desktop is an OAuth client (Authorization Code
  + PKCE), not a bearer-token integration; a seeded OAuth app means
  the user can paste credentials into Claude → Add custom connector
  immediately after a fresh seed.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log
  entry.

## Webhooks pane (Row 2 polish)

## 2026-05-16 — Webhook URL clear invariant + null-allowing migration

- **Item:** Blank URL submit clears the integration and zeroes both
  flags via a model `before_validation` invariant. New
  `flags_require_webhook_url` defense-in-depth validator. Distinct
  `cleared` vs `updated` flash copy. New migration
  `20260516180000_allow_null_webhook_url_on_notification_delivery_channels.rb`
  relaxes NOT NULL on the URL column.
- **Rationale:** Closeout polish — webhook clear flow was inconsistent
  (flags stayed on after URL went null, defeating the secret-clearing
  intent).
- **Plan link:** closeout polish on top of 01.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## 2026-05-16 — Discord + Slack webhook copy + pane split

- **Item:** Row 2 split into Discord LEFT + Slack RIGHT as two distinct
  `.pane` blocks (was a combined `_webhooks_pane.html.erb` with stacked
  Discord + Slack inside one pane). Webhook copy
  `deliver every notification` → `every notification`.
- **Rationale:** Sub-spec 01g — denser, more navigable layout when each
  integration has its own pane; the combined pane crammed two distinct
  configuration sets into one card.
- **Plan link:** ticked under `01g`.
- **Driver:** `2026-05-16 — 01g settings refactor follow-up` log
  entry.

## Sessions table (Row 1 Right inline)

## 2026-05-16 — Sessions table inline in Security pane

- **Item:** Sessions table moved from standalone `/settings/sessions`
  page into the Security pane as inline content. Columns: checkbox,
  user-agent, pinged (relative time), ip-as-`<code class="inline-code">`.
  `active` + `remember` columns dropped; visible rows filtered to
  active-only. Sortable headers drive `?sessions_sort=` /
  `?sessions_dir=` on `/settings` itself.
- **Rationale:** Sub-spec 01i — the Security pane is where the user
  thinks about session activity; the standalone page added a hop
  without adding signal.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — `pito:sessions:list[state]` rake task

- **Item:** New `pito:sessions:list[state]` in `lib/tasks/pito.rake`.
  Default: active only. Optional `state` ∈ `{active, revoked,
  expired, all}`. Tabular stdout (id / user / user-agent / ip /
  pinged / created-at); a `state` column appears only when
  `state=all`. Unknown state → stderr + non-zero exit.
- **Rationale:** Sub-spec 01i dropped the standalone web index; revoked
  + expired rows need an operator surface for audit.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — `YesNoBadgeComponent` + `ActiveBadgeComponent`

- **Item:** Two new thin wrappers over `StatusBadgeComponent`. YesNo
  coerces boolean / yes/no/1/0/true/false strings into green `[yes]` /
  muted `[no]`. Active renders `active` (or a `label:` override) with
  green styling.
- **Rationale:** Sub-spec 01i extracted reusable primitives during the
  sessions table rewrite — the yes/no boundary rule (CLAUDE.md) gets a
  view primitive, and `active` markers need a consistent style.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## 2026-05-16 — `code.inline-code` CSS rule

- **Item:** New generic CSS rule in `application.css` —
  `code.inline-code { background-color: var(--color-bg-alt); padding: 1px 4px; border-radius: 2px; }`.
  Mirrors the inline-code visual the markdown-preview surface uses, but
  generic so any short monospace data value (ids, short tokens, IPs)
  can adopt it.
- **Rationale:** Sub-spec 01i — sessions table IP column needs an
  inline-code visual; previously only available inside
  markdown-preview context.
- **Plan link:** ticked under `01i`.
- **Driver:** `2026-05-16 — 01i sessions revamp v2` log entry.

## Stack pane (Row 3)

## 2026-05-16 — Reindex modal moved to page-level mount

- **Item:** Reindex modal moved out of the broadcast partial into a
  page-level mount in `_stack_pane.html.erb`. New
  `refreshCsrf` Stimulus action copies the live `<meta name="csrf-token">`
  into the form's hidden `authenticity_token` input on submit.
- **Rationale:** Closeout fix — the broadcast re-render lost session
  context so the form's `authenticity_token` aged out. Page-level
  mount + live CSRF refresh = no stale-token submits.
- **Plan link:** closeout polish on top of 01.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## 2026-05-16 — Stack-table CSS rebuild (named vars + escaped sort arrows)

- **Item:** Stack-pane table CSS rebuilt — right-align both header and
  body cells for numeric columns; sort arrow escapes the cell via
  absolute positioning (`top: -10px; right: 0`). Sortable + stats
  tables share rule set with named CSS vars
  (`--stack-cell-padding: 8px`, `--stack-arrow-top: -10px`,
  `--stack-arrow-right: 0`). Sessions table opted in via a
  `.sessions-table` marker class.
- **Rationale:** Closeout polish — per-pixel tuning on every table was
  brittle; named vars + escaped arrows let one rule set drive every
  numeric table.
- **Plan link:** closeout polish on top of 01.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## Header + chrome

## 2026-05-16 — Logout link removed from header (lives in leader menu)

- **Item:** Header lost its logout link; logout lives in the leader
  menu only.
- **Rationale:** Closeout polish — header chrome was duplicated against
  the leader-menu affordance; subtraction in line with the beta-3
  direction.
- **Plan link:** closeout polish on top of 01.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## 2026-05-16 — Keyboard-shortcuts gate moved to `<meta>` tag

- **Item:** Gate moved from inline body `<script>` to
  `<meta name="pito-enroll-totp-gate">` in `<head>`. Each Stimulus
  controller does a live per-keypress read via a shared helper.
  Follow-up fix to `leader_menu_controller#connect` — early-return
  guard removed (was bailing during Turbo Drive permanent-element
  swap window before `hasPopupTarget` was true).
- **Rationale:** Closeout polish — inline `<script>` was stale across
  Turbo Drive navigation; the meta-tag pattern is the project's
  canonical way to pass server-known booleans into the JS layer.
- **Plan link:** closeout polish on top of 01.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## Infrastructure (orthogonal but landed in-phase)

## 2026-05-16 — `bin/test` wrapper + `.rspec` system-tag skip default

- **Item:** New `.rspec` default `--tag ~type:system` skips system
  specs in the local fast loop. CI workflow overrides with
  `-- --options /dev/null --require spec_helper` so CI still runs the
  full suite. New `bin/test-prepare` shim caches `db:test:prepare`
  invocation based on `db/schema.rb` mtime. New `bin/test` wrapper
  with `bin/test` / `bin/test failed` / `bin/test all` / `bin/test
  path/...` shortcuts.
- **Rationale:** Closeout infrastructure pass — the in-phase spec
  iteration loop kept stalling on Capybara/Chrome system specs (~5–10×
  slower); the wrapper formalizes the fast loop / full loop split.
- **Plan link:** outside plan; orthogonal infrastructure that landed
  in the closeout session.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry.

## 2026-05-16 — `/VERSION` bump → `0.0.1.beta3`

- **Item:** `/VERSION` bumped `0.0.1.beta2` → `0.0.1.beta3`. Inaugural
  beta-3 milestone marker — the page-by-page subtraction cycle starts
  here with `/settings` as the first page completed.
- **Rationale:** Closeout — beta-3 direction (cut the fat, sweep every
  screen) starts with /settings; the version bump signals the cycle
  shift.
- **Plan link:** outside plan; cycle marker.
- **Driver:** `2026-05-16 — Phase 32 closeout` log entry; user memory
  `project_beta_3_direction`.
