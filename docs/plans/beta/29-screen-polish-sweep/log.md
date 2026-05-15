# Phase 29 — Screen Polish Sweep — Log

> Session entries land here as Lane A units close. Append-only after user
> validation.

## 2026-05-14 — Unit A0 Channel read-only conversion: Rails impl landed

Spec: `specs/channel-read-only-conversion.md`. The three open questions were
resolved by the master agent: Q1 — no CLI compat shim; Q2 — drop only the
`channel_diffs` table, keep the channel attribute columns; Q3 — trim
`calendar_reminder_spec.rb` rather than delete (its calendar-entries-endpoint
block is unrelated to the channel edit form).

The channel is now a strictly one-way, read-only mirror (YouTube to pito). Every
edit / preview / banner / watermark / diff-reconciliation surface is gone.
`star` is the one mutable channel attribute and now rides a dedicated
`channel_star` path.

### Files deleted (25 app + 20 spec)

App — diff reconciliation: `channel_diff.rb`, `channels/previews_controller.rb`,
`channels/diff_apply.rb` / `diff_computer.rb` / `diff_persister.rb`,
`channel_diff_check_job.rb`, `channels/diff.html.erb`,
`channels/_open_diff_banner.html.erb`, `channels/_in_sync_banner.html.erb`,
`notification_formatter/templates/channel_diff_detected.rb`. App — edit /
preview / banner / watermark: `channel_preview_component.*`,
`watermark_preview_component.*`, `channels/edit.html.erb`,
`channels/_form.html.erb`, `_form_errors`, `_banner_upload`,
`banner_updated.turbo_stream.erb`, the `channel_preview` / `banner_upload` /
`links_repeater` / `reminder_link` Stimulus controllers, `preview_helper.rb`.
MCP (the one narrow forced exception): `mcp/tools/channel_diff_show.rb` +
`channel_diff_apply.rb` — their backing table is dropped, so they are physically
gone, not just deferred. MCP tool discovery is glob-based, so no registry edit
was needed. Specs: the 19 dead diff / preview / edit-form / watermark / banner /
MCP-diff specs plus `spec/factories/channel_diffs.rb`.

### Files modified (notable)

- `config/routes.rb` — `:channels` shrunk to `[:index, :show, :destroy]`;
  removed `:edit`, `:update`, `get :diff`, `patch :apply_diff`, the
  `resource :preview`; added
  `resource :star, only: :update, controller: "channels/stars", as: :channel_star`
  (PATCH `/channels/:id/star`, helper `channel_star_path`).
- `app/controllers/channels_controller.rb` — removed `edit`, `update`, `diff`,
  `apply_diff` and every private method that served only them (the whole
  star-toggle dispatch, watermark / banner / links handling, `coerce_*`,
  `extract_diff_decisions_param`, `diff_detail_json`, the `PERMITTED_EDIT_KEYS`
  constant). No write action remains.
- `app/controllers/channels/stars_controller.rb` — new. The only channel write
  path. Yes/no boundary enforced inline; assigns only `star`; removed attributes
  in the params are silently ignored.
- `app/models/channel.rb` — dropped the `channel_diffs` association,
  `open_channel_diff`, the `title_locked?` / `handle_locked?` /
  `title_unlock_at` / `handle_unlock_at` gate methods and the
  `TITLE_HANDLE_LOCK_WINDOW` constant.
- `app/helpers/channels_helper.rb` — dropped `title_gate_open?`,
  `handle_gate_open?`, `title_unlock_date`, `handle_unlock_date`,
  `channel_reminder_name`.
- `app/views/channels/show.html.erb` — removed the `[ e ]` edit link and the
  `channel_diff_banner` Turbo frame slot; `[ sync ]` href is now plain
  `/syncs/channel/:id` (no `intent=diff_check`).
- `app/views/channels/_pane.html.erb` — the inline `[star]` / `[unstar]` form
  repointed at `channel_star_path`.
- `app/controllers/syncs_controller.rb` — dropped `"channel"` from
  `DIFF_CHECK_JOBS`; channel `[sync]` is `overwrite`-only now.
- `app/services/notification_formatter/templates.rb` — dropped the
  `channel_diff_detected` registry line.
- `app/models/notification.rb` — removed the `channel_diff_detected` (kind 10)
  enum value; left a comment reserving the integer slot.
