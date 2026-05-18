# Beta-3 Lane A — i18n extraction catalog

Audited: 2026-05-18

Scope: /settings + /games areas only. See
`feedback_beta3_three_lane_discipline.md` for the scope contract. Out:
projects, videos, channels, notifications (the page, not toggles),
calendar, home, auth-area (`sessions/`), extras/, docs/, db/, spec/, lib/.

Total extractable strings found: **~280** (185 views, ~55 components,
~35 controllers, ~50 keybindings YAML `label:` fields). Net unique keys
after `common.*` de-dup: **~210**.

Zero `t(…)` calls in the in-scope tree today — surface is virgin.

---

## Per-file string catalog

### app/views/settings/index.html.erb

- L1 (title) `settings` → `settings.index.title` [view]
- L12 `settings` → `settings.index.heading` [view]

### app/views/settings/_profile_pane.html.erb

- L13 `profile` → `settings.profile.heading` [view]
- L31 `username` → `settings.profile.username_label` [label]
- L40 `current password` → `settings.profile.current_password_label` [label]
- L44 `required to authorize the change.` → `settings.profile.current_password_hint` [view]
- L48 `new password` → `settings.profile.new_password_label` [label]
- L52 `leave blank to keep current password.` → `settings.profile.new_password_hint` [view]
- L56 `confirm new password` → `settings.profile.confirm_password_label` [label]
- L62 `[update]` → `common.actions.update` [button]

### app/views/settings/_security_pane.html.erb

- L37 `security` → `settings.security.heading` [view]
- L49 `[revoke]` → `settings.security.revoke_button` [button]
- L77 `user-agent` → `settings.sessions.col_user_agent` [view]
- L78 `pinged` → `settings.sessions.col_pinged` [view]
- L95 tooltip `ip` → `settings.sessions.ip_badge` [label]
- L95 status `this` → `settings.sessions.this_badge` [label]
- L104 `no active sessions.` → `settings.sessions.empty` [view]
- L141 `revoke 0 sessions?` → `settings.sessions.confirm_default_title` [view]
- L143 `this set includes your current session.` → `settings.sessions.confirm_warning_line1` [view]
- L144 `revoking it signs you out.` → `settings.sessions.confirm_warning_line2` [view]
- L169 `revoke` → `common.actions.revoke` [button]
- L171 `cancel` → `common.actions.cancel` [button]

### app/views/settings/_discord_pane.html.erb

- L30 `Discord` → `settings.discord.heading` [view]
- L34 `webhook URL` → `settings.discord.webhook_url_label` [label]
- L47 `[update]` → `common.actions.update` [button]
- L65 `help` → `common.actions.help` [button]
- L73 `type "clear" to remove` → `settings.webhook.clear_hint_html` [view]
- L98 `every notification` → `settings.notification_toggle.everything` [label]
- L113 `daily digest` → `settings.notification_toggle.daily_digest` [label]
- L115 `sent daily at 09:00 in your time zone.` → `settings.notification_toggle.daily_digest_hint` [view]

### app/views/settings/_slack_pane.html.erb

- L27 `Slack` → `settings.slack.heading` [view]
- L31 `webhook URL` → `settings.slack.webhook_url_label` [label]
- L44 `[update]` → `common.actions.update` [button]
- L62 `help` → `common.actions.help` [button]
- L70 `type "clear" to remove` → `settings.webhook.clear_hint_html` [view]
- L91 `every notification` → `settings.notification_toggle.everything` [label]
- L106 `daily digest` → `settings.notification_toggle.daily_digest` [label]
- L109 `sent daily at 09:00 in your time zone.` → `settings.notification_toggle.daily_digest_hint` [view]

### app/views/settings/_settings_modal.html.erb

- L115 `close` → `common.actions.close` [button]

### app/views/settings/_stack_pane.html.erb

