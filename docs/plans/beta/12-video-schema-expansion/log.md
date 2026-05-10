# Phase 12 — Video Schema Expansion + Edit Surface + Pre-Publish Checklist

> Phase log. Newest entries on top once sessions land.

## Stub

Phase folder created on 2026-05-10 by architect-spec to hold:

- `specs/01-video-schema-expansion-and-pre-publish-checklist.md` — first (and
  currently only) implementation spec for this phase. Covers schema expansion
  per Mobile notes 1 + 2, edit surface, pre-publish checklist modal, sync-back
  to YouTube via `videos.update`, direct `Video.project_id` linkage (replaces
  the dropped Timeline model).

Cross-references when work begins:

- `docs/realignment-2026-05-09.md` — work unit 4. Resolved ambiguities #1
  (Timeline drop → `Video.project_id`), #7 (checklist on publish/schedule only),
  #10 (Path A2 retired).
- `docs/notes/2026-05-09-17-56-06-video-model-youtube-api.md` (Note 1).
- `docs/notes/2026-05-09-18-02-30-video-model-addendum-end-screen.md` (Note 2).
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — inherited
  destructive-and-reseed migration posture (note: by the time this phase ships,
  Phase 8 has already reseeded; this phase migrates additively).
- `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
  `YoutubeConnection` model identifier post-Phase-9.
- `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
  — schema baseline this phase builds on.