- `config/sidekiq_cron.yml` — removed the `channel_diff_check` cron.
- `app/services/channel_revoke_counts.rb` — the `diffs` count category is now
  video-side only (the `ChannelDiff` constant reference was a direct consequence
  of the table drop; the spec's file list missed it).
- `app/jobs/delete_channel_data_job.rb`, `app/views/shared/_diff_table.html.erb`
  — stale `channel_diffs` / `ChannelDiff` comment references trimmed.
- Migration: `db/migrate/20260514164940_drop_channel_diffs.rb` — drops
  `channel_diffs`, reversible `up`/`down`. Applied to the dev DB; `db/schema.rb`
  regenerated clean.

### Specs added

- `spec/requests/channels/star_spec.rb` — the surviving star-only write path:
  HTML + JSON happy paths, bad-boundary 422 / flash-alert,
  removed-attributes-ignored proof, star callbacks, slug + integer-id
  resolution.
- `spec/requests/channels/read_only_routes_spec.rb` — the removed route helpers
  are gone, the removed routes are not reachable, the surviving routes still
  resolve.
- `spec/migrations/drop_channel_diffs_spec.rb` — table dropped + the migration
  is reversible.
- `spec/system/channels/read_only_channel_spec.rb` — no edit form at
  `/channels/:id/edit`, no edit affordance / diff banner on show, the pane
  `[star]` / `[unstar]` toggle works end-to-end.
- Updated: `channel_spec.rb`, `channels_helper_spec.rb`,
  `channels_show_spec.rb`, `channels_spec.rb`, `show.html.erb_spec.rb`,
  `channel_show_journey_spec.rb`, `syncs_diff_check_spec.rb`,
  `delete_channel_data_job_spec.rb`, `channel_revoke_counts_spec.rb`,
  `calendar_reminder_spec.rb` (trimmed per Q3).

### Result

`bundle exec rspec` — 8614 examples, 1 pending; the 25 remaining failures are
all pre-existing (verified by stashing the A0 change and re-running them on a
clean tree — same 25 fail) in unrelated surfaces (composites, webhooks, games,
settings panes, calendar, seeds, OAuth flow, tokens, numeric-formatting lint).
Every A0-touched spec (491 examples) is green. `bundle exec rubocop` clean on
all touched files.

### Open issues / follow-ups

- `db/structure.sql` still lists `channel_diffs`. The repo's migration flow only
  maintains `db/schema.rb` (the `:ruby` schema format); recent migrations (e.g.
  `drop_deprecated_notification_kinds`) likewise did not update `structure.sql`.
  Left as-is to match the established flow — `structure.sql` appears orphaned
  and should be either removed or wired into the dump on a separate pass.
- Orphaned `.watermark-*` / `channel-preview` CSS rules remain in
  `app/assets/tailwind/application.css`. Dead but harmless (dead CSS does not
  500); left out of A0 to keep the blast radius tight, same posture the spec
  took with `youtube/client.rb`. Follow-up tidy-up.
- `youtube/client.rb`'s `#update_channel` / `#set_watermark` /
  `#unset_watermark` / `#upload_banner` are now unused by Rails — a later
  tidy-up pass per the spec.
- The paused `pito` CLI still PATCHes `/channels/:id.json` for its star toggle;
  that route is gone. Recorded deferred consequence (Q1 — no shim); the CLI gets
  repointed at `/channels/:id/star.json` when the surface un-pauses.
- MCP note: `channel_diff_show` / `channel_diff_apply` are physically deleted,
  not just deferred — the MCP-unpause spec should treat them as already gone.
- `docs/architecture.md` channel section and `docs/mcp.md` (`channel_diff_*`
  tools) describe the now-cut surface — flagged for the docs pass (out of
  `pito-rails` scope).

## 2026-05-14 — Unit A1 AppSetting → credentials consolidation: Rails impl landed

Spec: `specs/appsetting-credentials-consolidation.md`. All four master-resolved
decisions were already folded into the spec body and implemented as written:
drop the YouTube OAuth / Voyage / Google-console config from `AppSetting` (7
columns total), rewrite the Slack/Discord delivery gate to derive from the
`NotificationDeliveryChannel` row, slim the Voyage Settings pane to the
non-secret indexing toggle, and adopt the flat `google_oauth:` + per-env
`voyage:` credentials shape. Open questions resolved per the spec's defensible
calls: Q1 — dropped the dead `:youtube, :public_api_key` fallback; Q2 —
`youtube_credentials_updated` enum value 7 left reserved in `AuthAuditLog`,
removed from `Auth::AuditLogger`'s active allowlist; Q3 — kept the
`credentials.notifications.*_webhook_url` dispatcher fallback; Q4 — included the
defensive re-encrypt migration.

The project's stated configuration strategy is restored: secrets live
exclusively in `Rails.application.credentials`; `AppSetting` carries
runtime-mutable, non-secret config only. Google / YouTube OAuth config is now
deploy-time credentials config (closes follow-up 3 — the omniauth hot-rotation
gap — by accepting the tradeoff). The latent Slack/Discord delivery bug is
fixed: the gate was reading orphaned `AppSetting.*_enabled` columns the webhook
controllers never wrote, so delivery was silently dead; it now derives from the
`NotificationDeliveryChannel` row (existence + present `webhook_url` + at least
one routing flag).

### Files

Migrations created (2): `DropCredentialColumnsFromAppSettings` (drops
`voyage_api_key`, `youtube_api_key`, `youtube_client_id`,
`youtube_client_secret`, `youtube_redirect_uri`, `slack_enabled`,
`discord_enabled`; reversible — `remove_column` carries original type/options),
`ReencryptNotificationWebhookUrls` (defensive data migration, re-saves every
`notification_delivery_channels` row through the encrypting writer; no-op in
practice, `down` is a clean no-op). Both applied to the dev DB; `db/schema.rb`
reflects the drop.

App modified (8): `app/models/app_setting.rb` (drop the `encrypts`
declarations + the `youtube_*` accessors + `voyage_target_flags_require_key`;
`voyage_configured?` re-sourced from credentials;
`slack_/discord_delivery_enabled?` rewired to the channel row),
`config/initializers/omniauth.rb` (drop `pito_appsetting_youtube_value`;
three-tier credentials-first resolver),
`app/services/youtube/token_refresher.rb`

- `app/services/youtube/public_client.rb` (read `credentials.google_oauth`
  directly), `app/jobs/notes/embed_job.rb` (`resolve_api_key` reads
  `credentials.voyage[env]`), `app/controllers/settings_controller.rb` (drop the
  `youtube` branch + `update_youtube` + `YOUTUBE_FIELDS` +
  `update_appsetting_section` + `collect_appsetting_attrs` +
  `youtube_credentials_status` + `@youtube_credentials`; `update_voyage` slimmed
  to a focused flag-only writer that keeps the `voyage_credentials_updated`
  audit row), `app/services/auth/audit_logger.rb`
- `app/models/auth_audit_log.rb` (`youtube_credentials_updated` removed from the
  active allowlist, enum value 7 reserved).

Views modified (1): `app/views/settings/index.html.erb` — the YouTube
credentials pane removed; the Voyage.ai pane slimmed (API key field + key-clear
checkbox gone, indexing toggle kept, `section=voyage` hidden field kept). The
Slack/Discord panes + the search-pane Voyage status block untouched.

Deleted (1): `lib/tasks/youtube_credentials_backfill.rake` — the backfill
direction reversed; credentials are the source of truth again.

Seeds modified (1): `db/seeds.rb` — the Voyage AppSetting bootstrap block
removed (only the AppSettings section, lines ~24-44; the owner / dev-token /
Platform / sample-data sections untouched, left for A2).

### Specs

Modified: `spec/models/app_setting_spec.rb` (dead-columns-are-gone regression +
`voyage_configured?` credentials-driven + the Slack/Discord gate predicate truth
table via a shared example), `spec/models/notification_delivery_channel_spec.rb`
(probabilistic encryption assertion added), `spec/initializers/omniauth_spec.rb`
(AppSetting-accessor + resolver-rescue blocks dropped, credentials-first
resolver + boot smoke kept), `spec/jobs/notes/embed_job_spec.rb` (stubs
`:voyage` credentials instead of the dropped column),
`spec/services/youtube/public_client_spec.rb` (credentials-only key resolution),
`spec/services/auth/audit_logger_spec.rb` (active allowlist

- a rejection spec for the retired action),
  `spec/services/notification_delivery_channel/{slack,discord}_spec.rb` +
  `spec/jobs/notification_deliver_spec.rb` (gate driven by the channel row),
  `spec/requests/settings_spec.rb` (YouTube pane absent, Voyage pane slimmed,
  pane count 13→12, `section=youtube` legacy no-op, Voyage flag-only audit),
  `spec/requests/settings/totp_gates_spec.rb` (`section=youtube` no longer
  gated, `section=voyage` writes the flag). Added:
  `spec/migrations/drop_credential_columns_from_app_settings_spec.rb`,
  `spec/migrations/reencrypt_notification_webhook_urls_spec.rb`,
  `spec/system/settings_webhooks_spec.rb` (Slack/Discord panes render + save,
  YouTube pane absent, Voyage pane slimmed).

### Credentials the operator must provision

A1 implements the _code_ that reads credentials; the operator must add the
_values_ via `bin/rails credentials:edit` before the app boots:

- `google_oauth.client_id` + `google_oauth.client_secret` (flat block, not
  per-env) — REQUIRED, the omniauth initializer raises at boot without them (CI
  / local-no-DB can substitute `PITO_GOOGLE_OAUTH_CLIENT_ID` /
  `PITO_GOOGLE_OAUTH_CLIENT_SECRET`; the test env has a built-in placeholder).
- `google_oauth.api_key` — needed for `Youtube::PublicClient` (`configured?` is
  false without it; the client raises `NotConfiguredError` when invoked).
- `google_oauth.redirect_uri` — optional; omniauth falls back to the production
  callback URL when blank.
- `voyage.development.api_key` / `voyage.production.api_key` — per-env;
  `Notes::EmbedJob` no-ops cleanly when blank, so the test env key is optional.
- `notifications.slack_webhook_url` / `notifications.discord_webhook_url` —
  optional transitional fallback only; the source of truth for Slack/Discord is
  the `NotificationDeliveryChannel` row.

### Result

`bundle exec rspec` — 8587 examples, 24 failures, 1 pending. Every A1-touched
spec is green; the 24 residual failures match the pre-existing baseline recorded
in the A0 entry above (composites, webhook-help, games / platform_ownerships,
the `_slack_pane` / `_discord_pane` view specs — partials A1 deliberately did
not touch — calendar, OAuth flow, tokens, numeric-formatting lint) and are
unrelated to A1. `bundle exec rubocop` clean on all 25 touched files.

The user must restart `bin/dev` for manual testing — A1 changes the omniauth
initializer, the routes-adjacent controller surface, and the autoloaded
model/service code.

### Open issues / follow-ups

- Docs pass owed (out of `pito-rails` scope): `CLAUDE.md` "Configuration
  strategy" + "Active follow-ups" (follow-up 3 closed; follow-up 9 Voyage half
  resolved), a new ADR recording the reversal of ADR 0007
  (`youtube-credentials-moved-to-appsetting`), `docs/setup.md` (YouTube / Voyage
  via `credentials:edit`, not the Settings UI), `docs/auth.md` if it references
  the dropped audit action, `config/application.rb` l.61-66 comment
  (`voyage_configured?` is no longer DB-backed for the key half).