- L38 `stack` → `settings.stack.heading` [view]
- L44 `Postgres` → `settings.stack.postgres` [view]
- L46 `▲ connected` → `settings.stack.connected` [view]
- L48 `▽ disconnected` → `settings.stack.disconnected` [view]
- L57 `model` → `settings.stack.col_model` [view]
- L58 `rows` → `settings.stack.col_rows` [view]
- L59 `size` → `settings.stack.col_size` [view]
- L93 `Redis` → `settings.stack.redis` [view]
- L146 `successful` → `settings.stack.sidekiq.successful` [view]
- L149 `failed` → `settings.stack.sidekiq.failed` [view]
- L175 `busy` → `settings.stack.sidekiq.busy` [view]
- L176 `scheduled` → `settings.stack.sidekiq.scheduled` [view]
- L177 `enqueued` → `settings.stack.sidekiq.enqueued` [view]
- L178 `retry` → `settings.stack.sidekiq.retry` [view]
- L179 `dead` → `settings.stack.sidekiq.dead` [view]
- L201 `Meilisearch` → `settings.stack.meilisearch` [view]
- L214 `index` → `settings.stack.col_index` [view]
- L215 `docs` → `settings.stack.col_docs` [view]
- L232 `not yet indexed` → `settings.stack.not_yet_indexed` [view]
- L286 `reindex Meilisearch?` → `settings.stack.reindex_confirm_title` [view]
- L287 `this re-indexes all configured targets.` → `settings.stack.reindex_confirm_body` [view]
- L290 `reindex` → `settings.stack.reindex` [button]
- L291 `cancel` → `common.actions.cancel` [button]
- L299 `assets` → `settings.stack.assets` [view]
- L302 `▲ writable` → `settings.stack.writable` [view]
- L304 `▽ read-only` → `settings.stack.read_only` [view]
- L307 `▽ not present` → `settings.stack.not_present` [view]
- L316 `category` → `settings.stack.col_category` [view]
- L317 `files` → `settings.stack.col_files` [view]
- L353 `notes` → `settings.stack.notes` [view]
- L370 `namespace` → `settings.stack.col_namespace` [view]
- L371 `count` → `settings.stack.col_count` [view]

### app/views/settings/_time_zone_pane.html.erb

- L11 `time zone` → `settings.time_zone.heading` [view]
- L14 `your time zone` → `settings.time_zone.label` [label]
- L36 `common` (optgroup) → `settings.time_zone.optgroup_common` [view]
- L43 `all IANA` (optgroup) → `settings.time_zone.optgroup_all_iana` [view]
- L52 `affects how every time is rendered across pito.` → `settings.time_zone.hint` [view]
- L55 `[update]` → `common.actions.update` [button]

### app/views/settings/_voyage_section.html.erb

- L70 `Voyage AI` → `settings.voyage.heading` [view]
- L72 `▲ configured` → `settings.voyage.configured` [view]
- L74 `▽ not configured` → `settings.voyage.not_configured` [view]
- L82 `metric` → `settings.voyage.col_metric` [view]
- L83 `value` → `settings.voyage.col_value` [view]
- L88 `games embedded` → `settings.voyage.games_embedded` [view]
- L96 `bundles embedded` → `settings.voyage.bundles_embedded` [view]
- L106 `model` → `settings.voyage.model` [view]
- L111 `last indexed` → `settings.voyage.last_indexed` [view]
- L119 `HNSW indexes` → `settings.voyage.hnsw_indexes` [view]
- L121 `KB` (suffix) → `settings.voyage.size_suffix_kb` [view]
- L127 `last 24h` → `settings.voyage.last_24h` [view]
- L129 `embeddings` (suffix) → `settings.voyage.embeddings_suffix` [view]
- L147 `reindexing... started %{time_ago}` → `settings.voyage.reindexing_html` (interpolated) [view]
- L153 `reindex` → `settings.voyage.reindex_action` [button]

### app/views/settings/security/show.html.erb

- L1 (title) `security` → `settings.security.title` [view]
- L2 breadcrumb `settings` → `settings.breadcrumb_root` [view]
- L2 breadcrumb `security` → `settings.security.breadcrumb` [view]
- L6 `security` → `settings.security.heading` [view]
- L9 `2FA` → `settings.security.twofa_label` [view]
- L16 `status:` → `settings.security.status_prefix` [view]
- L18 `on` → `settings.security.status_on` [view]
- L20 `off` → `settings.security.status_off` [view]

### app/views/settings/security/totps/new.html.erb

