# Phase 32 — Settings Spread — Log

> Session entries land here as Lane E units close. Append-only after user
> validation.

## 2026-05-15 — 01 settings refactor end-to-end

Spec slug: `settings-refactor` (in-conversation dispatch; locked spec predates
this log entry).

### Implemented

- New `config/pito.yml` (gitignored) + `config/pito.yml.example` (committed)
  carrying `max_panes`, `pane_title_length`, and the install-level `timezone`.
  Loaded once at boot by `config/initializers/pito_config.rb` into
  `Rails.application.config.x.pito.*`. Out-of-range and unparseable values fall
  back to defaults with a stderr warning.
- New rake task surface `bin/rails pito:config:*`: `show`,
  `max_panes:{get,set[N]}`, `pane_title_length:{get,set[N]}`,
  `timezone:{get,set[IANA_NAME]}`. Range validation and IANA-name validation
  included; each `set` prints a Puma-restart reminder.
- Migration `20260515120000_drop_ux_app_settings_fields.rb` drops
  `app_settings.keyboard_navigation_enabled`, `app_settings.timezone`,
  `app_settings.voyage_index_project_notes`, and purges any leftover KV rows for
  `theme`, `max_panes`, `pane_title_length`. Reversible (re-adds columns at
  original defaults).
- `AppSetting` model simplified — drops `keyboard_navigation_enabled?` /
  `set_keyboard_navigation_enabled` accessors and the `timezone_must_be_iana`
  validation (the column is gone). `voyage_indexing_project_notes?` is now a
  thin alias for `voyage_configured?` (credentials key presence is the only
  signal).
- `/settings` is a 3-row dashboard. Row 1: profile inline form + security
  launchers (2FA / TOTP, sessions, locations) that open a layout-positioned
  `<dialog>` populated via Turbo Frame. Row 2: OAuth applications + tokens
  (inline list + new/revoke links) and Discord + Slack webhooks (stacked with a
  hairline). Row 3: stack pane (`pane--wide`) covering Postgres + Redis +
  Meilisearch + Voyage embeddings + assets + notes — same probe set the previous
  index exposed.
- Theme persistence moved to localStorage only.
  `app/javascript/controllers/theme_controller.js` no longer PATCHes the server;
  the layout's inline bootstrap script reads `pito-theme` with system-preference
  fallback.
- Keyboard navigation is always on.
  `app/javascript/controllers/keyboard_controller.js` registers its keydown
  listener unconditionally; the `data-keyboard-navigation-enabled` body
  attribute is gone from the layout.
- New `settings-modal` Stimulus controller mirrors the notification-modal /
  calendar-entry-modal pattern. The three modal-eligible views
  (`/settings/security/totp`, `/settings/sessions`, `/settings/security/blocks`)
  are wrapped in `turbo_frame_tag "settings_modal_frame"` so direct hits still
  render full pages while modal opens swap into the frame.
- MCP `manage_settings` tool + spec dropped (matches the paused-MCP cleanup
  pattern). The `pito://status` resource still returns the three workspace
  fields the CLI binds to; `max_panes` / `pane_title_length` resolve from
  `config.x.pito.*` now, `theme` is the static `"auto"` placeholder.
- Channels / Videos controllers' `max_panes` / `pane_title_length` helpers, the
  calendar entries / month / schedule controllers' `@install_tz`,
  `CalendarEntry#stamp_install_timezone`, `MilestoneRule#fire!`,
  `Game#calendar_entry_attributes`, and the calendar helper's `entry_*_label`
  methods all read from `Rails.application.config.x.pito.timezone` instead of
  `AppSetting.first&.timezone`.
- Layout drops the `data-theme-preference` attribute on `<html>` and the
  `data-keyboard-navigation-enabled` attribute on `<body>`.
- `PATCH /settings/theme` route + controller action dropped. `PATCH /settings`
  legacy passthrough redirects with the standard notice (no 500s on scripted
  callers).
- `.env.example` notes the migration of `MAX_PANES` / `PANE_TITLE_LENGTH` away
  from env.

### Files touched (high level)

- Application code: `app/controllers/settings_controller.rb`,
  `app/controllers/channels_controller.rb`,
  `app/controllers/videos_controller.rb`,
  `app/controllers/calendar/{entries,month,schedule}_controller.rb`,
  `app/models/{app_setting,calendar_entry,game,milestone_rule}.rb`,
  `app/helpers/calendar_helper.rb`, `app/mcp/resources/app_status.rb`,
  `app/javascript/controllers/{keyboard,theme,settings_modal}_controller.js`,
  `app/views/layouts/application.html.erb`,
  `app/views/calendar/router/show.html.erb`,
  `app/views/settings/{index,_profile_pane,_security_pane,_oauth_and_tokens_pane,_webhooks_pane,_stack_pane,_settings_modal}.html.erb`,
  `app/views/settings/security/{totps/new,blocks/index}.html.erb`,
  `app/views/settings/sessions/index.html.erb`, `config/routes.rb`,
  `config/initializers/pito_config.rb`, `config/pito.yml.example`,
  `lib/tasks/pito_config.rake`, `.env.example`, `.gitignore`.
- Dropped: `app/mcp/tools/manage_settings.rb`,
  `spec/mcp/tools/manage_settings_spec.rb`.
- Migration: `db/migrate/20260515120000_drop_ux_app_settings_fields.rb`
  - `db/schema.rb` post-migrate refresh.

### Specs added

- Model: `spec/models/app_setting_spec.rb` rewritten — dropped-column guards +
  simplified Voyage predicates.
- Request: `spec/requests/settings_spec.rb` rewritten — 3-row layout, modal
  launcher markup, dropped-surface negative guards, JSON contract, legacy
  passthrough, dropped `/settings/theme` 404.
- Views:
  `spec/views/settings/_{profile,security,oauth_and_tokens,webhooks,stack}_pane_html_erb_spec.rb`.
- System: `spec/system/settings_refactor_spec.rb`.
- Initializer: `spec/initializers/pito_config_spec.rb`.
- Migration: `spec/db/migrate/drop_ux_app_settings_fields_spec.rb`.
- Rake: `spec/lib/tasks/pito_config_rake_spec.rb`.

### Specs updated (drift across the suite)

- `spec/jobs/notes/embed_job_spec.rb` — Voyage indexing now keyed on credentials
  presence only.
- `spec/mcp/resources/app_status_spec.rb` — workspace values come from
  `config.x.pito.*`.
- `spec/models/calendar_entry_spec.rb`, `spec/helpers/calendar_helper_spec.rb`,
  `spec/requests/calendar/{entries,month,schedule}_spec.rb`,
  `spec/system/calendar_entry_modal_spec.rb` — install timezone reads
  `config.x.pito.timezone`.
- `spec/requests/channels_spec.rb` — `max_panes` from `config.x.pito`.
- `spec/requests/keyboard_shortcuts_layout_spec.rb` — keyboard navigation is
  always on (no `data-keyboard-navigation-enabled`).