- The `_slack_pane` / `_discord_pane` view specs fail on the suite baseline (a
  `nav-sep` middle-dot assertion) — pre-existing, unrelated to A1, and A1 was
  explicitly forbidden from touching those partials. Left for whoever owns the
  webhook-pane polish screen.

## 2026-05-14 — Unit A2 User auth refactor: Rails impl landed (specs not green — STOP+report)

Spec: `specs/user-auth-refactor.md`. All four resolved decisions (R1–R4)
implemented as written. Production code is complete and rubocop-clean; the full
suite is NOT at the ~24 baseline because the mandatory-2FA gate shifts the
entire test baseline far beyond the spec's enumerated regression list — flagged
for a follow-up decision.

### Production code (complete, rubocop-clean on 56 touched Ruby files)

- Migration `20260514185800_swap_user_email_for_username.rb` — drops
  `users.email` + `index_users_on_email`, adds `username` (citext, NOT NULL) +
  unique `index_users_on_username`. Written to survive a non-empty table (adds
  nullable, backfills `user_<id>`, then NOT NULL) so a stale dev DB migrates
  cleanly; applied to dev DB.
- `LoginAttempt.reason` — `first_login_totp_setup_required` added as integer
  value 15. Integer-backed enum → MODEL-ONLY edit, no migration (Migration 2 not
  needed).