- L1 (title) `enroll 2FA` → `settings.security.totp.title` [view]
- L52 `two-factor setup required` → `settings.security.totp.heading` [view]
- L54 `pito requires 2FA.` → `settings.security.totp.requires_line1` [view]
- L55 `nothing else is reachable until 2FA is enabled.` → `settings.security.totp.requires_line2` [view]
- L58 `scan with 1Password (or any authenticator app).` → `settings.security.totp.scan_hint` [view]
- L65 `scan` → `settings.security.totp.scan_heading` [view]
- L87 `or paste this seed manually:` → `settings.security.totp.seed_hint` [view]
- L93 `enter code` → `settings.security.totp.enter_code_heading` [view]
- L96 `6-digit code from your authenticator app` → `settings.security.totp.code_label` [label]
- L104 `enable 2FA` → `settings.security.totp.submit` [button]
- L109 `backup codes` → `settings.security.totp.backup_codes_heading` [view]
- L114 `each code works once.` → `settings.security.totp.backup_codes_hint_line1` [view]
- L115 `store them somewhere safe — outside the device that holds your authenticator.` → `settings.security.totp.backup_codes_hint_line2_html` [view]

### app/views/settings/user/show.html.erb

- L1 (title) `user` → `settings.user.title` [view]
- L2 breadcrumb `settings` → `settings.breadcrumb_root` [view]
- L2 breadcrumb `user` → `settings.user.breadcrumb` [view]
- L5 `user` → `settings.user.heading` [view]
- L7 `change your username or password.` → `settings.user.hint_line1` [view]
- L8 `current password is required to authorize the change.` → `settings.user.hint_line2` [view]
- L38 `username` → `settings.profile.username_label` [label]
- L45 `current password` → `settings.profile.current_password_label` [label]
- L49 `required to authorize the change.` → `settings.profile.current_password_hint` [view]
- L53 `new password` → `settings.profile.new_password_label` [label]
- L57 `leave blank to keep current password.` → `settings.profile.new_password_hint` [view]
- L61 `confirm new password` → `settings.profile.confirm_password_label` [label]
- L77 `[update]` → `common.actions.update` [button]
- L78 `cancel` → `common.actions.cancel` [button]

### app/views/games/index.html.erb

- L44 (title) `games` → `games.index.title` [view]
- L63 `games` (H1) → `games.index.heading` [view]
- L65 `+` → `common.actions.add_short` [button]
- L124 `recently played` → `games.index.recently_played_heading` [view]
- L165 `no games match this filter.` → `games.index.no_matches` [view]
- L179 `search games + bundles` (omnisearch placeholder) → `games.omnisearch.placeholder` [placeholder]

### app/views/games/show.html.erb

- L185 `—` em-dash placeholder → `common.em_dash` [view]
- L207 `date` → `games.show.meta.date` [label]
- L210 `dev` → `games.show.meta.dev` [label]
- L212 `pub` → `games.show.meta.pub` [label]
- L221 sync row label `sync` → `games.show.meta.sync` [label]
- L221 `---` syncing placeholder → `games.show.syncing_placeholder` [view]
- L284 `ownership` → `games.show.ownership_heading` [view]
- L312 `igdb error: %{msg}` → `games.show.igdb_error` [view]
- L317 `summary` → `games.show.summary_heading` [view]
- L333 aria-label `time to beat` → `games.show.ttb_aria` [aria]
- L363 aria/heading `bundles` → `games.show.bundles_aria` / `games.show.bundles_heading` [view][aria]
- L379, 409 aria-label `nothing yet` → `games.show.shelf_empty_aria` [aria]
- L380, 410 `nothing` → `games.show.empty_word_nothing` [view]
- L381, 411 `yet` → `games.show.empty_word_yet` [view]
- L401 aria-label `similar games` → `games.show.similar_aria` [aria]
- L402 `similar` heading → `games.show.similar_heading` [view]
- L428 aria/heading `videos` → `games.show.videos_aria` / `games.show.videos_heading` [view][aria]
- L429 `[TBD]` → `common.tbd` [view]
- L57 `[sync]` (muted) → `common.actions.sync` [button]
- L71 `[sync]` (active) → `common.actions.sync` [button]
- L93 `[-]` (delete) → `common.actions.delete_short` [button]
- L457 body `linked videos detach and any bundle composites regenerate. this cannot be undone.` → `games.show.delete_confirm_body` [view]
- L456 title `delete %{title}?` → `games.show.delete_confirm_title` [view]
- L460 confirm `delete` → `common.actions.delete` [button]
- L461 cancel `cancel` → `common.actions.cancel` [button]
- L476 title `resync %{title}?` → `games.show.sync_confirm_title` [view]
- L477 `this will consume from your IGDB request quota.` → `games.show.sync_confirm_body` [view]
- L480 confirm `sync` → `common.actions.sync` [button]
- L498 title `delete %{bundle}?` → `games.show.delete_bundle_confirm_title` [view]
- L498 body `this action cannot be undone.` → `common.delete_irreversible` [view]
- L499 confirm `delete` → `common.actions.delete` [button]

