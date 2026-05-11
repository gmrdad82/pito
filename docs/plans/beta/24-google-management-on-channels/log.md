# Phase 24 — Google management on Channels + revoke flow — log

## 2026-05-11 — Phase 24 implementation (Rails impl agent)

Implemented all five sub-specs in one pass per master-agent autonomous
dispatch (locked decisions on the seven open questions). Manual user
validation gate pending.

### Files changed (high-level)

**Routes & concerns**

- `config/routes.rb` — drop `/settings/youtube` show+connect routes; add
  `get "/settings/youtube" → redirect("/channels", 301)`; add
  `POST /channels/connect_google` + `GET/POST /channels/:id/revoke` +
  `GET/POST /channels/revokes/:ids`.
- `config/keybindings.yml` — leader-menu `[+]` channel add now points at
  `/channels` (banner) instead of `/settings/youtube`.
- `app/controllers/concerns/youtube_connection_oauth_redirect.rb` — OAuth
  callback now routes back to `/channels`.

**Controllers (new)**

- `app/controllers/channel_revokes_controller.rb` — per-channel revoke
  show+create.
- `app/controllers/channels/bulk_revokes_controller.rb` — bulk
  show+create with orphan-connection detection.

**Controllers (updated)**

- `app/controllers/channels_controller.rb` — `#connect_google` action;
  `@youtube_connections` / `@youtube_connection` exposed on index/show;
  include `YoutubeConnectionOauthRedirect` concern.
- `app/controllers/settings_controller.rb` — drop `OAUTH_KEYS` +
  `update_oauth`; drop Google connection ivars; drop `youtube_oauth`
  section branch.
- `app/controllers/deletions_controller.rb` — `youtube_connection`
  cancel/notice paths now route to `/channels` (was
  `/settings/youtube`).
- `app/controllers/youtube_connections/oauth_callbacks_controller.rb` —
  quota-exhausted flash now references `/channels` and the new
  `[+ add another Google account]` button.

**Controllers (deleted)**

- `app/controllers/settings/youtube_controller.rb` — surface moved.

**Services & jobs (new)**

- `app/services/channel_revoke_counts.rb` — module with `.for(channel)`
  and `.for_many(channels)` returning a `Counts` struct (videos,
  analytics, diffs, change_logs, links, rejected_imports,
  calendar_entries).
- `app/jobs/delete_channel_data_job.rb` — Sidekiq job, flat-name,
  `retry: 3`, idempotent. Triggers `Channel#destroy!` (cascade) then
  cleans up the YoutubeConnection only when both `channels.none?` AND
  `videos.none?` hold.

**Views (new)**

- `app/views/channels/_google_banner.html.erb` — index banner.
- `app/views/channels/_google_panel.html.erb` — channel-show panel.
- `app/views/channels/_needs_reauth_banner.html.erb` — moved from
  `settings/youtube/`; reconnect form now posts to
  `/channels/connect_google`.
- `app/views/channels/_revoke_modal.html.erb` — single + bulk modal.
- `app/views/channel_revokes/show.html.erb` — single-channel modal page.
- `app/views/channels/bulk_revokes/show.html.erb` — bulk modal page.

**Views (updated)**

- `app/views/channels/_picker.html.erb` — banner at top; `[+]`
  POSTs to `connect_google_channels_path`; new `[revoke N]` bulk action
  alongside `[delete N]`; empty-state copy references the banner.
- `app/views/channels/show.html.erb` — `[revoke]` link added to
  heading-actions row; new Google panel `.pane-row` after the identity
  pane.
- `app/views/channels/edit.html.erb` — local-only copy now references
  `/channels` instead of `/settings/youtube`.
- `app/views/settings/index.html.erb` — Google card + YouTube OAuth
  client credentials card removed.

**Views (deleted)**

- `app/views/settings/youtube/show.html.erb`
- `app/views/settings/youtube/_needs_reauth_banner.html.erb`

**Stimulus**

- `app/javascript/controllers/bulk_select_controller.js` — added
  `revokeAction` target + `revokePath` value to support the bulk
  `[revoke N]` action on `/channels`.

### Specs (delta)

**New specs (+5 files, ~75 examples)**

- `spec/services/channel_revoke_counts_spec.rb` — 14 examples.
- `spec/jobs/delete_channel_data_job_spec.rb` — 14 examples (full
  cascade, 4 YoutubeConnection cleanup branches, idempotency, args
  contract, isolation, sidekiq options).