- `AuthAuditLog.action` — `password_reset` added as value 9 (Open question 1
  default (a)); `Auth::AuditLogger::VALID_ACTIONS` extended. Integer-backed → no
  migration.
- `User` — `email` validations / `EMAIL_MAX_LENGTH` / `strip_email_whitespace`
  removed; `username` validations (presence, length 3..32, format
  `/\A[a-z0-9_]+(?:[.-][a-z0-9_]+)*\z/i`, case-insensitive uniqueness) +
  `normalize_username` (strip + downcase) added; `totp_configured?` alias;
  `totp_uri` provisions against `username`.
- `SessionsController` — username plumbing throughout; R4 first-login bootstrap
  (`bootstrap_first_login_session` mints an active session directly for a
  no-TOTP `:new_location` user, redirects to TOTP setup, records
  `first_login_totp_setup_required`). Backoff key prefix `email:` → `username:`.
- `Sessions::AuthConcern` — `require_totp_configured!` `before_action` after
  `authenticate_session!`, with `TOTP_SETUP_ALLOWLIST` (totps
  new/create/show/confirm + `DELETE /session`). Browser-only; `Api::AuthConcern`
  / `Mcp::RackApp` untouched (R3).
- `PasswordResetsController` (new) + 4 routes — reset-via-2FA: live TOTP code OR
  backup code (consumed, R1), short-lived signed reset marker (cookie +
  `Rails.cache` nonce), revokes every session on success, no auto-login, no
  existence oracle, constant-time dummy bcrypt on the unknown branch.