- `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
  — `youtube_connection_id` foreign key naming this phase inherits.

## Sessions

### 2026-05-10 — `rails-impl` first pass

- Spec dispatched:
  `specs/01-video-schema-expansion-and-pre-publish-checklist.md`.
- All 12 copy + 13 open-question decisions from the master agent's 2026-05-10
  lock-in were treated as the contract.

**Migration**

- `db/migrate/20260510135730_expand_videos_for_data_api_v3.rb` (single
  migration). Adds 19 columns to `videos` (title, description, tags jsonb,
  category*id, thumbnail_url, privacy_status integer-enum, publish_at,
  published_at, self_declared_made_for_kids, made_for_kids_effective,
  contains_synthetic_media, etag, pre_publish_checked_at, four
  pre_publish*\*\_ok booleans, last_sync_error, duration_seconds), one FK
  reference (`videos.project_id` ON DELETE SET NULL), GIN index on `tags`,
  partial index on `publish_at`, plain index on `published_at` and
  `privacy_status`. Renames `playlist_items` → `playlist_videos` (the Postgres
  rename auto-aligns the index names). Switches the `youtube_video_id` unique
  index to case-sensitive (Q12 lock).

**Models / concerns**

- `app/models/video.rb` heavy edit. New associations
  (`belongs_to :project optional`, `has_many :playlist_videos`,
  `has_many :playlists through:`, `has_one :channel_youtube_connection`).
  Validations: title bracket-character + length, description bytesize +
  brackets, tags array-of-strings + 500-char API-side budget, category_id
  numeric-string + required-on-publish-transition, publish_at future +
  private-only. `enum :privacy_status` with `prefix: :privacy`. Scopes
  `:published`, `:draft`, `:scheduled`, `:pre_publish_complete`. Public methods
  `pre_publish_complete?`, `studio_url`, `imported?`. Searchable hooks:
  `searchable :title, :description`,
  `filterable :privacy_status, :category_id, :channel_id, :project_id`.
  `after_update_commit :enqueue_sync_back, if: :writable_field_changed?`.
- `app/models/project.rb` — `has_many :videos, dependent: :nullify`.
- `app/models/playlist_video.rb` (new) — replaces `playlist_item.rb`.
- `app/models/playlist.rb` — `has_many :playlist_videos`,
  `has_many :videos, through: :playlist_videos`.
- `app/models/playlist_item.rb` deleted.

**Controllers / routes**

- `app/controllers/videos_controller.rb` heavy edit. Adds `edit`, `update`,
  `pre_publish_checklist`, `publish`, `schedule`. Strong- params shared via
  `app/policies/video_policy.rb`. Smuggle guards on `privacy_status` /
  `publish_at` (422 with explicit error). Form translates `tags_csv` → array.
- `config/routes.rb` — adds `:edit`, `:update` to `resources :videos`,
  `member { get :pre_publish_checklist; patch :publish; patch :schedule }`.

**Views**

- `app/views/videos/edit.html.erb` (new) + `_form.html.erb` (new) +
  `_pre_publish_modal.html.erb` (new). Modal uses Turbo Frame,
  Stimulus-disabled-until-checked submit, Studio deep-links per item. No JS
  confirm/alert/prompt anywhere. CLAUDE.md hard rule upheld.
- `app/views/videos/show.html.erb` — surfaces title, project link, imported
  indicator, last_sync_error.
- `app/views/videos/index.html.erb` — adds privacy column, imported indicator,
  [edit] link per row.
- `app/views/projects/show.html.erb` — adds linked-videos pane below the
  existing footage/notes/timelines row.

**Stimulus**

- `app/javascript/controllers/pre_publish_checklist_controller.js` (new).
  Eager-loaded via the existing `controllers/index.js`
  `eagerLoadControllersFrom`.

**Jobs / services / errors**

- `app/jobs/video_sync_back.rb` (new) — read-modify-write via the reader +
  client services. Optimistic on failure (Q10 lock). Records `last_sync_error`
  on every failure mode; re-raises on quota / 5xx / network so Sidekiq retries.
- `app/jobs/video_publish.rb` (new) — Sidekiq wrapper for the publish
  transition; defense-in-depth on pre-publish booleans.
- `app/services/youtube/videos_reader.rb` (new) — `videos.list` 1-unit call.
  Returns parsed item Hash for the writer.
- `app/services/youtube/videos_client.rb` (new) — `videos.update` 50-unit call.
  Builds full snippet+status payload, merges fresh pass-through fields (Note 1's
  destructive-PUT-per-part warning).
- `app/services/youtube/auth_revoked_error.rb`, `validation_error.rb`,
  `server_error.rb`, `not_found_error.rb` (new). Distinct error classes for the
  sync-back rescue blocks.
- `app/services/youtube/quota.rb` — adds `videos.update => 50`.

**Decorator / policy**

- `app/decorators/video_decorator.rb` heavy edit. Surfaces title, description,
  tags, category*id, privacy_status, publish_at, published_at,
  made_for_kids_effective (yes/no), the four pre_publish*\*\_ok booleans
  (yes/no), pre_publish_checked_at, studio_url, last_sync_error, imported
  (yes/no), last_sync_error.
- `app/policies/video_policy.rb` (new) — single source of truth for the writable
  subset; declares EDITABLE_ATTRS, SMUGGLE_GUARDED_ATTRS, SYSTEM_MANAGED_ATTRS,
  PUBLISH_ATTRS, SCHEDULE_ATTRS.

**MCP**

- `app/mcp/tools/update_video.rb` heavy edit. Full writable subset. Two-step
  `confirm: yes/no`. Dry-run returns structured diff
  (`{video_id, changes: { field: { old, new } }, hint }`). Smuggle guards on
  `privacy_status` / `publish_at`. App-scope gate.
- `app/mcp/tools/pre_publish_check_video.rb` (new) — flips four booleans +
  stamps `pre_publish_checked_at`. Two-step confirm.
- `app/mcp/tools/publish_video.rb` (new) — wraps the publish-state transition;
  rejects when pre-publish incomplete with explicit "missing checks" list.
  target=public/unlisted/scheduled.

**Specs added / rewritten**

- `spec/models/video_spec.rb` (heavy rewrite, 66 tests).
- `spec/models/playlist_video_spec.rb` (new, 4 tests).
- `spec/models/playlist_spec.rb` light edit (`playlist_videos` rename).
- `spec/models/project_spec.rb` light edit (linked-videos block).
- `spec/factories/videos.rb` heavy rewrite + 5 traits.
- `spec/factories/playlist_videos.rb` (new).
- `spec/factories/playlist_items.rb` deleted.
- `spec/models/playlist_item_spec.rb` deleted.
- `spec/decorators/video_decorator_spec.rb` heavy rewrite (16 tests).
- `spec/requests/videos_spec.rb` heavy rewrite (77 tests covering index, show,
  edit, update, smuggle guards, pre_publish_checklist, publish, schedule,
  destroy, panes, stats).
- `spec/jobs/video_sync_back_spec.rb` (new, 10 tests).
- `spec/jobs/video_publish_spec.rb` (new, 5 tests).
- `spec/services/youtube/videos_client_spec.rb` (new, 8 tests).
- `spec/services/youtube/videos_reader_spec.rb` (new, 5 tests).
- `spec/mcp/tools/update_video_spec.rb` heavy rewrite (16 tests).
- `spec/mcp/tools/pre_publish_check_video_spec.rb` (new, 5 tests).
- `spec/mcp/tools/publish_video_spec.rb` (new, 11 tests).
- `spec/system/video_pre_publish_checklist_spec.rb` (new, 6 tests).
- `spec/models/concerns/searchable_spec.rb` updated for the new searchable /
  filterable declarations.
- Adjacent fixes: `spec/helpers/application_helper_spec.rb`,
  `spec/requests/bulk_operations_spec.rb`, `spec/requests/channels_spec.rb`,
  `spec/requests/projects_spec.rb`, `spec/mcp/tools/get_video_spec.rb`,
  `spec/mcp/tools/list_videos_spec.rb` — assertions updated to reflect Phase
  12's restored title / privacy_status surface.

**Quality gates**

- `bundle exec rspec` — 2354 examples passing; 1 flaky failure on
  `spec/requests/calendar/month_spec.rb:35` (Phase 15 lane, passes in isolation,
  ordering-sensitive).
- `bundle exec rubocop` — clean (546 files inspected, no offenses).
- `bundle exec brakeman -q -w2` — 0 security warnings, 0 errors.

**Coordination notes**

- Phase 14 (Game IGDB) ran in parallel. No conflict — Game tables and Video
  tables are disjoint. Phase 14's `game_genres` / `game_platforms` migrations
  applied cleanly alongside Phase 12's videos migration.
- Phase 15 (Calendar) ran in parallel. The Calendar agent integrated the
  `CalendarDerivable` concern into `Video` directly and added
  `has_many :calendar_entries, dependent: :destroy`,
  `after_save_commit :sync_calendar_entry`, and the `calendar_entry_*` methods.
  These coexist with the Phase 12 hooks
  (`after_update_commit :enqueue_sync_back`) — both fire on the same
  writable-field changes.
- The `playlist_items` → `playlist_videos` rename did NOT impact parallel agents
  (none touched the join table).

**Open follow-ups**

- Manual playbook (steps 1-18 in the spec) requires the user.
- Docs-keeper handles `docs/architecture.md`, `docs/design.md`, `docs/mcp.md`
  updates after user validates.
- CLI parity (consuming the new `as_summary_json` / `as_detail_json` shape) is
  realignment work unit 10 — separate dispatch.
- Calendar test ordering flake is on the Phase 15 lane.

### 2026-05-10 — Phase 15 audit fix-forward (F1 + F2)

Phase 12 security audit returned 2 Medium findings against the new
`Youtube::VideosClient` / `Youtube::VideosReader` services. Fixed forward via
`rails-impl`.

**F1 — Token refresh missing in new YouTube clients**

Both new clients skipped the `ensure_token_fresh!` + retry-on-401 pattern that
`Youtube::Client` (`app/services/youtube/client.rb:115-160, 241-245`) has used
since Phase 7. Result: an `access_token` that simply expired (1h default) but
with a healthy `refresh_token` would surface as `needs_reauth: true` instead of
silently refreshing. Mirrors the legacy contract:

- `Youtube::OauthRefresh#ensure_token_fresh!` invoked at the top of
  `update_video` / `read_video` so a stale-but-refreshable token is refreshed
  before the call. A `Youtube::NeedsReauthError` from the pre-call refresh is
  re-raised as `Youtube::AuthRevokedError` so callers' rescue ladders are
  unchanged.