### app/views/games/_shelf.html.erb

- L21 `see all` → `common.actions.see_all` [button]

### app/views/games/_letter_shelves.html.erb / _genres_shelf.html.erb / _genre_sub_shelf.html.erb

- No literal user-facing strings (dynamic).

### app/views/games/_bundles_for_shelf.html.erb

- L36 `bundles` (shelf heading) → `games.bundles_shelf.heading` [view]
- L55 aria-label `create bundle` → `games.bundles_shelf.create_aria` [aria]
- L55 button `+` → `common.actions.add_short` [button]
- L71 title `delete %{bundle}?` → `bundles.delete_confirm_title` [view]
- L72 body `this action cannot be undone.` → `common.delete_irreversible` [view]
- L73 confirm `delete` → `common.actions.delete` [button]
- L74 cancel `cancel` → `common.actions.cancel` [button]

### app/views/games/_bundles_modal.html.erb

- L89 default title `bundle` → `bundles.modal.default_title` [view]
- L92 `change` → `bundles.modal.change_action` [button]
- L104 `-` → `common.actions.delete_short` [button]
- L117 `update` → `common.actions.update` [button]
- L118 `cancel` → `common.actions.cancel` [button]
- L131 `close` → `common.actions.close` [button]

### app/views/games/_search_results.html.erb

- L24 `type to search igdb.` → `games.search.placeholder_igdb` [view]
- L26 `no results for '%{query}'.` → `games.search.no_results` [view]
- L47 `[?]` no-cover sentinel → `games.search.no_cover` [view]
- L59 `update` → `common.actions.update` [button]
- L74 `add` → `common.actions.add` [button]

### app/views/games/_search_results_combined.html.erb

- L21 `type to search.` → `games.omnisearch.placeholder_default` [view]
- L25 `games` (section) → `games.omnisearch.section_games` [view]
- L37, 58 `game` / `bundle` (row chip) → `games.omnisearch.row_kind_game` / `.row_kind_bundle` [view]
- L49 `bundles` (section) → `games.omnisearch.section_bundles` [view]
- L70 `on igdb` (section) → `games.omnisearch.section_igdb` [view]
- L72 `igdb error: %{msg}` → `games.omnisearch.igdb_error` [view]
- L74 `no igdb results for '%{query}'.` → `games.omnisearch.no_igdb_results` [view]
- L94 `open` → `common.actions.open` [button]
- L100 `add` → `common.actions.add` [button]
- L110 `no results for '%{query}'.` → `games.omnisearch.no_results` [view]

### app/views/games/platform_ownerships/edit.html.erb

- L8 (title) `edit ownership: %{title}` → `games.platform_ownerships.edit_title` [view]
- L9 breadcrumb `games`, `edit ownership` → `games.breadcrumb_root`, `games.platform_ownerships.breadcrumb` [view]
- L22 `ownership` → `games.platform_ownerships.heading` [view]
- L40 `save` → `common.actions.save` [button]
- L41 `cancel` → `common.actions.cancel` [button]

### app/views/bundles/show.html.erb