- `rack_attack.rb` — `password/ip` (5/min) + `password/username` (10/15min,
  hashed) throttles; `throttled_responder` `password/` branch renders generic
  `reset failed.`; `login/email` throttle re-keyed to `username`.
- `lib/tasks/pito.rake` — `pito:user:reset_totp[username]` operator task (clears
  all four `totp_*` columns, destroys backup codes, revokes sessions, prints
  confirmation, non-zero exit on unknown username, idempotent).
- `db/seeds.rb` — owner block reads `credentials.owner.{username, password}`;
  project-workspace sample + `now playing` collection blocks deleted (A2-scoped
  sections only; A1's AppSettings block untouched).
- Views: `sessions/new`, `settings/user/show`, `settings/index`,
  `channels/change_logs/index.html.erb` + `.json.jbuilder` swapped
  email→username; `password_resets/new` + `edit` added.
- Minimal column-gone fixes (MCP paused, but `user.email` is a 500):
  `totp_status` / `channel_changes_list` / `auth_audit_log_list` tools,
  `notification_source/login_pending_approval`, `session_activator`,
  `session_pending_approver`, `pending_session_expirer`, `attempt_logger`,
  `rate_limit_logger`.
- `email_attempted` COLUMN on `login_attempts` kept (not in the spec's
  files-touched table); it now carries the typed username.

### Open issue — full suite NOT at baseline (the blocker)

`bundle exec rspec` — 8654 examples, **112 failures**, 1 pending (baseline per
A1's entry: 8587 / 24). Every A2-owned NEW spec is green (`user_spec`,
`login_attempt_spec`, `auth_audit_log` value, `totp_gate_spec`,
`password_resets_spec`, `pito_user_reset_totp`, `swap_user_email_for_username`
migration spec) and the A2-touched existing specs I updated are green. The ~88
failures over baseline are **spec-baseline fallout from the mandatory-2FA
gate**, in two clusters the spec's regression list did not enumerate:

1. **302-on-gate cluster (~30 specs).** Many existing specs build their own user
   via `let(:user) { Current.user || create(:user) }` then `sign_in_as(user)` —
   a fresh NON-TOTP user. The mandatory gate now redirects them off every
   non-allowlisted authenticated route. Affected:
   `settings/oauth_applications_spec`, `settings/sessions_spec`,
   `settings/security_spec`, `settings/security/totps_spec`,
   `concerns/sessions/auth_concern_spec`, `application_controller_current_spec`,
   and more — ~74 spec files use this pattern; ~30 fail. Fix: those specs' user
   must be `:totp_enabled`.
2. **`RecentTotpVerification` cluster (~55 specs).** The auto-signed-in user is
   now TOTP-configured (it MUST be, or every authenticated request 302s), which
   activates the `RecentTotpVerification` gate on sensitive writes.
   `settings/slack_webhooks_spec`, `settings/discord_webhooks_spec`,
   `settings_spec` voyage section, `settings/totp_modal_layout_spec` (2FA-off
   scenario) etc. PATCH without a `totp_code` and the write is now rejected.
   Fix: those specs must pass `totp_code: ROTP::TOTP.new(seed).now` (the pattern
   `totp_gates_spec.rb` was updated to — A2 fixed that one file).

The remainder of the 112 (composites, webhook-help, games/ platform_ownerships,
`_slack_pane`/`_discord_pane`, calendar "Document tree depth limit exceeded",
google_oauth_flow, tokens, numeric-formatting) match the pre-existing baseline.

This is genuinely beyond the spec's "Files touched" + "Regression spec list" —
the mandatory-2FA gate makes "an authenticated test user" mean "a
TOTP-configured test user" suite-wide, and that ripples into ~15 spec files the
spec did not call out. Per the implementer STOP-and-report directive: the
production code is done and correct; the master agent should decide between (a)
a focused follow-up spec-fix pass updating the ~15 affected files (mechanical:
swap `create(:user)` → `create(:user, :totp_enabled)` in the own-user specs, add
`totp_code:` to the `RecentTotpVerification`-gated write specs — the same
pattern A2 already applied to `totp_gates_spec.rb`, `settings/user_spec.rb`,
`totp_2fa_journey_spec.rb`, the `login/*` specs, and `spec/support/auth.rb`), or
(b) a global RSpec shim. A2 deliberately did not blanket-edit 15 unenumerated
spec files under uncertainty.

### Not done by A2 (by design)

- `bin/brakeman` — not run (suite not green; deferred to the post-spec-fix pass
  / reviewer).
- `plan.md` A2 checkbox — NOT ticked (acceptance criterion "all regression specs
  green in CI in the same commit" is not met).
- Docs (`CLAUDE.md`, `docs/auth.md`, `docs/setup.md`) + the ADR — flagged for
  the `pito-docs` pass, not edited.
- `:owner` credentials block — the operator must add
  `owner: { username:, password: }` via `bin/rails credentials:edit` for
  development AND test before `db:seed` / running the suite manually.

### Restart needed

Yes — `bin/dev` must be restarted for manual testing: new routes, a migration,
and autoloaded model/controller/concern changes.

## 2026-05-15 — Lane A wave consolidation: A0 + A1 + A2 closeout + parallel fixer pass + baseline status

Master-agent-level summary sitting on top of the three implementer-narrow
entries above (2026-05-14 A0, 2026-05-14 A1, 2026-05-14 A2). The three units
landed in working-tree form ahead of the master review; this entry captures the
wave's shape, the parallel fixer pass, and the partial verification baseline
reconciliation as a single reference point.

**Done:**

- Unit A0 — Channel read-only conversion. The channel is now strictly a one-way
  YouTube → pito mirror; every edit / preview / banner / watermark /
  diff-reconciliation surface deleted (25 app files + 20 spec files removed,
  `channel_diffs` table dropped). The only mutable channel attribute is `star`,
  served by the new `Channels::StarsController`
  (`PATCH /channels/:channel_id/star`). `/channels/:id/history` survives.
- Unit A1 — `AppSetting` → credentials consolidation. Five credential-bearing
  columns dropped from `app_settings` (`voyage_api_key`, `youtube_api_key`,
  `youtube_client_id`, `youtube_client_secret`, `youtube_redirect_uri`) plus two
  orphaned dead columns (`slack_enabled` / `discord_enabled`). YouTube / Voyage
  / Google console credentials live in `Rails.application.credentials` again;
  the Slack/Discord delivery gate now derives from the
  `NotificationDeliveryChannel` row (fixing a latent delivery bug — the old gate
  read columns the controllers never wrote). The Settings YouTube pane is gone;
  the Voyage pane is slimmed to the `voyage_index_project_notes` indexing
  toggle.
- Unit A2 — User auth refactor. `users.email` → `users.username` (citext, format
  `/\A[a-z0-9_]+(?:[.-][a-z0-9_]+)*\z/i`, length 3..32, downcased on write);
  TOTP is mandatory from first login via
  `Sessions::AuthConcern#require_totp_configured!` (browser-only, allowlist
  covers the enrollment endpoints + logout); reset-via-2FA is the
  password-recovery surface (`PasswordResetsController`, accepts live TOTP or
  single-use backup code, rate-limited, no auto-login, no username-existence
  oracle, revokes every session on success);
  `bin/rails pito:user:reset_totp[<username>]` is the operator escape hatch for
  the lost-device-and-codes lockout. `LoginAttempt.reason` gained
  `first_login_totp_setup_required` (value 15) for the R4 first-login bootstrap
  branch; `AuthAuditLog.action` gained `password_reset` (value 9).
- Parallel fixer pass — dispatched after A2 left the suite ~88 above baseline
  (mandatory-2FA gate fallout into ~15 spec files the spec did not enumerate).
  The fixer pass updated own-user specs to use `:totp_enabled` and
  `RecentTotpVerification`-gated write specs to pass `totp_code:` on the form,
  the same pattern A2 applied to `totp_gates_spec.rb`. Suite returned to the
  documented baseline cluster.
- Verification baseline (partial — 2026-05-15 01:57 run, 5580 examples) recorded
  at `/home/catalin/Dev/pito/tmp/verification/baseline-2026-05-15.md`. 6
  failures + 1 pending, every failure maps onto the documented standing cluster
  list (numeric-formatting lint, calendar, composites, games, OAuth-flow /
  settings panes). The verification agent crashed before reporting; recovered by
  reading the log directly. The enumeration is folded into
  `docs/agents/testing.md` "Current known baseline".

**Decisions:**

- ADR 0007 (YouTube credentials on `AppSetting`) superseded by new ADR 0012
  (`docs/decisions/0012-revert-appsetting-credentials-to-rails-credentials.md`).
  Hot-rotation was the original motivation; it never actually worked (omniauth
  read at boot), and the storage-pattern drift cost was higher than the rotation
  benefit. Accepted tradeoff: YouTube + Voyage become deploy-time config,
  rotated via `bin/rails credentials:edit` + Puma restart.
- Phase 29 R3 — the mandatory-2FA gate applies to browser sessions only; API
  tokens and MCP bearer credentials are NOT gated. `Api::AuthConcern` /
  `Mcp::RackApp` untouched. A token is minted by an already-authenticated
  browser user who is themselves gated upstream.
- Phase 29 R4 — first-login bootstrap. A no-TOTP fresh-seed user skips
  new-location approval (approval is meaningless without an established account)
  and gets an active session minted directly so the mandatory-2FA gate can force
  enrollment. `LoginAttempt.reason = first_login_totp_setup_required` records
  the forensic trace.
- Phase 29 R1 — reset-via-2FA accepts a backup code in place of a live TOTP
  code. Single-use; the backup-code consumer stamps `used_at` under a row lock.
  A user who lost the authenticator app but kept backup codes still has a
  recovery path; a user who lost both is the operator rake task's domain.
- Active follow-ups #3 (YouTube credentials hot-rotation gap) and #9 (Voyage
  AppSetting revamp) are resolved by A1 and now closed.
- The `_slack_pane` / `_discord_pane` view specs fail on a `nav-sep` middle-dot
  assertion in the baseline — pre-existing, unrelated to any Lane A unit,
  deferred to the webhook-pane polish surface.

**Next:**

- Reviewer + security playbooks land under `docs/orchestration/playbooks/` in
  parallel with this docs pass (different filenames — no collision).
- Full parallel verification run (8 processes) once the Lane A wave is
  committed; that run becomes the next authoritative reconciliation for
  `docs/agents/testing.md` "Current known baseline".
- User validation of A0 + A1 + A2 together (manual playbook); master commits
  after validation.
- `db/structure.sql` orphan question (A0 follow-up) — either remove the file or
  wire it into the dump on a separate pass. Recent migrations have not
  maintained it; the established flow is `db/schema.rb` only.
- Orphaned `.watermark-*` / `channel-preview` CSS in
  `app/assets/tailwind/application.css` (A0 follow-up) — dead but harmless,
  queued for a tidy-up pass.
- `Youtube::Client#update_channel` / `#set_watermark` / `#unset_watermark` /
  `#upload_banner` (A0 follow-up) — unused by Rails now, queued for the same
  tidy-up pass.
- Paused `pito` CLI star toggle still PATCHes the old `/channels/:id.json` route
  (A0 recorded deferred consequence per Q1 — no shim). Repoint at
  `/channels/:id/star.json` when the CLI surface un-pauses.
- MCP `channel_diff_show` / `channel_diff_apply` are physically deleted (A0);
  the MCP-unpause spec must treat them as already gone, not just deferred.

## 2026-05-15 — A2 security fix-pass (F1, F2, F4, F6)

Consolidated security follow-up from
`docs/orchestration/playbooks/security-2026-05-15-auth-refactor.md`. Closes the
four actionable findings on the A2 auth refactor (F3 is shell-history hygiene
guidance only, F5 / F7 / F8 are informational). The brakeman surface stays at
the pre-existing 1-warning baseline (Games genre shelf raw SQL — out of scope
for this lane). No new findings introduced.

**Done:**

- F1 (High) — `PasswordResetsController#update` now revokes every `ApiToken`,
  `Doorkeeper::AccessToken`, and `Doorkeeper::AccessGrant` belonging to the
  user alongside their cookie sessions, via `update_all` on the bulk path. The
  `AuthAuditLog` row carries revocation tallies in metadata
  (`sessions_revoked`, `api_tokens_revoked`, `oauth_access_tokens_revoked`,
  `oauth_access_grants_revoked`).
- F1 (High) — `lib/tasks/pito.rake pito:user:reset_totp` mirrors the same
  bearer-credential revocation block under the existing transaction. Now
  also emits a `password_reset` `AuthAuditLog` row (acting_user + target =
  the affected user; `source_surface = :tui`; metadata carries
  `source: "rake:pito:user:reset_totp"` + the revocation tallies). The
  success print now includes the tallies.
- F2 (Medium) — `PasswordResetsController#create` wrong-code branch now pays
  `bcrypt_dummy_compare` BEFORE rendering the generic failure, symmetrizing
  wall-clock cost with the unknown-username / no-TOTP bail branches. Closes
  the timing oracle that previously distinguished "has TOTP" from
  "doesn't exist / no TOTP" via response latency.
- F6 (Low) — `bcrypt_dummy_compare` extracted from `SessionsController` and
  `PasswordResetsController` into a new shared concern at
  `app/controllers/concerns/sessions/bcrypt_dummy_compare.rb`. Both
  controllers `include Sessions::BcryptDummyCompare`. A single call site for
  the helper eliminates the drift risk between the two surfaces (which F2's
  fix relies on).
- F4 (Low) — `config/initializers/rack_attack.rb` `password/*` branch of the
  `throttled_responder` now calls `Auth::RateLimitLogger.call(request:, username:)`,
  writing a `LoginAttempt` row on every password-reset throttle hit (same
  pattern the `login/*` branch already followed). Reuses
  `LoginAttempt.reason = :rate_limited`; no enum migration. The body still
  carries the generic `reset failed.` HTML — no rate-limit leak.

**Files changed (rails impl):**

- `app/controllers/password_resets_controller.rb` — F1 (bearer revocation),
  F2 (wrong-code dummy compare), F6 (include shared concern, drop local body).
- `app/controllers/sessions_controller.rb` — F6 only (include shared concern,
  drop local body).
- `app/controllers/concerns/sessions/bcrypt_dummy_compare.rb` — new shared
  concern (F6).
- `lib/tasks/pito.rake` — F1 (bearer revocation + `AuthAuditLog` row in the
  rake task) and the success-print update.
- `config/initializers/rack_attack.rb` — F4 (`Auth::RateLimitLogger` call in
  the `password/*` branch of the throttled responder).

**Regression specs (mandatory):**

- `spec/controllers/concerns/sessions/bcrypt_dummy_compare_spec.rb` — new.
  10 examples; pins shared-helper shape + both controllers' inclusion + the
  `instance_method(:bcrypt_dummy_compare).owner` invariant so a future
  re-introduction of a local body is caught.
- `spec/requests/password_resets_spec.rb` — extended with the F1 group
  (revokes ApiToken / OAuth access tokens / OAuth access grants, preserves
  already-revoked rows, audit-log metadata tallies, no-revoke-on-failure)
  and the F2 group (wrong-code path and wrong-shape-code path both call
  through `bcrypt_dummy_compare`).
- `spec/lib/tasks/pito_rake_spec.rb` — extended with the F1 rake group
  (same shape as the controller F1 group: token / OAuth revocation, audit
  log, print line).
- `spec/initializers/rack_attack_login_throttle_spec.rb` — extended with the
  F4 group (password/ip + password/username throttle hits both write
  `LoginAttempt` rows; the response body still has no rate-limit leak).

**Quality gate evidence:**

- `bundle exec rubocop` on every touched file (9 files): no offenses.
- `bin/brakeman -q -w2`: 1 warning total, same pre-existing Games genre-shelf
  raw-SQL pattern reported on the prior baseline. No new findings.
- `bundle exec parallel_rspec spec/ -n 8` (final full-suite pass,
  `/tmp/pito-parallel-rspec-2026-05-15.log`): 8680 examples, 18 failures,
  1 pending. All 18 failures map onto the standing baseline clusters
  (`docs/agents/testing.md`): 1 numeric-formatting lint, 2 calendar, 1
  composites / deletions games branch, 2 games (steam-shelf + 9 platform-
  ownerships view failures — `platforms.any?` on a nil collection,
  unrelated to this lane), 1 OAuth flow, 1 tokens, 2 settings panes
  (`_slack_pane` / `_discord_pane` nav-sep middle-dot). Well within the
  documented 24/1 baseline and below the most-recent 20/1 capture.

**Notes:**

- The Doorkeeper API used in tests is the project's `OauthApplication`
  factory (`spec/factories/oauth_applications.rb`) — `Doorkeeper::Application`
  directly would fail the `ActiveRecord::AssociationTypeMismatch` guard
  because of the `Doorkeeper.configure { application_class "OauthApplication" }`
  binding in the initializer. Specs use `create(:oauth_application, scopes:
  Scopes::APP)` and `Doorkeeper::AccessToken.create!` for the access-token /
  grant rows.
- F4 deliberately reuses `LoginAttempt.reason = :rate_limited` rather than
  introducing a new enum value (`password_reset_rate_limited`) — the agent
  scope said "do not touch other production files beyond the listed
  surfaces", and a new enum value lives on `app/models/login_attempt.rb`.
  The `email_attempted` field on the row + the IP carries enough forensic
  context to distinguish password-recovery throttle hits from login throttle
  hits in the attempt log. Promoting to a dedicated enum value can ride a
  follow-up architect spec if the operator surface needs the explicit
  partition.

**Next:**

- Master agent reviews the diff and either dispatches `pito-reviewer` for
  a final verification pass, or stages the diff for user validation.
- After user validation, the master commits the security fix-pass alongside
  the A2 unit body (the security playbook explicitly noted "merge with
  fix-forward" — these four findings are the "fix" half).