- Mid-call `Google::Apis::AuthorizationError` triggers exactly one
  `Youtube::TokenRefresher.call` retry (`refreshed_once` latch + `retry`). A
  second 401 declares the connection revoked (`AuthRevokedError`); a refresh
  that returns `invalid_grant` flips `needs_reauth: true` (`TokenRefresher`
  already does this) and re-raises as `AuthRevokedError`; a transient refresh
  failure surfaces as `Youtube::ServerError` so Sidekiq retries.

**F2 — Missing HTTP timeouts**

`Google::Apis::YoutubeV3::YouTubeService.new` was constructed with no
`client_options` / `request_options` in any of the three OAuth-backed clients. A
hung Google endpoint could wedge a Sidekiq worker indefinitely. Centralized
construction in a new `Youtube::ServiceFactory`:

- `Youtube::ServiceFactory.data_service(connection)` and `.analytics_service`
  build the Google service with `open_timeout_sec=10`, `read_timeout_sec=30`,
  `send_timeout_sec=30` (the gem uses `_sec`-suffixed accessors on
  `Google::Apis::ClientOptions`, not the bare `open_timeout` / `read_timeout`
  the audit finding suggested).
- `Youtube::Client`, `VideosClient`, `VideosReader` all delegate their private
  `data_service` / `analytics_service` to the factory. The duplicated
  `build_oauth_credentials` adapter inside `Client`, `VideosClient`,
  `VideosReader` collapsed into the factory's late-binding implementation
  (`PublicClient` and `AnalyticsClient` were out of audit scope and remain
  unchanged).