- L19 breadcrumb `games` → `games.breadcrumb_root` [view]
- L26 `-` (bracketed delete) → `common.actions.delete_short` [button]
- L43 `%{count} member` / `members` → `bundles.show.member_count` (ICU plural) [view]
- L49 `regenerating…` → `bundles.show.regenerating` [view]
- L57 `members` heading → `bundles.show.members_heading` [view]
- L63 col `game` → `bundles.show.col_game` [view]
- L64 col `release` → `bundles.show.col_release` [view]
- L75 `no members yet.` → `bundles.show.empty_members` [view]
- L78 `add member` heading → `bundles.show.add_member_heading` [view]
- L80 `pick a game from your library.` → `bundles.show.pick_hint` [view]
- L88 placeholder `search your games…` → `bundles.show.search_placeholder` [placeholder]
- L93 select prompt `—` → `common.em_dash` [view]
- L95 `add` → `common.actions.add` [button]
- L98 `no games match` → `bundles.show.no_games_match` [view]
- L104 `linked videos` heading → `bundles.show.linked_videos_heading` [view]
- L113 `[★]` primary marker → `common.primary_star` [view]
- L119 `no linked videos yet.` → `bundles.show.no_linked_videos` [view]

### app/views/bundles/_search_results.html.erb

- L26 `type to search.` → `games.omnisearch.placeholder_default` [view]
- L30 `in your library` heading → `bundles.omnisearch.section_local` [view]
- L44 `add` → `common.actions.add` [button]
- L56 `on igdb` heading → `games.omnisearch.section_igdb` [view]
- L58 `igdb error: %{msg}` → `games.omnisearch.igdb_error` [view]
- L60 `no igdb results for '%{query}'.` → `games.omnisearch.no_igdb_results` [view]
- L72 `in igdb only` → `bundles.omnisearch.igdb_only` [view]
- L81 `no results for '%{query}'.` → `games.omnisearch.no_results` [view]

### app/views/bundles/create.turbo_stream.erb

- L42 toast `bundle created.` → `bundles.flash.created` [flash]

### app/views/bundles/destroy.turbo_stream.erb

- L41 toast `bundle deleted.` → `bundles.flash.deleted` [flash]

### app/views/deletions/show.html.erb (game / bundle branches only)

- L6 H1 `delete %{count} %{type}(s)` → `deletions.show.heading` (ICU plural) [view]
- L7 body `this will permanently remove this/these %{type}(s) and all associated data.` → `deletions.show.body` [view]
- L34 col `title` (game) → `deletions.show.col.title` [view]
- L35 col `publisher` (game) → `deletions.show.col.publisher` [view]
- L36 col `bundles` (game) → `deletions.show.col.bundles` [view]
- L46 col `name` (bundle) → `deletions.show.col.name` [view]
- L47 col `members` (bundle) → `deletions.show.col.members` [view]
- L87, 90 placeholder `—` → `common.em_dash` [view]
- L125 submit `[-]` → `common.actions.delete_short` [button]

### app/views/syncs/show.html.erb (game branch only)

- L23 H1 `sync %{count} %{type}(s)` → `syncs.show.heading` [view]
- L29 `just kicking off the sync — won't take long.` → `syncs.show.body_overwrite` [view]
- L68 col `title` (game) → `syncs.show.col.title` [view]
- L105 submit `[sync]` → `common.actions.sync` [button]

---

## Components

### app/components/games/cover_component.html.erb / game_tile_component.html.erb

- L37/41/59/63 + L43/49: `no cover available` (alt) → `games.cover.no_cover_alt` [aria]

### app/components/games/bundle_tile_component.rb

- L141 `add to %{bundle}` (aria_label) → `bundles.tile.add_aria` [aria]

### app/components/games/shelf_component.html.erb

- L13 `see all` → `common.actions.see_all` [button]

### app/components/games/editions_badge_component.rb

- L32 `edition` / `editions` → `games.editions_badge.noun` (ICU plural) [view]
- L33 `+%{count} %{noun}` → `games.editions_badge.label` [view]

### app/components/games/editions_section_component.rb

- L27 `editions (%{count})` → `games.editions_section.heading` [view]

### app/components/games/filter_chip_component.html.erb

- L7 `[x]` / `[ ]` → keep as code OR `games.filter_chip.checked|unchecked` [view]
- Chip token labels via `chip_label(token)` (FiltersHelper): `released`, `scheduled`, `owned`, `wishlist`, `played`, `PS`, `Switch`, `Steam` → `games.filters.token.*` [view]

### app/components/games/ownership_matrix_component.html.erb