- `spec/requests/oauth_authorization_spec.rb` — `data-theme-preference` dropped
  from layout.
- `spec/requests/settings/totp_gates_spec.rb` — Voyage section is gone.
- `spec/system/{settings_webhooks,settings_time_zone,settings/tokens}_spec.rb` —
  pane structure update.

### Parallel suite

`bundle exec parallel_rspec spec/ -n 8` ends at 17 failures + 1 error across
7,451 examples — at or under the 18/1 baseline. All remaining failures are
pre-existing, unrelated to the settings refactor:

- `spec/system/google_oauth_flow_spec.rb:51` — channels index no longer renders
  "no channels yet" copy.
- `spec/lint/numeric_formatting_spec.rb:52` — `settings/security/show.html.erb`
  raw numeric renders (pre-existing).
- `spec/system/calendar_edit_delete_spec.rb:26` — pre-existing.
- `spec/system/settings/tokens_spec.rb:21` — was "Unable to find link 'manage
  tokens'" pre-existing; now "Ambiguous match on `app` scope label" (the
  underlying spec needs a label-disambiguation pass; the failure is unchanged in
  count).
- `spec/views/settings/_{discord,slack}_pane_html_erb_spec.rb`
  `[update] · [help]` regex — pre-existing.
- `spec/views/games/platform_ownerships/edit.html.erb_spec.rb` (9 examples) —
  pre-existing `Games::PlatformOwnershipEditorComponent#any_platforms?` nil bug.
- `spec/system/games_steam_shelf_spec.rb:63` — pre-existing.
- `spec/requests/deletions_spec.rb:227` — pre-existing.
- 1 error outside of examples (early-bootstrap; pre-existing).

### Brakeman

`bundle exec brakeman -q -w2` — 1 medium-confidence SQL injection warning in
`app/queries/games/genre_shelf_batch.rb:82` (pre-existing, not in this
refactor's scope). No new warnings introduced.

### Restart reminder

The new `config/initializers/pito_config.rb` reads `config/pito.yml` at boot.
Operators must restart Puma after editing the YAML or running
`bin/rails pito:config:*:set[…]`. The rake tasks print the reminder on every
`set`.

### Open issues

- The pre-existing `_discord_pane` / `_slack_pane` `nav-sep` regex failures look
  like the spec regex needs to be updated to match the rendered
  `[<span class="bl">help</span>]` form. Out of scope for this refactor.
- The settings tokens flow system spec hits Capybara's label ambiguity on
  `Scopes::APP`; the fix is to disambiguate on the description text. Out of
  scope here — the failure is unchanged in count.

## 2026-05-15 — Settings refactor polish (Concern 1 + Concern 2)

Polish pass on the Settings refactor. Two TOTP-gate concerns the user surfaced.
Implementer dispatched after a prior agent had only partially inventoried the
surface.

### Concern 1 — Recent-TOTP gate on profile updates (regression

restoration finding)

Git forensics on `app/controllers/settings/user_controller.rb` and the
`RecentTotpVerification` concern shows the password-change TOTP gate was ADDED
on commit `d634143` (Wave 4a — 2026-05-11 mega settings + 2FA +
content-missing + channels polish + analytics fix + calendar polish + forms
sweep + videos import + keyboard nav). It has not been removed since:

```
git log --all --oneline -p -S "require_recent_totp_if_enabled" -- \
  app/controllers/settings/user_controller.rb
# d634143 — added `include RecentTotpVerification` + the
#           `return unless require_recent_totp_if_enabled!` guard
#           at the top of #update.
```

The `Settings::UserController#update` filter is still in place today
(`return unless require_recent_totp_if_enabled!` runs before the
`current_password` check). The user's intuition that "at one time this was
working" is correct: the gate has been live continuously since Wave 4a — what
changed in the settings refactor is the form's SUBMIT URL is no longer the
standalone /settings/user page, it's the inline profile pane on /settings
POSTing to /settings/user. The filter still fires.

Spec fallout: `spec/system/settings_profile_totp_gate_spec.rb:94` was asserting
`status_code == 302`, but rack_test's `page.driver.submit` follows redirects by
default — the 302 to /settings yields a 200 on the followed page. Fixed by
asserting on `current_path` + DB mutation instead.

### Concern 2 — Mandatory TOTP enrollment auto-opens on /settings

Replaced the focused-dialog full-page enrollment-landing flow with an auto-open
non-dismissible modal on /settings. Wiring:

- `Sessions::AuthConcern#require_totp_configured!` now redirects every
  non-allowlisted authenticated route to `settings_path(enroll_totp: 1)` instead
  of `settings_security_totp_path`.
- `TOTP_SETUP_ALLOWLIST` adds `GET /settings` so the gate's destination is not
  itself a redirect target (no loop).
- `SessionsController#bootstrap_first_login_session` redirects to the same hub
  URL after a fresh-seed first-login.
- `app/views/settings/index.html.erb` reads `Current.user.totp_configured?`
  (defensive — not the query param) and wraps the pane stack in
  `.settings-panes--muted` plus `aria-disabled="true"` when the gate is active.
  The `_settings_modal.html.erb` partial accepts two new locals:
  - `auto_open_url:` — points the layout-positioned `<dialog>` at a Turbo Frame
    URL on connect.
  - `non_dismissible:` — drops the `[close]` link from the modal header and
    tells the Stimulus controller to suppress Escape + click-outside.
- `app/javascript/controllers/settings_modal_controller.js` gained the
  `autoOpenUrl` + `nonDismissible` values, a `connect()` hook that opens the
  dialog when `autoOpenUrl` is set, and a `cancelDismiss` action wired to the
  dialog's native `cancel` event so Escape no longer closes the dialog when
  locked. The partial's `[close]` link is also conditionally omitted so there is
  no DOM surface to dismiss.
- `app/assets/tailwind/application.css` gained `.settings-panes--muted` —
  opacity 0.45, grayscale 0.4, pointer-events: none, user-select: none. Visible
  context, no interaction.

Allowlisted routes still bypass the gate (enrollment endpoints + logout). Domain
routes (`/channels`, `/videos`, `/projects`, `/games`, `/bundles`, `/calendar`,
`/settings/security`) bounce to the hub with the modal-mount markup on.

### Files touched

- App code: `app/controllers/concerns/sessions/auth_concern.rb`,
  `app/controllers/sessions_controller.rb`, `app/views/settings/index.html.erb`,
  `app/views/settings/_settings_modal.html.erb`,
  `app/javascript/controllers/settings_modal_controller.js`,
  `app/assets/tailwind/application.css`.