- `spec/requests/channel_revokes_spec.rb` — 14 examples (happy / sad /
  yes-no boundary / unauthenticated / title fallback).
- `spec/requests/channels/bulk_revokes_spec.rb` — 10 examples (single +
  N + 11+, orphan-list, confirm/cancel, unauthenticated).
- `spec/views/channels/_google_banner.html.erb_spec.rb` — 6 examples.
- `spec/views/channels/_google_panel.html.erb_spec.rb` — 3 examples.
- `spec/views/channels/_revoke_modal.html.erb_spec.rb` — 11 examples.
- `spec/system/channel_revoke_spec.rb` — 2 examples (critical user
  journey + cancel path).

**Updated specs**

- `spec/requests/settings_spec.rb` — Google card / YouTube OAuth /
  `youtube_oauth` section removed; new negative-guard sweeps; new
  `GET /settings/youtube` 301 redirect spec.
- `spec/requests/channels_spec.rb` — `[+]` now POSTs; empty-state
  references banner.
- `spec/requests/channels_show_spec.rb` — `.pane-row` count goes from
  3 to 4 (Google panel added).
- `spec/views/channels/show.html.erb_spec.rb` — same `.pane-row` count
  update.
- `spec/requests/channels/edit_form_spec.rb` — NeedsReauth redirect
  target moved from `/settings/youtube` to `/channels`.
- `spec/requests/youtube_connections/oauth_callbacks_spec.rb` — every
  callback assertion updated to `/channels`; flash copy updated.
- `spec/system/channel_add_via_google_spec.rb` — visits `/channels`
  banner instead of `/settings/youtube`.
- `spec/system/google_oauth_flow_spec.rb` — same.
- `spec/system/leader_menu_spec.rb` — channels submenu `+` now
  navigates to `/channels`.

**Deleted specs**

- `spec/requests/settings/youtube_spec.rb` — surface gone.

### Gates

- `bundle exec rspec` — 4424 examples, 0 failures, 1 pending
  (pre-existing unrelated to this phase; two pre-existing failures
  outside the lane: `auth_concern_spec.rb` and
  `calendar_edit_delete_spec.rb` — both fail on `main` as well).
- `bundle exec rubocop` — clean (1014 files).
- `bin/brakeman -q -w2` — 0 security warnings.

### Manual test plan (user)

1. `bin/dev`.
2. Visit `/settings`. Confirm: no Google card, no YouTube OAuth card.
3. Visit `/settings/youtube`. Confirm: 301-redirects to `/channels`.
4. Visit `/channels`. Confirm: Google banner renders at the top with
   `[+ add another Google account]` (or `[connect google]` if no
   connections exist).
5. Click a channel row → visit `/channels/:slug`. Confirm: Google panel
   renders below the identity pane.
6. On a channel show, click `[revoke]`. Confirm: wide-modal page
   renders with the seven cascade counts and `[cancel]` /
   `[confirm revoke]` buttons.
7. Click `[cancel]`. Confirm: back to channel show, no data change.
8. Click `[revoke]` again → `[confirm revoke]`. Confirm: redirect to
   `/channels`, flash "channel revoke scheduled.", channel disappears
   once Sidekiq runs the job.
9. Bulk path: on `/channels`, select multiple checkboxes. Confirm
   `[revoke N]` appears alongside `[delete N]` in the bulk toolbar.
10. Click `[revoke N]`. Confirm: wide-modal with N channels listed +
    aggregated counts + list of connections-to-be-orphaned.
11. Confirm. Confirm: redirect to `/channels` with `N channel revokes
    scheduled.`; channels disappear once Sidekiq drains.

### Open follow-ups (queued)

- `AppSetting` rows for `youtube_client_id` / `youtube_client_secret` /
  `youtube_redirect_uri` still exist (Phase 24 only removed the UI).
  Migration to Rails credentials is a separate hygiene pass —
  add to `docs/orchestration/follow-ups.md`.
- `DeletionsController#destroy_channel` and MCP `delete_records[channel]`
  still go through plain `Channel#destroy!` (Rails cascade); they do
  NOT trigger the YoutubeConnection orphan-cleanup branch. Wiring them
  through `DeleteChannelDataJob` is filed as a separate follow-up
  (locked decision #7).