- L34 `—` em-dash empty → `common.em_dash` [view]
- L61 `owned` → `games.ownership_matrix.owned_label` [label]
- L82 `played` → `games.ownership_matrix.played_label` [label]

### app/components/games/owned_platforms_chip_list_component.html.erb

- L12 `(not owned on any platform)` → `games.owned_platforms.empty` [view]

### app/components/games/platform_ownership_chip_component.html.erb

- L23 title `owned on %{label} — click to remove` → `games.platform_ownership_chip.owned_title` [view]
- L23 title `not owned on %{label} — click to add` → `games.platform_ownership_chip.not_owned_title` [view]

### app/components/games/platform_ownership_editor_component.html.erb

- L24 `(no platforms available)` → `games.platform_ownership_editor.no_platforms` [view]

### app/components/games/played_chip_component.html.erb

- L4 `[played]` → `games.played_chip.label` [view]
- L6 title `played on %{date}` / `not yet played` → `games.played_chip.played_title` / `.not_played_title` [view]

### app/components/games/rating_badge_component.rb

- L56 missing glyph `—` → `common.em_dash` [view]

### app/components/games/time_to_beat_component.rb

- L48 `main` → `games.ttb.main` [view]
- L49 `extras` → `games.ttb.extras` [view]
- L50 `completionist` → `games.ttb.completionist` [view]
- L165 em-dash `—` → `common.em_dash` [view]
- L167/L174 `%{n}h` → `games.ttb.hours_short` [view]
- L180 `footage` → `games.ttb.footage` [view]
- L58 (template) `TTB` watermark → `games.ttb.watermark` [view]

### app/components/games/version_parent_picker_component.html.erb

- L18 placeholder `cannot attach — this row has editions` → `games.version_parent.disabled_placeholder` [placeholder]
- L18 placeholder `type to search primaries…` → `games.version_parent.placeholder` [placeholder]
- L32 `detach` → `games.version_parent.detach` [button]

### app/components/bundles/all_games_table_component.html.erb

- L10 `all games` heading → `bundles.all_games.heading` [view]
- L13 `+` → `common.actions.add_short` [button]
- L45 col `title` → `bundles.all_games.col.title` [view]
- L46 col `genre` → `bundles.all_games.col.genre` [view]
- L47 col `release` → `bundles.all_games.col.release` [view]
- L48 col `score` → `bundles.all_games.col.score` [view]
- L81 `no games yet — click [+] to add` → `bundles.all_games.empty` [view]
- L96 placeholder `add a game to this bundle` → `bundles.all_games.search_placeholder` [placeholder]

### app/components/bundles/all_games_table_component.rb

- L62 `—` → `common.em_dash` [view]

### app/components/platforms/chip_component.rb

- SLUG_BRAND labels: `PS`, `Switch`, `Steam` → `platforms.chip.label.ps` / `.switch` / `.steam` [label]

### app/components/bracketed_muted_link_component.rb

- L28 default label `cancel` → `common.actions.cancel` [button]

### app/components/confirm_modal_component.rb

- L19 default `confirm_label: "-"` → `common.actions.delete_short` [button]
- L20 default `cancel_label: "cancel"` → `common.actions.cancel` [button]

### app/components/status_tbd_badge_component.html.erb

- L1 `[TBD]` → `common.tbd` [view]

---

## Controllers (flash strings)

### app/controllers/settings_controller.rb

- L109 notice `settings saved.` → `settings.flash.saved`
- L138 alert `reindex already in progress.` → `settings.flash.reindex_in_progress`
- L144 notice `reindex started.` → `settings.flash.reindex_started`

### app/controllers/games_controller.rb

- L341 alert `games can only be added via the IGDB search modal.` → `games.flash.igdb_only`
- L351 alert `igdb id must be a positive integer.` → `games.flash.invalid_igdb_id`
- L356 alert `already in your library.` → `games.flash.already_in_library`
- L373 notice `added; metadata loading in background.` → `games.flash.added`
- L375 alert `could not add game.` → `games.flash.create_failed`
- L382 notice `game deleted.` → `games.flash.deleted`
- L395 notice `already resyncing.` → `games.flash.already_resyncing`
- L423 notice `refreshing from igdb…` → `games.flash.refreshing`

### app/controllers/bundles_controller.rb