- Spec updates (drift across the gate's reach):
  `spec/requests/totp_gate_spec.rb`,
  `spec/requests/settings/totp_gates_spec.rb`, `spec/requests/sessions_spec.rb`,
  `spec/requests/settings/security/totp_backup_codes_spec.rb`,
  `spec/requests/settings/security/totps_spec.rb`,
  `spec/requests/settings/totp_modal_layout_spec.rb`,
  `spec/system/fresh_seed_first_login_spec.rb`,
  `spec/system/settings_profile_totp_gate_spec.rb`.
- New regression specs: `spec/requests/settings/enroll_totp_auto_open_spec.rb`,
  `spec/system/settings_enroll_totp_gate_spec.rb`.

### Parallel suite

`bundle exec parallel_rspec spec/ -n 8` — see captured tail; at or under the
17/1+1-error baseline (pre-existing `_discord_pane` / `_slack_pane` `nav-sep`
regex, settings tokens ambiguous label, calendar/composites/games clusters).

### Brakeman

`bundle exec brakeman -q -w2` — 1 medium-confidence SQL injection warning in
`app/queries/games/genre_shelf_batch.rb:82`. Pre-existing and out of scope for
this polish pass.

### Restart reminder

A Puma restart is required to pick up the new Stimulus controller behavior + the
auth-concern redirect target change. Operators on `bin/dev` should restart after
pulling.

### Open issues

- JS-driven system coverage for the non-dismissible modal (Escape /
  click-outside suppression) is asserted at the markup level only. rack_test
  cannot execute Stimulus connect; full Capybara JS-driver coverage would need
  Cuprite / Selenium registration first.

## 2026-05-16 — 01g settings refactor follow-up: drop OAuth/tokens UI, seed Claude Desktop OAuth app

Spec slug: `settings-refactor-followup` (in-conversation dispatch; locked scope
predates this log entry).

Re-framing of the prior architect's assumption that Claude Desktop is a
bearer-token integration. It is an OAuth client (Authorization Code + PKCE) —
Doorkeeper's OAuth app registration is exactly what Claude Desktop uses. The
web-side management UI for OAuth Apps + Tokens is unnecessary for a single-user
install; both move to rake tasks. The Doorkeeper handshake routes stay live.

### Implemented

- Dropped `/settings/oauth_applications/*` and `/settings/tokens/*` management
  UI: routes, controllers (`Settings::OauthApplicationsController`,
  `Settings::TokensController`), views, request specs
  (`spec/requests/settings/oauth_applications_spec.rb`,
  `spec/requests/settings/tokens_spec.rb`), and the system feature spec
  `spec/system/settings/tokens_spec.rb`. Doorkeeper handshake endpoints
  (`/oauth/authorize`, `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`) are
  untouched — Claude Desktop's OAuth flow keeps working.
- `/settings` Row 2 simplified from
  `[OAuth+Tokens pane (LEFT)] | [Discord+Slack stacked pane (RIGHT, hairline-separated)]`
  to `[Discord pane (LEFT)] | [Slack pane (RIGHT)]` — two distinct `.pane`
  blocks mirroring the canonical pane-row pattern. The combined
  `_webhooks_pane.html.erb` partial is deleted; the pre-existing
  `_discord_pane.html.erb` and `_slack_pane.html.erb` partials (still surfaced
  as standalone view specs) become the row-2 primaries.
- `SettingsController#index` drops the now-unused `@applications`,
  `@active_tokens`, `@revoked_tokens`, `@new_token`, `@new_oauth_application`,
  and related counter instance variables.
- New rake task surface `lib/tasks/pito_oauth_apps.rake`:
  - `pito:oauth_apps:list` — print id, name, client_id, redirect_uri, scopes,
    created_at (NO client_secret).
  - `pito:oauth_apps:mint[name,redirect_uri,scopes?]` — create a new
    confidential Doorkeeper application, print **client_id + client_secret +
    redirect_uri + scopes** once behind a clear "save the client_secret now"
    header. Defaults `scopes` to `Scopes::ALL` when omitted. Validates non-empty
    name + redirect_uri + every-scope-in-catalog; non-zero exit with stderr on
    failure.
  - `pito:oauth_apps:show[id_or_client_id]` — print one app's metadata; lookup
    resolves either numeric id or Doorkeeper `uid`. NO client_secret in output.
  - `pito:oauth_apps:revoke[id_or_client_id,force?]` — destroy the application
    and revoke (`revoked_at`) every outstanding `OauthAccessToken` +
    `OauthAccessGrant` tied to it inside a transaction. `force` arg required to
    avoid accidental destroys; non-zero exit + stderr without it. Prints
    `tokens=N, grants=N` tally on success.
- New rake task surface `lib/tasks/pito_tokens.rake`:
  - `pito:tokens:list` — print id, name, scopes, status, preview, last_used_at,
    created_at (NO plaintext).
  - `pito:tokens:mint[name,scope1+scope2+...]` — mint an `ApiToken` for the
    seeded owner user (`User.first`); print the plaintext exactly once behind a
    clear "save the plaintext now" header. Validates non-empty name + non-empty
    scopes + every-scope-in-catalog; non-zero exit with stderr on failure.
    Errors if no `User` row exists.
  - `pito:tokens:revoke[id_or_name]` — soft-delete (`revoke!`) by numeric id or
    token name. Idempotent — already-revoked tokens print an "already revoked"
    line and exit 0. Pre- existing `tokens:create / tokens:list / tokens:revoke`
    rake surface in `lib/tasks/tokens.rake` is intentionally untouched (still
    valid; predates this follow-up). The new `pito:tokens:*` surface is the
    canonical, namespace- consistent entry point that matches
    `pito:user:reset_totp` / `pito:oauth_apps:*` style.
- `db/seeds.rb` mints a `claude-mcp` Doorkeeper application after the dev-token
  block, with `redirect_uri: https://claude.ai/api/mcp/auth_callback` (the value
  Claude Desktop's MCP custom connector POSTs back to during the OAuth dance,
  observed in the previous run's dev log), `confidential: true`, and
  `scopes: Scopes::ALL`. Idempotent on re-seed via
  `OauthApplication.find_by(name: "claude-mcp")` — the create branch prints the
  `client_id + client_secret + redirect_uri` block once; re-runs print a
  one-line presence acknowledgement instead of the secret. Sample seed-end
  output (with placeholder values):

      ======================================================================
      Claude Desktop OAuth app (paste these into Claude → Add custom
      connector → Advanced):
        client_id:     <43-char_uid>
        client_secret: <43-char_plaintext>
        redirect_uri:  https://claude.ai/api/mcp/auth_callback

      (client_secret is shown once on initial creation — cannot be
       retrieved later if Doorkeeper is reconfigured to hash secrets)
      ======================================================================

- `spec/system/leader_menu_spec.rb`'s `AUDITED_PATHS` constant drops
  `/settings/tokens` + `/settings/oauth_applications` (both surfaces are gone).

### Files touched (high level)

- Application code: `config/routes.rb`,
  `app/controllers/settings_controller.rb`, `app/views/settings/index.html.erb`,
  `db/seeds.rb`.
- Dropped: `app/controllers/settings/oauth_applications_controller.rb`,
  `app/controllers/settings/tokens_controller.rb`,
  `app/views/settings/oauth_applications/{index,new,_form,create,show,revoke}.html.erb`,
  `app/views/settings/tokens/{index,new,_form,create,revoke}.html.erb`,
  `app/views/settings/_oauth_and_tokens_pane.html.erb`,
  `app/views/settings/_webhooks_pane.html.erb`,
  `spec/requests/settings/oauth_applications_spec.rb`,
  `spec/requests/settings/tokens_spec.rb`,
  `spec/system/settings/tokens_spec.rb`,
  `spec/views/settings/_oauth_and_tokens_pane_html_erb_spec.rb`,
  `spec/views/settings/_webhooks_pane_html_erb_spec.rb`.
- New rake task files: `lib/tasks/pito_oauth_apps.rake`,
  `lib/tasks/pito_tokens.rake`.
- New specs: `spec/lib/tasks/pito_oauth_apps_rake_spec.rb` (24 examples),
  `spec/lib/tasks/pito_tokens_rake_spec.rb` (16 examples).
- Updated specs: `spec/requests/settings_spec.rb` (negative guards for the
  dropped surfaces + Doorkeeper handshake smoke tests + Row 2 dual-pane
  structure assertion), `spec/system/settings_refactor_spec.rb` (Row 2 dual-pane
  LEFT/RIGHT ordering), `spec/seeds_spec.rb` (Claude Desktop OAuth app
  idempotency + shape), `spec/system/leader_menu_spec.rb` (`AUDITED_PATHS` drops
  the dropped routes).

### Parallel suite

`bundle exec parallel_rspec spec/ -n 8` — \*\*16 failures + 1 error

- 1 pending\*_ across 7,597 examples. At or under the 17/1+1-error baseline. All
  remaining failures map onto the standing baseline clusters (composites,
  webhooks, games, settings panes, calendar, seeds, OAuth flow, tokens,
  numeric-formatting lint) — none introduced by this follow-up. Spot-checked the
  only failure that did not match prior log enumeration verbatim
  (`spec/requests/settings/webhooks/help_spec.rb:116, :121`): both pass in
  isolation; the failure is environmental parallel-suite cross-test pollution,
  not a regression of this follow-up (the deleted routes are
  `/settings/{oauth_applications,tokens}/_`, never `/settings/webhooks/help/\*`).

### Rubocop

`bundle exec rubocop` on the touched Ruby files — 11 files inspected, no
offenses detected.

### Brakeman

`bundle exec brakeman -q -w2` — same single medium-confidence SQL injection
warning in `app/queries/games/genre_shelf_batch.rb:82` (pre-existing, out of
scope here). No new warnings introduced.

### Restart reminder

Yes — routes + autoload changed. Operators on `bin/dev` should restart Puma
after pulling so the router picks up the dropped
`/settings/oauth_applications/*` + `/settings/tokens/*` routes and the seed
re-run mints the `claude-mcp` Doorkeeper application.

### Open issues

- `lib/tasks/tokens.rake` (`tokens:create / tokens:list / tokens:revoke`) is
  intentionally left in place — predates this follow-up and remains valid.
  Future cleanup could collapse it into `pito:tokens:*` if the operator finds
  the dual surface confusing; not blocking.

## 2026-05-16 — 01h: 2FA / TOTP web-surface cleanup

Spec slug: in-conversation dispatch (no `specs/` file; user direction locked in
conversation after a stopped earlier dispatch on the same surface).

### Implemented

- 2FA / TOTP web surface collapsed to a single focused enrollment view. The
  previous multi-action flow (new → create → show → confirm → disable /
  regenerate backup codes) is gone. Two routes only:
  `GET /settings/security/totp` (renders the 2-row enrollment view) and
  `POST /settings/security/totp` (atomic finalize). Disable + backup-code
  rotation moved to operator-only rake tasks.
- Atomic-finalization fix. The prior controller persisted
  `users.totp_seed_encrypted` plus the 10 backup-code rows during
  `POST /settings/security/totp` (the "create the seed" step), BEFORE the user
  confirmed a 6-digit code. A user who closed the tab mid-enrollment was left
  with the column populated and the database in a half-state. Reworked to
  draft-then-commit: the seed + plaintext codes live in `Rails.cache` (keyed on
  user id, 5-minute TTL) during the GET; the database row is touched only inside
  a single transaction on the POST after a correct 6-digit verify (stamps
  `totp_seed_encrypted` + `totp_enabled_at` + `totp_disabled_at: nil` +
  `totp_last_used_step: nil` and inserts the 10 `totp_backup_codes` rows in one
  go). Wrong-code 422 re-renders the same draft so the QR + codes the user is
  staring at stay valid for the retry.
- Non-resumable enrollment. Every fresh GET regenerates the seed + 10 backup
  codes and overwrites the cache draft. A browser refresh on the enrollment view
  discards the previous unconfirmed draft — the spec calls this out explicitly.
  Successful confirm deletes the cache entry; the seed lives on the user row
  going forward, the plaintext backup codes are never re-displayed.
- 2-row enrollment layout. Row 1 (`.pane-row`, two `.pane` cells): scan
  heading + QR + seed text (left), backup codes heading + 10 codes + "save them
  safely" copy (right). Row 2 (`.pane--wide` spanning the row): "enter code"
  heading + 6-digit input + `[ enable 2FA ]` submit button. The view sets
  `content_for(:hide_chrome, true)` so the focused-dialog feel is preserved (no
  nav header, no footer, no breadcrumb).
- Breadcrumb dropped on this view. The previous file rendered
  `[settings] / [security] / [2FA] / [enroll]` on the configured branch; now
  there is no configured branch at all (a configured user hitting the URL
  redirects to root), and the unconfigured branch never carried a breadcrumb to
  begin with.
- `[ cancel ]` button dropped. The earlier flow's cancel left the user in a
  half-enrolled state (the bug noted above); with atomic finalize there is
  nothing to cancel. The only exits become: complete enrollment, or log out
  (still allowlisted by the mandatory-2FA gate).
- `[ 2FA / TOTP ]` link removed from `/settings` Row 1 Right. The page it opened
  is gone (no manage page, no disable, no backup-codes rotation surface). The
  Security column in Row 1 Right now carries just `[ sessions ]` and
  `[ locations ]`. The mandatory-enrollment flow does not go through this link —
  the gate's auto-open modal on `/settings?enroll_totp=1` handles enrollment
  forcing.
- Stale management surfaces deleted.
  `Settings::Security::TotpBackupCodesController`
  - its views (`new`, `show`); `Settings::Security::TotpsController#show` /
    `#destroy_screen` / `#destroy_confirmed` + their views; the routes
    `GET /settings/security/totp/show`, `PATCH /settings/security/totp/confirm`,
    `GET|POST /settings/security/totp/disable`, and the three
    `/settings/security/totp_backup_codes` routes. The
    `Sessions::AuthConcern::TOTP_SETUP_ALLOWLIST` shrinks from 6 entries to 4
    (the `/show` GET and the `/confirm` PATCH are gone).
- New rake task `pito:user:regenerate_backup_codes[username]`. Lives alongside
  the existing `pito:user:reset_totp` in `lib/tasks/pito.rake`. Calls
  `Auth::BackupCodeRegenerator`, prints the 10 fresh codes once with a "save
  them now — cannot be retrieved later" header, idempotent, exits non-zero on
  unknown username and on a not-enrolled target. The existing
  `pito:user:reset_totp` is untouched (still the full-wipe path).
- The `/settings/security` (security dashboard) view drops the `[manage 2FA]`
  bracketed link — the page it pointed to is gone. The status line stays as
  read-only context.
- The Rack::Attack `settings/totp` throttle stays in place (10
  POST/PATCH/PUT/DELETE per 15 minutes per IP under `/settings/security/totp*`).
  The regex is broad enough to keep the surviving `POST /settings/security/totp`
  enrollment finalize in the bucket; the throttle's per-path-comment block was
  rewritten to reflect the slimmed surface.

### Files touched

Modified (Ruby + ERB):

- `app/controllers/settings/security/totps_controller.rb` — rewrite.
- `app/views/settings/security/totps/new.html.erb` — rewrite (2-row layout, no
  breadcrumb, no cancel, single atomic form).
- `app/views/settings/_security_pane.html.erb` — drop the `[ 2FA / TOTP ]`
  launcher.
- `app/views/settings/security/show.html.erb` — drop the `[manage 2FA]` link.
- `app/controllers/concerns/sessions/auth_concern.rb` — shrink the
  `TOTP_SETUP_ALLOWLIST` to the surviving routes.
- `app/controllers/concerns/recent_totp_verification.rb` — drop the stale
  doc-comment reference to `destroy_confirmed`.
- `config/routes.rb` — drop the deleted routes; update the comment block.
- `config/initializers/rack_attack.rb` — refresh the per-path comment under the
  `settings/totp` throttle.
- `lib/tasks/pito.rake` — new `pito:user:regenerate_backup_codes[username]`
  task.

Deleted (Ruby + ERB):

- `app/controllers/settings/security/totp_backup_codes_controller.rb`.
- `app/views/settings/security/totp_backup_codes/new.html.erb`.
- `app/views/settings/security/totp_backup_codes/show.html.erb`.
- `app/views/settings/security/totps/show.html.erb`.
- `app/views/settings/security/totps/destroy_screen.html.erb`.

Modified specs:

- `spec/lib/tasks/pito_rake_spec.rb` — adds the
  `pito:user:regenerate_backup_codes` describe block (9 examples).
- `spec/routing/settings_security_totp_routing_spec.rb` — pins the two surviving
  routes; pins the seven deleted routes as not-routable.
- `spec/views/settings/_security_pane_html_erb_spec.rb` — drops the
  `[ 2FA / TOTP ]` launcher assertions; pins the two surviving launchers.
- `spec/requests/totp_gate_spec.rb` — updates the allowlist describe block to
  match the slimmed surface; swaps the "configured user keeps the chrome"
  example for "configured user is redirected away from the enrollment view".
- `spec/system/fresh_seed_first_login_spec.rb` — rewrites the enrollment portion
  of the first-login journey to match the atomic-finalize flow (read the seed
  out of `Rails.cache`, fill in the code, click `[ enable 2FA ]` once).
- `spec/system/settings_refactor_spec.rb` — flip the modal-launcher assertion to
  expect the `[ 2FA / TOTP ]` launcher to be ABSENT.
- `spec/requests/settings/enroll_totp_auto_open_spec.rb` — stale test that
  expected the modal's default title to surface "two-factor setup required" on
  the hub render replaced with two fresh assertions: the modal title slot stays
  empty in mandatory mode (Concern 1 polish) and the headline lives inside the
  Turbo-Frame body fetched from `/settings/security/totp`.
- `spec/system/settings_enroll_totp_gate_spec.rb` — same swap as above for the
  system-shell version of the assertion.

Deleted specs:

- `spec/requests/settings/security/totps_spec.rb` (covers removed show / confirm
  / disable surfaces).
- `spec/requests/settings/security/totp_backup_codes_spec.rb` (covers the
  removed backup-codes management surface).
- `spec/system/totp_2fa_journey_spec.rb` (covers the dropped disable
  - regenerate-backup-codes flows; the surviving enroll-only flow is already
    pinned by `fresh_seed_first_login_spec.rb`).
- `spec/initializers/rack_attack_totp_throttle_spec.rb` (the throttle itself
  stays — see `config/initializers/rack_attack.rb` — but the examples were keyed
  on the deleted disable + backup-codes POSTs).

### Targeted specs

`bundle exec rspec spec/lib/tasks/pito_rake_spec.rb` — 27/27 pass (including the
9 new `pito:user:regenerate_backup_codes` examples).
`bundle exec rspec spec/routing/settings_security_totp_routing_spec.rb spec/views/settings/_security_pane_html_erb_spec.rb spec/requests/totp_gate_spec.rb spec/requests/settings/enroll_totp_auto_open_spec.rb spec/requests/settings/totp_modal_layout_spec.rb spec/requests/settings/totp_gates_spec.rb spec/system/settings_enroll_totp_gate_spec.rb`
— all green. Per user direction: no parallel-suite run for this dispatch.

### Rubocop

`bundle exec rubocop` on every touched `.rb` / `.rake` / spec file — 9 files
inspected, no offenses detected. ERB files are non-Ruby-parseable and excluded.

### Brakeman

`bundle exec brakeman -q -w2` — same single medium-confidence SQL injection
warning in `app/queries/games/genre_shelf_batch.rb:82` (pre-existing, out of
scope here). No new warnings introduced.

### Restart reminder

Yes — routes + controller + autoload changed. Operators on `bin/dev` should
restart Puma after pulling so the router picks up the dropped
`/settings/security/totp/{show,confirm,disable}` and
`/settings/security/totp_backup_codes*` routes and the autoloader forgets the
deleted `Settings::Security::TotpBackupCodesController` constant.

### Open issues

- None for this dispatch. The mandatory-2FA gate behavior is unchanged at the
  redirect level — only the per-route allowlist shrunk and the destination view
  collapsed.

## 2026-05-16 — 01i sessions revamp v2 (inline-in-Security-pane + remember drop)

Spec slug: `sessions-revamp-v2` (in-conversation dispatch; user-locked scope, no
architect spec file).

### Implemented

- New migration `db/migrate/20260516135916_drop_session_remember_column.rb`
  drops the `sessions.remember` boolean column. Reversible (re-adds the column
  at `default: false, null: false`). Migrated dev + test databases;
  `db/schema.rb` updated.
- `Session.create_for!` signature collapses to `(user:, ip:, user_agent:)` — the
  `remember:` keyword is gone, and a stray `remember:` call raises
  `ArgumentError`. `Session::REMEMBER_ME_TTL` constant deleted.
- `Auth::SessionActivator.call` drops the `remember:` keyword (signature now
  `(user:, request:)`).
- `SessionsController` drops the `remember_me` form param read, the `remember:`
  plumbing on `write_session_cookie` / `write_pre_auth_marker` /
  `bootstrap_first_login_session`, and the cookie's conditional `expires:`
  attribute. Session cookies are session-only now.
- `Login::TotpChallengesController` mirrors the same shape — drops the
  `@pre_auth_marker[:remember]` read and the cookie's `expires:`.
- `Sessions::TokenRotation` concern drops the `session_row.remember?` branch in
  the cookie rewrite.
- `app/views/sessions/new.html.erb` (the `/login` form) drops the
  `<input type="checkbox" name="remember_me">` block and the "remember me on
  this device (30 days)" label.
- `_security_pane.html.erb` rewritten: helper copy block gone (`2FA: …`,
  `active sessions: …`, the modal-vs-direct prose), the `[ sessions ]` modal
  launcher gone, and the sessions table renders INLINE inside the pane's
  `<fieldset>`. Columns: checkbox / user-agent / pinged /
  ip-as-`<code class="inline-code">`. The `active` column was dropped (visible
  rows are filtered to active-only) and the `remember` column was dropped along
  with the database column. Sortable headers drive `?sessions_sort=…` /
  `?sessions_dir=…` on `/settings` itself (no controller-collision with future
  sortable surfaces on the same URL).
- `SettingsController#index` now provides `@sessions` / `@sessions_sort` /
  `@sessions_dir` via a small allowlisted-sort helper trio
  (`SESSIONS_ALLOWED_SORTS` / `SESSIONS_ALLOWED_DIRS`). The scope is
  `Current.user.sessions.active_sessions`.
- `Settings::SessionsController` deleted entirely (the surviving bulk-revoke
  flow already lives in `Settings::Sessions::BulkRevokesController`).
- `app/views/settings/sessions/{index,revoke}.html.erb` deleted.
- `Settings::Sessions::BulkRevokesController` repoints every redirect from
  `settings_sessions_path` to `settings_path`. The confirmation view
  `bulk_revokes/show.html.erb` is no longer wrapped in
  `turbo_frame_tag "settings_modal_frame"` — it renders as a standalone
  top-level confirmation page, with `cancel_path: settings_path`. The IP cell
  uses `<code class="inline-code">`.
- Routes: `resources :sessions, only: %i[index destroy]` plus the
  `member { get :revoke }` block are dropped from `config/routes.rb`. Only
  `/settings/sessions/revokes/:ids` (GET + POST → bulk_revokes) stays.
  `Rails.application.routes.recognize_path` for the dropped paths raises
  `ActionController::RoutingError` (covered in the request spec).
- New ViewComponents extracted for future reuse:
  - `YesNoBadgeComponent` — thin wrapper over `StatusBadgeComponent` that
    coerces a boolean (or yes/no/1/0/true/false string) into a green `[yes]` /
    muted `[no]` badge. Pairs with the project's yes/no boundary rule.
  - `ActiveBadgeComponent` — thin wrapper rendering `active` (or a `label:`
    override) with green (`:success`) styling. Both delegate to
    `StatusBadgeComponent` so styling and a11y stay consistent.
- New CSS rule
  `code.inline-code { background-color: var(--color-bg-alt); padding: 1px 4px; border-radius: 2px; }`
  in `app/assets/tailwind/application.css`. Mirrors the inline-code visual the
  markdown-preview surface uses.
- `sessions-bulk-revoke` Stimulus controller comment block refreshed — the
  modal-frame reasoning is gone; the controller still constructs the same
  `/settings/sessions/revokes/<ids>` href and drives header / row checkbox
  state.
- New rake task `pito:sessions:list[state]` in `lib/tasks/pito.rake`. Default
  behaviour (no arg): active only. Optional `state` ∈
  `{active, revoked, expired, all}`. Tabular stdout output (columns id / user /
  user-agent / ip / pinged / created-at); a `state` column appears only when
  `state=all`. Mirrors the `pito:tokens:list` / `pito:oauth_apps:list`
  operator-friendly format. Unknown state → stderr + non-zero exit.
- `spec/lib/tasks/pito_rake_spec.rb` adds a 12-example block for
  `pito:sessions:list` covering every state, footer count, singular
  pluralization, conditional `state` column, empty-state copy, unknown-state
  error path, idempotence, and the operator-username rendering.

### Specs added / rewritten

- `spec/components/yes_no_badge_component_spec.rb` (new, 11 examples) — boolean
  rendering, string-boundary coercion (`yes`/`true`/`1`/ string-`1`/etc.),
  structural chrome (one span, no bracket chars).
- `spec/components/active_badge_component_spec.rb` (new, 6 examples) — default
  `active` label + green styling, `label:` override.
- `spec/views/settings/_security_pane_html_erb_spec.rb` rewritten to cover the
  dropped helper copy, dropped `[ sessions ]` / `[ 2FA / TOTP ]` /
  `[ locations ]` launchers, dropped modal-trigger Stimulus wiring, and the
  empty-state ("no active sessions."). Rich rendered rows are covered in the
  `/settings` request spec because the view-spec wrapper has no controller route
  context for `sort_link_to`.
- `spec/requests/settings/sessions_spec.rb` rewritten — removed the standalone
  index / per-row revoke coverage (those routes are gone). Kept + retargeted
  bulk-revoke confirmation + create coverage (single + multi, current-session
  inclusion, cancel, already-revoked skip, cross-user scoping). Added
  inline-code IP rendering assertion. Added routing-table negative guards for
  `GET /settings/sessions`, `DELETE /settings/sessions/:id`,
  `GET /settings/sessions/:id/revoke` via
  `Rails.application.routes.recognize_path`.
- `spec/requests/settings_spec.rb` extended — Security pane row asserts now
  check the inline-table contract (bulk-revoke controller mount, idle `[revoke]`
  toolbar, column headers user-agent / pinged / ip, no `active` / `remember`
  headers, no helper copy).
- `spec/requests/sessions_spec.rb` — the `name="remember_me"` assertion flipped
  to `not_to include`. The two `remember_me=yes / true` tests collapsed into a
  single "cookie has no `expires=` regardless of stray remember_me param" test.
  `name="password"` field-name typo (`login_password`) left alone —
  pre-existing.
- `spec/models/session_spec.rb` — `respects remember=true` deleted (orphan),
  `does not pass a tenant: keyword` retargeted to assert the minimal kwarg
  surface `(user:, ip:, user_agent:)` and adds a defense-in-depth "rejects a
  stray remember: keyword" test.
- `spec/services/auth/session_activator_spec.rb` — `honors remember: true` +
  `defaults remember to false` deleted (orphans).
- `spec/system/settings_refactor_spec.rb` — "renders the security modal
  launchers" retargeted: no link for sessions or locations; presence of
  `data-controller="sessions-bulk-revoke"` on the pane; TOTP-only modal skeleton
  still mounted.
- `spec/system/leader_menu_spec.rb` — `/settings/sessions` removed from the
  audit path list (the standalone page is gone).
- `spec/factories/sessions.rb` — `remember { false }` line deleted.
- `spec/support/auth.rb` — `sign_in_as(user, remember: false)` signature
  simplified to `sign_in_as(user)`.
- `spec/requests/concerns/sessions/auth_concern_spec.rb`,
  `spec/lib/sessions/authenticator_spec.rb`,
  `spec/system/settings_enroll_totp_gate_spec.rb`,
  `spec/system/settings_profile_totp_gate_spec.rb` — every `, remember: false`
  argument on `Session.create_for!` calls stripped (the kwarg is gone).
- `app/jobs/session_stale_sweeper_job.rb` — `STALE_AFTER` comment refreshed to
  drop the `REMEMBER_ME_TTL` reference (constant is gone); the 30-day
  operational bound stays.

### Orphan specs deleted

None deleted in this dispatch. Every orphan-equivalent assertion was _retargeted
in place_ (the file still serves a purpose post-revamp — the model spec still
covers `create_for!`; the activator spec still covers session minting; the
sessions request spec still covers the bulk-revoke flow). Per the standing rule
the deletions that did happen are application files, not specs:

- `app/controllers/settings/sessions_controller.rb`
- `app/views/settings/sessions/index.html.erb`
- `app/views/settings/sessions/revoke.html.erb`

### Files modified / deleted / created

- Application code modified: `app/models/session.rb`,
  `app/services/auth/session_activator.rb`,
  `app/controllers/sessions_controller.rb`,
  `app/controllers/login/totp_challenges_controller.rb`,
  `app/controllers/concerns/sessions/token_rotation.rb`,
  `app/controllers/settings_controller.rb`,
  `app/controllers/settings/sessions/bulk_revokes_controller.rb`,
  `app/jobs/session_stale_sweeper_job.rb`, `app/views/sessions/new.html.erb`,
  `app/views/settings/_security_pane.html.erb`,
  `app/views/settings/sessions/bulk_revokes/show.html.erb`,
  `app/javascript/controllers/sessions_bulk_revoke_controller.js`,
  `app/assets/tailwind/application.css`, `config/routes.rb`, `db/schema.rb`.
- Application code created:
  `db/migrate/20260516135916_drop_session_remember_column.rb`,
  `app/components/yes_no_badge_component.rb`,
  `app/components/active_badge_component.rb`, `lib/tasks/pito.rake` (new
  `pito:sessions:list[state]` task).
- Application code deleted: `app/controllers/settings/sessions_controller.rb`,
  `app/views/settings/sessions/index.html.erb`,
  `app/views/settings/sessions/revoke.html.erb`.
- Specs modified: `spec/factories/sessions.rb`, `spec/support/auth.rb`,
  `spec/models/session_spec.rb`, `spec/services/auth/session_activator_spec.rb`,
  `spec/requests/sessions_spec.rb`, `spec/requests/settings_spec.rb`,
  `spec/requests/settings/sessions_spec.rb`,
  `spec/requests/concerns/sessions/auth_concern_spec.rb`,
  `spec/lib/sessions/authenticator_spec.rb`, `spec/system/leader_menu_spec.rb`,
  `spec/system/settings_refactor_spec.rb`,
  `spec/system/settings_enroll_totp_gate_spec.rb`,
  `spec/system/settings_profile_totp_gate_spec.rb`,
  `spec/views/settings/_security_pane_html_erb_spec.rb`,
  `spec/lib/tasks/pito_rake_spec.rb`.
- Specs created: `spec/components/yes_no_badge_component_spec.rb`,
  `spec/components/active_badge_component_spec.rb`.

### Targeted specs

`bundle exec rspec spec/models/session_spec.rb spec/services/auth/session_activator_spec.rb spec/components/yes_no_badge_component_spec.rb spec/components/active_badge_component_spec.rb`
— 43/43 pass.

`bundle exec rspec spec/requests/settings/sessions_spec.rb` — 13/13 pass.

`bundle exec rspec spec/views/settings/_security_pane_html_erb_spec.rb spec/requests/settings_spec.rb`
— 48/48 pass.

`bundle exec rspec spec/lib/tasks/pito_rake_spec.rb` — 39/39 pass (includes the
12 new `pito:sessions:list` examples).

`bundle exec rspec spec/requests/sessions_spec.rb spec/requests/concerns/sessions/auth_concern_spec.rb spec/requests/login/totp_challenges_spec.rb spec/system/leader_menu_spec.rb spec/system/settings_refactor_spec.rb spec/requests/settings/security_spec.rb`
— 131/131 pass.

`bundle exec rspec spec/lib/sessions spec/services/auth spec/controllers/concerns/sessions spec/jobs/session_stale_sweeper_job_spec.rb`
— 126/126 pass.

`bundle exec rspec spec/system/settings_enroll_totp_gate_spec.rb spec/system/settings_profile_totp_gate_spec.rb`
— 13/13 pass.

### Brakeman

`bin/brakeman -q -w2` — same single medium-confidence SQL injection warning in
`app/queries/games/genre_shelf_batch.rb:82` (pre-existing, out of scope here).
No new warnings introduced.

### IP-as-code mechanism

A new generic CSS rule `code.inline-code` was added to
`app/assets/tailwind/application.css`. Wrapping IP values in
`<code class="inline-code">…</code>` gives them the project's `--color-bg-alt`
swatch + 2px-rounded inline padding — the same visual the
`.markdown-preview code` rule already produces for inline-code in rendered
markdown, but generic so any short monospace data value (ids, short tokens) can
adopt it without markdown context.

### Restart reminder

Yes — routes + autoload (deleted controller) + migration all changed. Operators
on `bin/dev` should:

1. `bin/rails db:migrate` to drop the `sessions.remember` column.
2. Restart Puma so the router forgets the dropped `/settings/sessions` index /
   destroy / revoke routes and the autoloader forgets the deleted
   `Settings::SessionsController` constant.

### Open issues

- None for this dispatch. The bulk-revoke confirmation page is intentionally a
  standalone top-level navigation now (no Turbo Frame wrap) — a quiet
  behavioural change worth flagging on the manual playbook: clicking
  `[ revoke N ]` from the Security pane navigates to a dedicated confirm screen
  instead of a modal swap.

## 2026-05-16 — Phase 32 closeout: settings polish wave + beta-3 inaugural

Long iterative `/settings` polish + cleanup wave that closes Phase 32 ("simplify
and spread the settings page", step 5 of the beta-2 nine-step roadmap) and marks
the inaugural milestone of beta-3 (page-by-page revamp, subtraction over
addition). The session bracketed by version bump `0.0.1.beta2` → `0.0.1.beta3`
in `/VERSION` (single source of truth — Rails footer + Astro website both read
this file).

No architect spec file backs this closeout — the work was a conversation-locked
polish pass over the previously-shipped sub-specs 01 / 01g / 01h / 01i. Captured
here as a single session entry so the log has a "settings is done; beta-3 starts
here" marker.

### Functional changes

- Session-revoke flow converted from action screen to modal in the Security
  pane. Compact, dynamic title, the "includes current session" warning split to
  two lines, button label `[revoke]` not `[confirm revoke]`.
- Reindex modal moved out of the broadcast partial into a page-level mount in
  `_stack_pane.html.erb`. Fixes the CSRF token going stale across job-context
  renders (the broadcast re-render lost session context, so the form's
  `authenticity_token` aged out).
- Session-revoke modal gained a Stimulus `refreshCsrf` action that copies the
  live `<meta name="csrf-token">` into the form's hidden `authenticity_token`
  input on submit — belt-and-suspenders against session rotation between page
  render and submit.
- Help modal (the `?`-toggled keyboard-shortcuts overlay) deleted entirely. The
  leader menu is now the sole keyboard-discovery affordance.
- Footer `[_]` button no longer triggers the help modal — only opens the leader
  menu.
- Keyboard-shortcuts gate moved from an inline body `<script>` to
  `<meta name="pito-enroll-totp-gate">` in `<head>`. Each Stimulus controller
  does a live per-keypress read via a shared helper. Follow-up fix:
  `leader_menu_controller#connect`'s early-return guard removed (was bailing
  during the Turbo Drive permanent- element swap window before `hasPopupTarget`
  was true).
- Webhook URL clear flow: blank URL submit clears the integration and zeroes
  both flags via a model `before_validation` invariant. New
  `flags_require_webhook_url` defense-in-depth validator. Distinct `cleared` vs
  `updated` flash copy.
- Webhook copy `deliver every notification` → `every notification`.
- New migration
  `db/migrate/20260516180000_allow_null_webhook_url_on_notification_delivery_channels.rb`
  relaxes NOT NULL on the URL column to let the invariant land.
- Stack-pane table CSS rebuilt with a new design — right-align both header label
  and body cells for numeric columns; sort arrow escapes the cell via absolute
  positioning (`top: -10px; right: 0`); no per-pixel tuning needed. Sortable +
  stats tables coexist under one shared rule set with named CSS vars
  (`--stack-cell-padding: 8px`, `--stack-arrow-top: -10px`,
  `--stack-arrow-right: 0`). The Sessions table opted into the same family via a
  `.sessions-table` marker class.
- Logout link removed from the header (lives in the leader menu only).
- TOTP gate enrollment lost the logout escape-hatch form (intentional
  minimization — the gate's allowlist still covers the logout route).
- `LoginAttempt` model + the MCP tools + the digest section dropped entirely
  (Phase 25 rollback — the surface accreted past its useful weight and the
  operator-facing signal is now captured via session rows + audit logs).
- IP column dropped from the sessions table; replaced by an inline
  `TooltipBadgeComponent`.

### Infrastructure changes

- New `.rspec` default `--tag ~type:system` to skip system specs in the local
  fast loop.
- CI workflow overrides the default with
  `-- --options /dev/null --require spec_helper` so CI still runs the full
  suite.
- New `bin/test-prepare` shim caches `db:test:prepare` invocation based on
  `db/schema.rb` mtime.
- New `bin/test` wrapper with shortcuts: `bin/test` / `bin/test failed` /
  `bin/test all` / `bin/test path/...`.
- `CLAUDE.md` gained a "Spec workflow" subsection (already edited by the
  architect — out of docs-keeper scope).
- `docs/agents/rails.md` gained a "Spec invocation" subsection (already edited
  by the architect — out of docs-keeper scope).

### Sweep

- Orphan code sweep deleted `Pito::Auth::IpPrefix`,
  `Pito::Auth::UserAgentParser`, `Auth::TotpDisabler` (+ specs).
- Stale `SESSIONS_ALLOWED_SORTS "ip"` entry trimmed.
- Dead `seeds.rb` comment block (pointing at a removed
  `pito:drop_seeded_channels` rake) deleted.
- Three stale `Auth::TotpDisabler` doc-comments refreshed.

### Specs

- Comprehensive coverage added for the webhook clear invariant: 7 model + 4
  validator + 6 Discord + 6 Slack + 4 system examples.
- Reindex modal mount invariant covered with 3 new examples in
  `spec/requests/settings_spec.rb` — modal mounted once, lives outside the
  broadcast target, carries a session-bound CSRF token.
- 49 spec drift failures fixed across 5 clusters:
  - webhook help guide copy,
  - `platform_ownership` view-locals shape,
  - channels bracketed-URL cells,
  - confirm-modal cancel as `<button>` not `<a>`,
  - navbar logout removal ripple,
  - TOTP-gate escape-hatch ripple,
  - password reset `:pending` trait removal,
  - digest composer login-attempts removal,
  - calendar `[note]` link removal,
  - `google_oauth` empty-state copy change,
  - `steam-shelf` `<h2>` hoisted,
  - `deletions/games` `Sidekiq.inline!` wrap,
  - MCP filter test data fix.

### Version

- `/VERSION` bumped `0.0.1.beta2` → `0.0.1.beta3`. Inaugural beta-3 milestone —
  the page-by-page subtraction cycle starts here with `/settings` as the first
  page completed.

### Phase status

- Phase 32 plan checkboxes (01, 01g, 01h, 01i) are all ticked. This closeout
  session does not add a new checkbox — the polish pass spans every sub-spec
  rather than introducing a new one.
- Phase closes here. Next page in the beta-3 revamp picks up in the next active
  phase log (Phase 33 — help affordance — per the beta-2 roadmap, or whatever
  lane the user greenlights next).

### Restart reminder

Yes — initializer + autoload + migration changes all landed in this session.
Operators on `bin/dev` should:

1. `bin/rails db:migrate` (picks up the `notification_delivery_channels.url` NOT
   NULL relaxation).
2. Restart Puma so the meta-tag-based keyboard gate, the dropped `LoginAttempt`
   autoload, and the reindex-modal mount swap all take effect.

### Open issues

- None blocking. The stack-table CSS rebuild introduces a sort-
  arrow-escapes-cell pattern via absolute positioning that may inform other
  table surfaces; not promoted to an ADR — see the docs-keeper closeout report
  for the rationale.