**Files changed**

- `app/services/youtube/service_factory.rb` (new) — single source of
  bounded-timeout + late-binding-authorization service construction.
- `app/services/youtube/videos_client.rb` — pre-call `ensure_token_fresh!`,
  one-shot refresh-on-401 retry inside `perform`, factory delegation, removed
  the local `build_oauth_credentials`.
- `app/services/youtube/videos_reader.rb` — same shape.
- `app/services/youtube/client.rb` — `data_service` / `analytics_service`
  delegate to the factory; the duplicated `build_oauth_credentials` removed.

**Specs added / updated**

- `spec/services/youtube/service_factory_spec.rb` (new, 7 tests) — verifies
  service class, timeout values, late-binding authorization adapter.
- `spec/services/youtube/videos_client_spec.rb` — added 5 tests under "token
  refresh" (proactive refresh, retry-then-success,
  retry-then-401-then-AuthRevoked, refresh-invalid-grant, pre-call invalid
  grant) plus a "configures bounded HTTP timeouts" assertion. The existing 401
  test was deleted (replaced by the new refresh-then-401 test that matches the
  new contract).
- `spec/services/youtube/videos_reader_spec.rb` — same shape (5 token-refresh
  tests + timeout assertion).
- `spec/services/youtube/client_spec.rb` — `stub_data_service` helper now also
  stubs `client_options` to a settable struct so the factory's real construction
  path runs through the `instance_double`.

**Quality gates**

- `bundle exec rspec spec/services/youtube/` — 167 examples, 0 failures.
- `bundle exec rspec spec/jobs/video_sync_back_spec.rb spec/requests/settings/youtube_spec.rb`
  — 24 examples, 0 failures.
- `bundle exec rubocop` on changed files — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings, 0 errors.

**Out of scope**

- `Youtube::PublicClient` and `Youtube::AnalyticsClient` were not in the audit
  scope and were not touched. Both remain candidates for the same factory
  treatment in a follow-up. `AnalyticsClient` already calls
  `ensure_token_fresh!` via `OauthRefresh` and so does not have the F1
  pathology; it lacks F2 timeouts and is the more pressing of the two.