- L49 notice `bundle updated.` → `bundles.flash.updated`
- L85 notice `bundle created.` → `bundles.flash.created`
- L114/L115 notice `bundle deleted.` → `bundles.flash.deleted`
- L167 default name `unnamed bundle` → `bundles.default_name`

### app/controllers/settings/time_zone_controller.rb

- L28 notice `time zone saved.` → `settings.time_zone.flash.saved`
- L32 alert `invalid time zone` → `settings.time_zone.flash.invalid`

### app/controllers/settings/user_controller.rb

- L34 error `is incorrect.` → `settings.user.errors.current_password_incorrect`
- L47 error `does not match.` → `settings.user.errors.password_mismatch`
- L56 notice `no changes.` → `settings.user.flash.no_changes`
- L61 notice `account updated.` → `settings.user.flash.updated`

### app/controllers/settings/discord_webhooks_controller.rb

- L46 `Pito test ping — Discord webhook configured.` → `settings.discord.test_ping_text`
- L55 `Discord webhook unchanged.` → `settings.discord.flash.unchanged`
- L65 `invalid Discord webhook URL.` → `settings.discord.flash.invalid_url`
- L73 `Discord test ping failed: %{error}.` → `settings.discord.flash.ping_failed`
- L84 `Discord webhook updated.` → `settings.discord.flash.updated`
- L87 `could not save Discord webhook: %{errors}.` → `settings.discord.flash.save_failed`
- L104 `Discord webhook cleared.` → `settings.discord.flash.cleared`
- L107 `could not clear Discord webhook: %{errors}.` → `settings.discord.flash.clear_failed`

### app/controllers/settings/slack_webhooks_controller.rb

- L41 `Pito test ping — Slack webhook configured.` → `settings.slack.test_ping_text`
- L48 `Slack webhook unchanged.` → `settings.slack.flash.unchanged`
- L58 `invalid Slack webhook URL.` → `settings.slack.flash.invalid_url`
- L65 `Slack test ping failed: %{error}.` → `settings.slack.flash.ping_failed`
- L77 `Slack webhook updated.` → `settings.slack.flash.updated`
- L80 `could not save Slack webhook: %{errors}.` → `settings.slack.flash.save_failed`
- L97 `Slack webhook cleared.` → `settings.slack.flash.cleared`
- L100 `could not clear Slack webhook: %{errors}.` → `settings.slack.flash.clear_failed`

### app/controllers/settings/notification_toggles_controller.rb

- L37–45 BRAND_LABELS (`Discord`, `Slack`) + KIND_LABELS (`every notification`, `daily digest`) → `settings.notification_toggle.brand.*`, `.kind.*`
- L53 alert `unknown notification toggle.` → `settings.notification_toggle.flash.unknown`
- L63 notice `%{brand} %{kind} on/off.` → `settings.notification_toggle.flash.toggled`
- L78 alert `could not toggle %{brand} %{kind}.` → `settings.notification_toggle.flash.toggle_failed`

### app/controllers/games/platform_ownerships_controller.rb

- L45 notice `ownership updated.` → `games.platform_ownership.flash.updated`
- L77 error `duplicate platform submitted.` → `games.platform_ownership.errors.duplicate`
- L79 error `unknown platform.` → `games.platform_ownership.errors.unknown_platform`

### app/controllers/games/ownership_toggles_controller.rb

- L70 notice `Game owned on %{platform}.` → `games.ownership_toggle.flash.owned_on`
- L93 notice `Game no longer owned on %{platform}.` → `games.ownership_toggle.flash.no_longer_owned`
- L124 notice `Playing on %{platform}.` → `games.ownership_toggle.flash.playing_on`
- L128 notice `No longer playing on %{platform}.` → `games.ownership_toggle.flash.no_longer_playing`
- L137 alert `could not update played platform.` → `games.ownership_toggle.flash.played_failed`
- L149/L161 alert `unknown platform.` → `games.ownership_toggle.flash.unknown_platform`

### app/controllers/settings/security/totps_controller.rb

- L57/L76 notice `2FA is already on.` → `settings.totp.flash.already_on`
- L86 alert `enrollment expired. start again.` → `settings.totp.flash.expired`
- L128 notice `2FA enrolled.` → `settings.totp.flash.enrolled`
- L137 alert `login failed.` → `settings.totp.flash.login_failed`

### app/controllers/settings/sessions/bulk_revokes_controller.rb

- L44 alert `revoke cancelled.` → `settings.sessions.flash.cancelled`
- L50 alert `nothing to revoke.` → `settings.sessions.flash.nothing`
- L74 notice `session revoked` → `settings.sessions.flash.revoked_one`
- L76 notice `%{count} sessions revoked` → `settings.sessions.flash.revoked_many`

---

## config/keybindings.yml

**Architectural decision required** — file is consumed by BOTH the Rails web
(`leader_menu_controller.js`) AND the Rust `pito` CLI. Three options:

- (a) **Defer.** Leave YAML as-is. Keybindings labels stay literal until the
  Rust client is unpaused. Lane A skips this file. RECOMMENDED — matches
  `project_web_polish_focus.md` Rust pause.
- (b) **Dual.** Keep YAML labels for Rust, also mirror in en.yml for Rails
  web. Risk: drift between the two.
- (c) **Migrate.** Move labels to en.yml, drop from YAML, teach Rust client to
  read en.yml. Big change.

Default action for Phase 2: option (a). Keybindings YAML stays literal.

(If user reverses: labels span per-page `page_actions` + `menus` + `modal_actions`
tree — see file `config/keybindings.yml` for the canonical structure.)

---

## Implementation slicing — 8 parallel impl agents

Each ≤ 15 min wall-clock. Each owns its own slice of `config/locales/en.yml`.

| Agent | Files | Strings |
|---|---|---|
| A1 | settings/{index,_profile_pane,_security_pane,_settings_modal,_time_zone_pane,_voyage_section,_stack_pane}.html.erb | ~95 |
| A2 | settings/{_discord_pane,_slack_pane,security/show,security/totps/new,user/show,webhooks/help/show}.html.erb | ~50 |
| A3 | All in-scope settings controllers (flashes) | ~45 |
| A4 | games/{index,show,_shelf,_letter_shelves,_genres_shelf,_genre_sub_shelf}.html.erb | ~38 |
| A5 | app/components/games/*.{rb,erb} + app/components/platforms/chip_component.{rb,erb} | ~40 |
| A6 | bundles views + components + bundles_controller.rb + games/_bundles_{for_shelf,modal}.html.erb | ~38 |
| A7 | games sub-controllers + shared bracketed/confirm/status components + deletions/syncs game/bundle branches | ~30 |
| A8 | **DEFERRED per option (a) above.** config/keybindings.yml stays literal. |

After parallel A1–A7 land, **Agent A9 (sequential)** merges slices into one
canonical `config/locales/en.yml`, verifies every `t(…)` call site resolves
(via `bin/rails runner` walk of all rendered views or via a quick request
smoke), and writes locale-key resolution specs.

---

## Open issues flagged

1. **Keybindings YAML** — see option discussion above. Default: defer.
2. **`BracketedLinkComponent`** caller-supplied `@label` — every call site (~50)
   needs `t(…)` wrapper. Mechanical sweep within each impl agent's slice.
3. **Bundle modal `default_title: "bundle"`** (line 89 of `_bundles_modal.html.erb`)
   — overwritten by JS at runtime; first-paint flash only. Extract for correctness.
4. **`shared/_omnisearch_modal`** — rendered from in-scope files but lives under
   `app/views/shared/`. Caller passes `placeholder:` (in scope); internal labels
   (close button) are out of scope. Recommend: include in Agent A6's slice
   since /games + /bundles are the only consumers.

---

## Already extracted (skip)

Zero `t(…)` calls in the in-scope tree today. Full virgin extraction.

## Out of scope (NOT cataloged)

- `/projects`, `/videos`, `/channels`, `/notifications`, `/calendar`, `/home`
- `/sessions` auth flow
- `extras/cli/`, `extras/website/`
- `docs/`, `db/`, `spec/`, `lib/`
- Code comments
- Brand-name literals (Slack, Discord, YouTube, Voyage AI, Postgres, Redis,
  Meilisearch, 1Password, IGDB, YouTube, pito) — extracted to keys but EN
  values stay literal per `feedback_brand_names_always_capitalized.md`
