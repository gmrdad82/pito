# Channel Revamp — Master Spec

Phase folder: `pito-dev-kb/plans/beta/03-channel-revamp/` Status: amended
(architect-spec + 5 audit findings + 3 user clarifications + 7 late user
clarifications woven in by spec-amender).

---

## 1. Goal

Replace the Alpha-era `Channel` model and its surrounding UX with a slim,
URL-locked, tenant-scoped record built around the canonical YouTube channel URL.
In the same phase, lay down the multi-tenant primitives Beta has always called
for — `Tenant` and `User` — at the schema level only, with a singleton `Current`
shim so the app continues to behave as single-user. Mirror the revamp
simultaneously across the Rails web app (Lane 1), the `pito-sh` terminal app
(Lane 2a), and the MCP tool surface (Lane 2b), so the canonical contract and
both client surfaces ship together. Nothing about real YouTube data, OAuth, or
the future Auth UI is implemented here; this phase ends with a tenant-scoped
Channel that has a strict URL, four sync triggers, a bulk-sync operation that
mirrors bulk-delete, and three clients (web, terminal, MCP) all driving the same
JSON contract.

---

## 2. Scope deviations from `beta.md` and the original `03-plan.md`

- The active Phase 3 folder is renamed and re-scoped: `03-auth-foundation/` is
  preserved untouched and effectively deferred; `03-channel-revamp/` is the
  phase that runs now.
- Auth (Doorkeeper, scoped tokens, login UI, Google OAuth, header-bearer auth on
  both Pumas) is **not** in this phase. Those land later when the deferred Phase
  3 (or the Phase 12 successor) is reactivated.
- Tenant and User are introduced at **schema and model level only**. No login,
  no signup, no session, no token, no UI surface. The app continues to operate
  single-tenant / single-user via `Current.tenant = Tenant.first` and
  `Current.user = User.first` set in a `before_action`.
- The Alpha `Channel` columns (`youtube_channel_id`, `title`, `description`,
  `subscriber_count`, `view_count`, `video_count`, `thumbnail_url`, all
  `oauth_*`) are **removed**. They will return — under different names and with
  proper OAuth wiring — once Phase 7 (Google OAuth + YouTube API foundation)
  lands. The audit confirms the current `channels` table has 16 columns; the
  migration drops every Alpha column, keeps the existing `connected` and
  `last_synced_at` columns (they happen to match the new shape), and adds
  `tenant_id`, `channel_url`, `star`, `syncing`.
- `Channel` becomes tenant-scoped: `belongs_to :tenant`. It does **not** belong
  to a user.
- `Searchable` is **dropped** from `Channel`. With `title` and `description`
  gone, there is nothing to index. `Channel` is removed from `ReindexAllJob`'s
  iteration list, the search engine's Channel branch is removed, and the search
  controller's Channel search branch is dropped. The pito-sh `SearchChannelHit`
  UI is also removed (or replaced with a simple browse-channels link).
- The single-channel delete UX is **already** routed through the action
  confirmation framework (`app/views/channels/show.html.erb:6` already links to
  `/deletions/channel/#{@channel.id}`). The earlier spec text claiming we need
  to "migrate single-channel delete from JS confirm" is incorrect and is
  dropped. Remaining JS `confirm()` dialogs live on SavedView delete actions and
  are out of scope this phase.
- A `Confirmable` controller concern is extracted from `DeletionsController`
  (`load_items`, `cancel_path`, type→model dispatch) and applied to both
  `DeletionsController` and the new `SyncsController` to prevent drift. This is
  a should-do; if mid-phase it proves disruptive, the implementer may defer it
  but must flag it.
- `User` schema is locked:
  `users(id, tenant_id, username, email, password_digest, created_at, updated_at)`.
  There is **no** separate `name` column. Username and email are **globally
  unique** (single-column unique indexes), not scoped to tenant. Username regex
  is `\A[A-Za-z][A-Za-z0-9]*\z` — must start with a letter, alphanumerics only,
  no spaces, no special characters.
- This phase ships across all three lanes simultaneously: Lane 1 (Rails) lands
  first inside the phase, then Lane 2a (`pito-sh`) and Lane 2b (MCP) fan out in
  parallel per `orchestration/lanes.md`. Both Lane 2 surfaces fully participate;
  neither is on the skip list.
- Single-channel delete already routes through the action confirmation page
  (verified by audit). After this phase, every destructive channel action —
  single delete, bulk delete, single sync, bulk sync — flows through that
  confirmation page.
- A new `BulkSync` operation mirrors the existing `BulkDelete` operation
  pattern. The audit confirms the framework: `BulkOperation` (kind enum,
  extended to 6 values) + `BulkOperationItem` (status enum, extended to 4
  values) + `BulkSyncJob` (Sidekiq, mirroring `BulkDeleteJob`) + Turbo Streams
  over ActionCable for progress + `SyncsController` mirroring
  `DeletionsController`. It includes a confirmation page, Turbo Streams
  progress, and a skip rule for channels already syncing.
- **bulk_sync mirrors bulk_delete exactly — controller queues and returns**. The
  URL pattern is `/syncs/:type/:ids` (mirror of `/deletions/:type/:ids`). IDs
  are comma-separated and the same route works whether the user selected one
  channel or many. `SyncsController#show` renders the confirmation preview (with
  skip badges for already-syncing channels). `SyncsController#create` creates a
  `BulkOperation(kind: :bulk_sync, status: :pending)`, creates
  `BulkOperationItem` rows (with `status: :skipped` pre-marked for
  already-syncing channels), then enqueues
  `BulkSyncJob.perform_async(@operation.id)` (or
  `perform_in(3.seconds, @operation.id)` matching exactly what bulk*delete
  does). The controller renders `:progress` immediately and does NOT block on
  job completion — the controller queues and returns. The progress page
  subscribes via Turbo Stream (whatever bulk_delete uses today) and the job
  broadcasts updates as it runs. **No new realtime mechanism**: reuse the exact
  `Turbo::StreamsChannel.broadcast_replace_to("bulk_operation*#{id}",
  ...)`pattern from`BulkDeleteJob`. The bulk_sync flow uses the same Turbo
  Streams over ActionCable mechanism that bulk_delete uses — no custom
  ActionCable channel.
- **No separate single-record actions in MCP**. Single-record MCP tools
  (`sync_channel(id:)`, `delete_channel(id:)` if it existed) are dropped from
  the tool surface. Only the bulk equivalents remain:
  `bulk_delete_channels(ids: [int], confirm: bool)` and
  `bulk_sync_channels(ids: [int], confirm: bool)` — both accept 1 or many IDs.
  Each requires a two-step confirmation flow: first call without `confirm: true`
  (or with `confirm: false`) returns a structured preview
  `{ total: N, syncable: [ids], skipped: [{id, reason}], message: "..." }` with
  no state change and no `BulkOperation` created; second call with
  `confirm: true` creates the `BulkOperation`, items, and enqueues the job,
  returning `operation_id` and progress URL so the client can poll status. The
  exact JSON schema for each tool is documented in the "MCP tool surface"
  section, including the `confirm` parameter.
- **Terminal app (pito-sh) uses the bulk pattern + in-TUI confirmation**. There
  are NO separate single-channel delete or sync flows in the terminal.
  Single-record actions are routed through the bulk picker: user selects 1 or
  more channels (existing bulk_select shortcut, e.g., space to toggle); user
  triggers a bulk action (e.g., `D` for delete, `Y` for sync); the terminal app
  shows an in-TUI confirmation screen (NOT a system dialog) listing the selected
  channels with skip badges for any already-syncing; user presses `y` to confirm
  or any other key to cancel; on confirmation, the terminal calls the bulk
  MCP/JSON API with `confirm: true`. If a highlighted channel has no explicit
  selection, it becomes the implicit selection of one and `D`/`Y` opens the same
  bulk preview. Any pre-existing single-channel key bindings that immediately
  delete or sync are refactored to this flow.
- **Comprehensive testing required across all three lanes** (Rails, MCP,
  pito-sh). Every restriction, enforcement, and format rule in this spec must
  have explicit test coverage. See section 5 "Test scenarios" for the named
  scenarios that gate acceptance.
- **Dashboard chart `[ ] sync` state persisted in localStorage** (NEW small
  feature). Each sync-capable dashboard chart (line/time-series charts only —
  not bar charts) has the existing `[ ] sync` design-system bracketed-checkbox
  in its header (rendered via `CheckboxComponent` → `<label class="md-check">`,
  NOT a native `<input>`). The checkbox controls crosshair synchronization
  between charts (toggling `data-sync-group="dashboard"` on the chart container,
  which the existing crosshair plugin in `app/javascript/application.js` reads).
  State persists across reloads via `localStorage` under the key
  `pito_dashboard_charts_synced` (JSON array of chart slugs that are currently
  synced / checked). On first visit (key absent), the array is initialized with
  all sync-capable chart slugs — every `[ ] sync` checkbox starts checked
  (`[x]`), matching the UX default rule. Implementation lives in
  `app/javascript/controllers/chart_sync_controller.js` (already exists;
  extended to own seeding + persistence in addition to the runtime sync-group
  toggle); each chart container has a stable `data-chart-id` slug (e.g.,
  `daily-views`, `views-by-channel`, `daily-engagement`) and is wired as
  `data-chart-sync-target="chart"`. The `[ ] sync` checkbox is wired as
  `data-chart-sync-target="checkbox"` with `data-chart-id="<slug>"` and
  `data-action="change->chart-sync#toggle"`. The controller reads/writes the
  array on `connect()` and on every checkbox `change` event. **No chart-hiding /
  chart-visibility toggle is shipped in this phase** — only crosshair sync state
  is persisted.
- **No JavaScript alert/confirm/prompt dialogs in any code touched by this
  phase** (project-wide hard rule going forward). The action-confirmation page
  is the canonical replacement. Any spec or template touched in this phase that
  lists `data-turbo-confirm` or `confirm:` link options is amended to remove
  them. Pre-existing dialogs in code NOT touched this phase (specifically
  SavedView delete) remain as legacy and are migrated in a future phase — the
  rule applies forward, not retroactively.
- **Bulk operation pattern is the foundation for many future actions**. The
  `BulkSync` job + `SyncsController` + `Confirmable` concern triple is designed
  as a reusable skeleton. Future operations (bulk metadata update, bulk privacy
  change, bulk add-to-playlist, bulk thumbnail update, etc.) will reuse this
  skeleton; new bulk kinds extend the `BulkOperation.kind` enum and add a
  sibling controller + job.
- A new daily cron, `SyncStarredChannelsJob`, is added at midnight UTC. It
  enqueues `ChannelSync` for every starred channel.
- An owner credentials block (`Rails.application.credentials.owner`) is
  introduced as the single source of truth for the seeded tenant/user. Seeds
  read from it; if the block is missing, placeholder values are used and a
  warning is printed.
- Seeds expand to 100 channels with a deterministic distribution of
  star/connected flags and a stable RNG-driven URL set, so re-runs are stable
  and the index/list views always show realistic ordering.

### Boolean wire format

- **Boolean fields use `"yes"` / `"no"` strings at every external boundary.**
  Internal storage stays `Boolean` (Postgres `boolean`, Ruby `true`/`false`,
  Rust `bool`), but URL query params, JSON API request/response bodies, MCP tool
  inputs (as `enum: ["yes", "no"]`), and MCP tool outputs all communicate
  booleans as the strings `"yes"` and `"no"`. Filter chips on `/channels` use
  `?starred=yes&connected=yes&syncing=yes` (absent param = no filter). JSON
  responses for `Channel` emit `"star": "yes"`, `"connected": "no"`,
  `"syncing": "yes"` (strings, not booleans). MCP `list_channels` accepts
  `star: "yes" | "no"`, `connected: "yes" | "no"`, `syncing: "yes" | "no"`. MCP
  `update_channel` accepts `star` and `connected` as `"yes" | "no"`. The Rust
  `Channel` struct keeps `bool` fields with `#[serde(with = "yes_no")]` so JSON
  serde handles conversion automatically. Conversion helpers live at the
  boundary (`YesNo.to_yes_no`/`from_yes_no` in Ruby; `yes_no` serde module in
  Rust). Strict-on-input: only `"yes"` and `"no"` accepted; `true`, `1`, `on`,
  etc. are rejected with a clear error. See `orchestration/ux-defaults.md`
  "Boolean values" for the global rule. The `confirm: bool` MCP parameter on
  bulk tools is the one explicit exception this phase keeps in `bool` shape
  (pre-existing contract); future bulk tools may migrate it to `"yes"`/`"no"`
  but this phase does not.

---

## 3. Files touched

### Repo: `pito` (Rails + MCP, Lane 1 + Lane 2b)

#### Migration

| File                                      | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `db/migrate/<ts>_create_tenants.rb`       | Create `tenants` table (id, name, timestamps).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `db/migrate/<ts>_create_users.rb`         | Create `users` table with exact columns `id, tenant_id (FK), username (citext), email (citext), password_digest, created_at, updated_at`. **Single-column unique indexes** on `username` and `email` (NOT scoped to tenant).                                                                                                                                                                                                                                                                                                                                                                                                   |
| `db/migrate/<ts>_revamp_channels.rb`      | Drop the 14 Alpha-only columns from `channels` (`title, description, subscriber_count, view_count, video_count, thumbnail_url, youtube_channel_id, oauth_access_token, oauth_refresh_token, oauth_expires_at, oauth_scopes`); add `tenant_id` FK NOT NULL, `channel_url` (string, unique), `star` (bool default false), `syncing` (bool default false); keep existing `connected` (bool) and `last_synced_at` (timestamp). Columns stay `boolean` internally; the wire format is `"yes"`/`"no"` (see section 2 "Boolean wire format"). Use `change_table` with `bulk: true`. `down` recreates the dropped columns as nullable. |
| (no separate dependent-cleanup migration) | Audit confirms `videos.channel_id`, `playlists.channel_id`, `video_uploads.channel_id` continue to reference `channels.id`. They survive untouched this phase; their owning models are revamped in later phases.                                                                                                                                                                                                                                                                                                                                                                                                               |

#### Models

| File                                 | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/models/tenant.rb`               | `has_many :users`, `has_many :channels`. Validates `name` presence + length 3..30.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `app/models/user.rb`                 | `belongs_to :tenant`. `has_secure_password`. Validates `username` and `email` with `uniqueness: true` (NO `scope: :tenant_id` — globally unique). Username regex: `\A[A-Za-z][A-Za-z0-9]*\z`. Email RFC-style format. Class method `find_by_username_or_email(login)`. NO `name` column or attribute.                                                                                                                                                                                                      |
| `app/models/channel.rb`              | Rewritten. `belongs_to :tenant`. URL validation regex. Lock-on-update guard. Scopes `starred`, `connected`, `syncing` (drop the existing `public_only` scope — no longer meaningful). `after_create_commit` enqueues `ChannelSync`. `after_update_commit` enqueues `ChannelSync` when `saved_change_to_star?` and `star?`. **Remove** `encrypts :oauth_access_token, :oauth_refresh_token` (columns dropped). **Remove** `include Searchable`. **Remove** validations on `youtube_channel_id` and `title`. |
| `app/models/current.rb`              | `ActiveSupport::CurrentAttributes` with `attribute :tenant, :user, :token`.                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `app/models/saved_view.rb` (line 31) | Update `entity_labels` so the channel branch reads `entity&.id&.to_s` instead of `entity&.title`. Recommend kind-aware dispatch (`kind == "channels" ? entity&.id&.to_s : entity&.title`). Note: Channel labels use `id.to_s` for now; when YouTube sync lands and channels gain a synced title or display field, this rule may be revisited.                                                                                                                                                              |
| `app/models/bulk_operation.rb`       | Extend `kind` enum from 5 to 6 values: append `bulk_sync: 5` (existing 0..4 are `update_metadata, update_privacy, add_to_playlist, remove_from_playlist, bulk_delete`). No migration — enum is integer-backed.                                                                                                                                                                                                                                                                                             |
| `app/models/bulk_operation_item.rb`  | Extend `status` enum from 3 to 4 values: append `skipped: 3` (existing 0..2 are `pending, succeeded, failed`).                                                                                                                                                                                                                                                                                                                                                                                             |

#### Controllers

| File                                                           | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `app/controllers/application_controller.rb`                    | Add `before_action :set_current_tenant_and_user` setting `Current.tenant = Tenant.first; Current.user = User.first`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `app/controllers/channels_controller.rb`                       | Rewritten. Strong params: `[:channel_url, :star, :connected]` for `create`; `[:star, :connected]` for `update` (URL is locked). Boolean params (`:star`, `:connected`) arrive as `"yes"`/`"no"` strings on JSON and as `"yes"`/`"no"` from filter chip URL params (`?starred=yes&connected=yes&syncing=yes`); coerce via `YesNo.from_yes_no` before assignment, reject anything other than `"yes"` or `"no"` with 422. JSON responses serialize booleans as `"yes"`/`"no"` via `YesNo.to_yes_no` (e.g., `{"star": "yes", "connected": "no", "syncing": "no"}`). Drop the auto-`youtube_channel_id = "local_..."` line in `create`. Replace every `.order(title: :asc)` with `.order(channel_url: :asc)` or `.order(created_at: :desc)`. Routes through the action confirmation framework for delete + sync. JSON variants on every action. |
| `app/controllers/concerns/confirmable.rb` (NEW)                | Concern extracted from `DeletionsController`. Provides `load_items`, `cancel_path`, and the type→model dispatch helper. Included by both `DeletionsController` and `SyncsController`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `app/controllers/deletions_controller.rb`                      | Include `Confirmable`. Replace `.order(title: :asc)` at lines 35 and 63 with `.order(channel_url: :asc)`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `app/controllers/syncs_controller.rb` (NEW)                    | Mirror of `DeletionsController`. `GET /syncs/:type/:ids` → preview (`show`); `POST /syncs/:type/:ids` → create `BulkOperation` (kind: `bulk_sync`) + items + enqueue `BulkSyncJob` + render `:progress`. Pre-flight skip logic in `load_items` and `create`: partition channels by `syncing: true`/`false`. For already-syncing channels, create the `bulk_operation_item` with `status: :skipped` and `error_message: "already syncing"` so the job can render the skip badge from initial state without invoking the sync service.                                                                                                                                                                                                                                                                                                       |
| `app/controllers/search_controller.rb` (lines 13, 21)          | Drop the `engine.search(Channel, ...)` branch. Channel is no longer searchable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `app/controllers/dashboard_controller.rb` (lines 5, 14-19, 49) | The `views_by_channel` chart joins `channels.title`. Change the GROUP BY column to `channels.channel_url` (or drop the chart for this phase if too disruptive — implementer's call).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

#### Views

| File                                                                             | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `app/views/channels/index.html.erb`                                              | Listing with truncated URL + hover full URL, `[ view ]`, star icon, connected icon, syncing pill, relative `last_synced_at`. Filter chips: starred / connected / syncing — each chip toggles a `?<filter>=yes` URL param (e.g., `?starred=yes&connected=yes&syncing=yes`); absence of the param means "no filter" and chip is off. Never emit `=true`/`=false`/`=1`/`=0` in the URL. Bulk action bar: `[ sync ]`, `[ delete ]`.                                                                                                                                                            |
| `app/views/channels/show.html.erb`                                               | Full URL + `[ view ]`, `[ sync ]`, `[ delete ]`, star toggle, connected toggle.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `app/views/channels/new.html.erb`                                                | Single URL input with `pattern=` regex and example placeholder.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `app/views/channels/edit.html.erb`                                               | URL `<input readonly disabled>`; star + connected as togglable checkboxes.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `app/views/channels/_channel_row.html.erb`                                       | Shared row partial used by index and the action confirmation pre-flight.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `app/views/channels/_picker.html.erb`                                            | Refactor: drop `title`, `description`, `subscriber_count`, `video_count`, `view_count`, `connected?`, `youtube_channel_id` references. Display by `channel_url` (truncated) + star/connected/syncing indicators.                                                                                                                                                                                                                                                                                                                                                                           |
| `app/views/channels/_pane.html.erb`                                              | Same refactor as above.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `app/views/channels/_form.html.erb`                                              | Same refactor; `new` shows URL input, `edit` shows URL readonly.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `app/views/channels/panes.html.erb`                                              | Same refactor.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `app/views/channels/_add_pane_dialog.html.erb`                                   | Same refactor.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `app/views/dashboard/index.html.erb` (line 8)                                    | "X videos across Y channels" copy: keep, just count. **Also**: attach the `chart-sync` Stimulus controller to the dashboard root container.                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `app/views/dashboard/index.html.erb` (each sync-capable chart container)         | Add a stable `data-chart-id="<slug>"` attribute on the chart container (e.g., `daily-views`, `views-by-channel`, `daily-engagement`) and `data-chart-sync-target="chart"`. Render the existing `[ ] sync` checkbox via `CheckboxComponent` (design-system bracketed style; never a native `<input type="checkbox">`) wired with `data-chart-sync-target="checkbox"`, `data-chart-id="<slug>"`, and `data-action="change->chart-sync#toggle"`. Non-sync-capable charts (bar charts) get the `data-chart-id` for stable identity but NO `data-chart-sync-target` and NO `[ ] sync` checkbox. |
| `app/views/search/show.html.erb` (lines 21-41)                                   | **Drop** the channel-results table entirely. Channel is no longer searchable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `app/views/videos/_form.html.erb` (line 8)                                       | `Channel.order(:title)` → `Channel.order(:channel_url)`; use `:channel_url` as display label until later phases refactor video creation.                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `app/views/videos/index.html.erb`, `_pane.html.erb`, `_add_pane_dialog.html.erb` | Replace `video.channel.title` with `video.channel.channel_url` (truncated), or drop the channel column from those views in this phase.                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `app/views/syncs/show.html.erb` (NEW)                                            | Clone of `app/views/deletions/show.html.erb` with `destructive: false`, `submit_label: "[sync]"`. Renders skip rows in red `[ skip ]` with casual muted message ("already humming away"). Footer note: "X channels will be skipped (already syncing)." Disable submit if all rows are skipped.                                                                                                                                                                                                                                                                                             |
| `app/views/syncs/progress.html.erb` (NEW)                                        | Clone of `app/views/deletions/progress.html.erb`. For already-skipped rows render `<span class="bracketed text-danger">[ skip ]</span>` in `#item_status_<id>` instead of `<span class="dot-loader">`.                                                                                                                                                                                                                                                                                                                                                                                     |
| `app/views/bulk_operations/_item_row.html.erb`                                   | Add `elsif status == "skipped"` branch rendering the red bracketed `[ skip ]` badge.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `app/views/shared/_action_screen.html.erb`                                       | Existing partial (the action-confirmation framework). Reused by both deletions and syncs. No structural change needed beyond what the syncs view consumes.                                                                                                                                                                                                                                                                                                                                                                                                                                 |

#### Jobs

| File                                                          | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/jobs/channel_sync.rb` (or `app/sidekiq/channel_sync.rb`) | Sidekiq job. Flips `syncing` true; placeholder body; ensure-block flips `syncing` false and stamps `last_synced_at` only if the channel still exists.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `app/jobs/sync_starred_channels_job.rb`                       | Sidekiq job iterating `Channel.where(star: true)` and calling `ChannelSync.perform_async(id)` for each.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `app/jobs/bulk_sync_job.rb` (NEW)                             | Mirrors `app/jobs/bulk_delete_job.rb`. `Sidekiq::Job`, queue `bulk_sync`. Three private broadcast helpers identical to `bulk_delete_job.rb`: `broadcast_status` (to `operation_progress`), `broadcast_progress` (to `operation_progress`), `broadcast_item_status` (to `item_status_#{item_id}`). Stream name `"bulk_operation_#{id}"` via `Turbo::StreamsChannel.broadcast_replace_to`. **Difference from BulkDelete**: do NOT fail-fast — sync errors mark per-item failed and the loop continues for remaining items. When iterating, `next` on items already in `:skipped` status; do NOT broadcast a new state for them (the initial render already shows the skip badge). |
| `app/jobs/reindex_all_job.rb`                                 | **Remove** `Channel` from the iteration list. Channel is no longer searchable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |

#### Realtime (Turbo Streams over ActionCable)

| File                            | Purpose                                                                                                                                                                                                                                                                                            |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (no custom ActionCable channel) | The audit confirms pito uses **Turbo Streams via ActionCable** (not custom ActionCable channels). `BulkSync` broadcasts via `Turbo::StreamsChannel.broadcast_replace_to("bulk_operation_#{id}", target: ..., partial: ...)` — identical pattern to `BulkDelete`. No new channel class is required. |

#### JS / Stimulus

| File                                                                 | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/javascript/controllers/operation_progress_controller.js`        | `_applyState`: add `else if (item.status === "skipped")` branch writing the same `[ skip ]` markup as the cable path. Currently has only `dot-done` and `dot-fail` branches.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `app/javascript/controllers/bulk_select_controller.js` (lines 68-87) | Add `syncAction` Stimulus target and `syncTypeValue`. Mirror the existing `[ delete N ]` link generation to render `[ sync N ]` linking to `/syncs/${syncTypeValue}/${ids}` with the `bracketed` class (NOT `text-danger`, since sync is non-destructive). Generated URLs accept 1 or many comma-separated IDs (single-record actions ride the same URL pattern).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `app/javascript/controllers/chart_sync_controller.js` (extended)     | Existing Stimulus controller, attached to the dashboard root. Targets: `chart` (one per sync-capable chart container) and `checkbox` (one per `[ ] sync` checkbox). On `connect()`: read `localStorage.getItem("pito_dashboard_charts_synced")`; if null, write the full set of sync-capable chart slugs (default-ACTIVE rule). Apply state to each surface: set the hidden native `<input>`'s `checked` (drives the `[ ]` / `[x]` indicator via the `md-check` CSS) AND set/remove `data-sync-group="dashboard"` on the chart container (drives the crosshair plugin in `app/javascript/application.js`). `toggle(event)` action: read the checkbox's `data-chart-id`, add or remove from the synced set based on `event.currentTarget.checked`, persist, re-apply state. localStorage key: `pito_dashboard_charts_synced`. Value: JSON array of chart slug strings that are CURRENTLY SYNCED, e.g., `["daily-views", "daily-engagement"]`. |

#### MCP (Lane 2b)

| File                                                         | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `app/mcp/tools/list_channels.rb`                             | Refactor: filterable (star, connected, syncing — each declared as `enum: ["yes", "no"]` in the input schema; absence of the field = no filter), paginated, returns the new shape. Boolean fields in returned channels emit as `"yes"`/`"no"` strings (e.g., `{"star": "yes", "connected": "no", "syncing": "no"}`), never as JSON booleans.                                                                                                                                                |
| `app/mcp/tools/get_channel.rb`                               | Refactor: returns the new shape. Boolean fields (`star`, `connected`, `syncing`) emit as `"yes"`/`"no"` strings.                                                                                                                                                                                                                                                                                                                                                                           |
| `app/mcp/tools/create_channel.rb`                            | Refactor: strict URL validation matching the model regex (no drift between layers). Drop any `youtube_channel_id` or Alpha fields from the input schema. Boolean inputs (`star`, `connected`) declared as `enum: ["yes", "no"]`. Returned channel serializes booleans as `"yes"`/`"no"`.                                                                                                                                                                                                   |
| `app/mcp/tools/update_channel.rb`                            | Refactor: permits `star`, `connected` only — both declared as `enum: ["yes", "no"]` in the input schema; rejected with a clear error if anything else is sent. URL changes rejected (decision below). Returned channel serializes booleans as `"yes"`/`"no"`.                                                                                                                                                                                                                              |
| `app/mcp/tools/bulk_delete_channels.rb`                      | Refactor or rename existing `delete_records` Channel branch. Two-step confirm flow: input schema `{ ids: [int], confirm: bool }`; first call (no confirm or `confirm: false`) returns `{ total, deletable: [ids], skipped: [{id, reason}], message }` with no state change; second call (`confirm: true`) creates the `BulkOperation`, items, enqueues `BulkDeleteJob`, returns `{ operation_id, progress_url }`. Accepts 1 or many IDs.                                                   |
| `app/mcp/tools/bulk_sync_channels.rb` (NEW)                  | Two-step confirm flow identical to `bulk_delete_channels` but for sync. Input schema `{ ids: [int], confirm: bool }`; first call returns `{ total, syncable: [ids], skipped: [{id, reason: "already syncing"}], message }`; second call creates the `BulkOperation` with `kind: :bulk_sync`, items (with `status: :skipped` pre-marked for already-syncing channels), enqueues `BulkSyncJob.perform_async(operation.id)`, returns `{ operation_id, progress_url }`. Accepts 1 or many IDs. |
| `app/mcp/tools/delete_records.rb`                            | Drop the per-record Channel branch — bulk channel deletion now flows through `bulk_delete_channels`. Other record types (videos, playlists) remain handled here for now.                                                                                                                                                                                                                                                                                                                   |
| `app/mcp/tools/get_dashboard.rb`                             | Refactor any references to dropped Channel fields.                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `app/mcp/tools/search_content.rb`                            | Drop the Channel branch — Channel no longer searchable.                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `app/mcp/tools/app_status.rb`                                | Refactor any references to dropped Channel fields.                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `app/mcp/server.rb` (or wherever tools register)             | Replace registered Channel tools with the new set: `list_channels`, `get_channel`, `create_channel`, `update_channel`, `bulk_delete_channels`, `bulk_sync_channels`. **Drop** any registered `sync_channel(id:)` and `delete_channel(id:)` single-record tools.                                                                                                                                                                                                                            |
| `app/mcp/tools/SCHEMA_DOCS.md` (or inline tool descriptions) | Document the exact JSON schema for `bulk_delete_channels` and `bulk_sync_channels` including the `confirm` parameter description: "If false or absent, returns a preview of what would happen and creates no state. If true, executes the operation and returns the operation_id."                                                                                                                                                                                                         |

#### Specs (RSpec)

| File                                                                      | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec/models/tenant_spec.rb`                                              | Validations: name presence, length 3..30 (negative cases for 2 chars and 31 chars), associations.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `spec/models/user_spec.rb`                                                | Validations, **global** uniqueness for `username` and `email` (single-column unique indexes; not scoped to tenant). Username regex tests: positive cases `asdk123`, `M23kony`; negative cases `123abc` (starts with digit), `Catalin Ilinca` (contains space), `me_too` (contains underscore), and assert the regex is exactly `\A[A-Za-z][A-Za-z0-9]*\z`. Password digest. `find_by_username_or_email` (covers both username and email lookup paths, including non-existent values).                                                                                                                                                                                                                                                                   |
| `spec/models/channel_spec.rb`                                             | Refactor: drop Alpha-field assertions. Cover URL regex (positive case `https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ`; negative cases `youtube.com/@handle`, `https://youtu.be/...`, `https://www.youtube.com/c/somename`, `https://www.youtube.com/user/legacy`, `http://www.youtube.com/channel/UC...` (http not https), `https://youtube.com/channel/UC...` (missing www.), and an empty string). Cover lock-on-update guard (`before_update` raises or invalidates), scopes (`starred`, `connected`, `syncing`; assert `public_only` removed), `after_create_commit` enqueues `ChannelSync`, `after_update_commit` enqueues only when `saved_change_to_star?` and `star?`. Assert `Channel` does NOT include `Searchable`.               |
| `spec/factories/channels.rb`                                              | Drop `title`, `description`, `subscriber_count`, `view_count`, `video_count`, `thumbnail_url`, `youtube_channel_id`, `oauth_*` factory attributes. Add `tenant`, `channel_url`, `star`, `connected`, `syncing`, `last_synced_at`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `spec/decorators/channel_decorator_spec.rb`                               | Refactor: assert `as_summary_json` and `as_detail_json` expose only `{id, channel_url, star, connected, syncing, last_synced_at, created_at, updated_at}`, with `star`, `connected`, `syncing` emitted as `"yes"`/`"no"` strings (NOT JSON booleans). Assert `formatted_subscriber_count`, `formatted_view_count`, `formatted_video_count` are removed.                                                                                                                                                                                                                                                                                                                                                                                                 |
| `spec/jobs/channel_sync_spec.rb`                                          | Lifecycle: syncing flag flip, graceful nil, deletion-during-sync race.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `spec/jobs/sync_starred_channels_job_spec.rb`                             | Enqueues one ChannelSync per starred channel.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `spec/jobs/bulk_sync_job_spec.rb` (NEW)                                   | Clone of `spec/jobs/bulk_delete_job_spec.rb`. Per-item progress broadcasts asserted via the existing helper. **Add a context "with already-syncing channel"** asserting the item stays `:skipped`, no broadcast occurs for it, and the sync service was not called for it. Assert the loop does NOT fail-fast on per-item errors (one failed item does not abort the rest).                                                                                                                                                                                                                                                                                                                                                                             |
| `spec/jobs/bulk_delete_job_spec.rb`                                       | Update the channels factory usage to the new shape.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `spec/jobs/reindex_all_job_spec.rb`                                       | Update: assert the iteration list NO LONGER includes `Channel`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `spec/jobs/{search_index,search_remove}_job_spec.rb`                      | Update channel factory usage. Assert these jobs no longer accept Channel.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `spec/requests/channels_spec.rb`                                          | Web: full CRUD (index, show, new, create, edit, update, with HTML and JSON variants for each) + URL-lock 422 (update rejects `channel_url` change). Strong-params assertions: `update` rejects URL changes; `create` permits `[:channel_url, :star, :connected]`. URL format validation matches the model regex.                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `spec/requests/syncs_spec.rb` (NEW)                                       | Clone of `spec/requests/deletions_spec.rb`. Cover GET preview for: 1-id, multi-id, all-already-syncing, mixed (some syncing some not), and empty cases. Cover POST create — assert `BulkOperation` count increases by 1 (`change(BulkOperation, :count).by(1)`), `BulkOperationItem` rows are created with correct `status` pre-marking (`skipped` for already-syncing), `BulkSyncJob.perform_async` is enqueued (or `perform_in(3.seconds, ...)` matching bulk_delete), and the controller responds with `:progress` immediately without waiting on the job. Add a context "with already-syncing channel" asserting the `bulk_operation_item` is created with `status: :skipped` and `error_message: "already syncing"` directly, before the job runs. |
| `spec/requests/deletions_spec.rb`                                         | Update existing spec: assert `change(BulkOperation, :count).by(1)` style assertion on POST create. Assert no JS-confirm fallback is used.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `spec/system/channels_spec.rb`                                            | Capybara: index filters (star, connected, syncing — assert each filter actually narrows results), show actions, new/edit forms, bulk confirmation flow including the `[ skip ]` badge, ActionCable / Turbo Stream broadcast assertions using whatever helper the existing bulk_delete specs use (e.g., `have_broadcasted_to`).                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `spec/system/dashboard_spec.rb` (or `spec/javascript/chart_sync_test.js`) | Assert dashboard renders with `data-chart-id` attributes on every chart container; assert the `chart-sync` Stimulus controller is bound on the root; assert each sync-capable chart has `data-chart-sync-target="chart"` and a `[ ] sync` `CheckboxComponent` wired as `data-chart-sync-target="checkbox"`. Behavior test: toggle a `[ ] sync` checkbox, refresh the page, assert the checkbox stays unchecked (localStorage persistence) AND the chart container's `data-sync-group` attribute reflects the saved state. If a Stimulus-only test setup exists, prefer that; otherwise system-spec via Capybara with `evaluate_script` to read localStorage.                                                                                            |
| `spec/mcp/tools/list_channels_spec.rb`                                    | Filters: `star`, `connected`, `syncing` each work and combine. Pagination. Returns the new shape.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `spec/mcp/tools/get_channel_spec.rb`                                      | Happy path with valid id; error path with non-existent id. Returns the new shape.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `spec/mcp/tools/create_channel_spec.rb`                                   | Happy path; error paths: missing `channel_url`, invalid URL format (matches model regex; same negative cases as `channel_spec.rb`). Confirms no drift between layers.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `spec/mcp/tools/update_channel_spec.rb`                                   | Permits `star` and `connected`. Rejects URL changes (silently or with structured error — pick and document).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `spec/mcp/tools/bulk_delete_channels_spec.rb`                             | Two-step confirm flow. First call (no `confirm`): returns preview structure, no `BulkOperation` created. Second call (`confirm: true`): creates `BulkOperation` (kind: `bulk_delete`), creates items, enqueues `BulkDeleteJob`, returns `operation_id` + `progress_url`. Negative paths: empty `ids`, non-existent ids. Accepts 1 or many ids.                                                                                                                                                                                                                                                                                                                                                                                                          |
| `spec/mcp/tools/bulk_sync_channels_spec.rb` (NEW)                         | Two-step confirm flow. First call (no `confirm`): returns preview `{ total, syncable, skipped: [{id, reason: "already syncing"}], message }`, no `BulkOperation` created. Second call (`confirm: true`): creates `BulkOperation` (kind: `bulk_sync`), creates items (with `status: :skipped` pre-marked for already-syncing), enqueues `BulkSyncJob`, returns `operation_id` + `progress_url`. Negative paths: empty `ids`, non-existent ids, all-already-syncing. Accepts 1 or many ids.                                                                                                                                                                                                                                                               |
| `spec/controllers/concerns/confirmable_spec.rb` (NEW, optional)           | If the `Confirmable` concern is extracted (step A6b), give it its own spec covering `load_items`, `cancel_path`, type→model dispatch. If deferred per `dropped.md`, this spec is dropped too.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `spec/models/saved_view_spec.rb`                                          | Update the `entity_labels` test: for `kind == "channels"`, assert label uses `id.to_s`; for `kind == "videos"`, still uses `title`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `spec/components/saved_views_section_component_spec.rb`                   | Update fixtures to the new Channel shape; verify `display_name_with_deletions` continues to work after the saved_view.rb edit.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `spec/services/search/meilisearch_engine_spec.rb`                         | Drop the Channel branch — Searchable removed from Channel.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `spec/models/concerns/searchable_spec.rb`                                 | Remove the Channel assertion (Channel no longer includes Searchable).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `spec/seeds_spec.rb`                                                      | Seeds integrity: counts + distribution + URL format.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

#### Config

| File                                                                                                      | Purpose                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config/sidekiq_cron.yml`                                                                                 | Add `sync_starred_channels` entry: cron `0 0 * * *`, class `SyncStarredChannelsJob`.                                                                                                                                                                                                                                                                                          |
| `config/routes.rb`                                                                                        | Routes for `sync` (member POST), `bulk_sync` (collection POST), `bulk_destroy` (collection DELETE). NEW: `get "syncs/:type/:ids", to: "syncs#show"` and `post "syncs/:type/:ids", to: "syncs#create"` mirroring the deletions routes. JSON-aware.                                                                                                                             |
| `config/credentials.yml.enc`                                                                              | Add `:owner` block (user runs `bin/rails credentials:edit`).                                                                                                                                                                                                                                                                                                                  |
| `db/seeds.rb` (lines 9-60 currently create 10 channels with rich Alpha fields + 30/20 videos per channel) | Refactor: read `:owner`; seed Tenant; seed User; seed **100** Channels with the deterministic distribution per spec (7 starred, 6 connected, 2 in intersection). Keep the existing video/stat seeding using `Channel.id` (videos still belong_to channel). The current title-template lookup is keyed by `Channel.title` — rekey by `Channel.id` or by a deterministic index. |
| `app/models/concerns/searchable.rb`                                                                       | No edits required, but verify Channel no longer includes it.                                                                                                                                                                                                                                                                                                                  |
| `app/services/search/meilisearch_engine.rb`                                                               | Remove the Channel-specific branch.                                                                                                                                                                                                                                                                                                                                           |
| `app/services/search/engine.rb`                                                                           | Remove the Channel branch from the searchable-models registry.                                                                                                                                                                                                                                                                                                                |

### Repo: `pito-sh` (Lane 2a)

| File                                                                | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/api/models.rs`                                                 | Replace existing 8-field `Channel` struct (`id, youtube_channel_id, title, description, connected, subscriber_count, view_count, video_count`) with the 7-field new struct: `id, tenant_id, channel_url, star, connected, syncing, last_synced_at`. The `star`, `connected`, and `syncing` fields stay as `bool` internally but are annotated `#[serde(with = "yes_no")]` so JSON serialization/deserialization handles the `"yes"`/`"no"` wire format automatically. Add a `yes_no` serde module (in `src/api/yes_no.rs` or alongside) implementing `serialize`/`deserialize` for `bool` ↔ `"yes"`/`"no"`, rejecting any other input.                                                                    |
| `src/api/client.rs`                                                 | `MockClient` lines 24-57 contains 3 mock channels with the Alpha shape — refactor to the new shape. The `search` filter at line 444 currently filters by `c.title.to_lowercase().contains` — refactor to `c.channel_url.to_lowercase().contains`. List/get/create/update calls return the new shape. **Replace** any single-record `delete_channel(id)` and `sync_channel(id)` client methods with `bulk_delete_channels(ids: Vec<i64>, confirm: bool)` and `bulk_sync_channels(ids: Vec<i64>, confirm: bool)` matching the MCP/JSON-API two-step confirm flow. Single-record actions are made by passing a one-element `ids` vec. Client-side URL format validation matches the server regex (no drift). |
| `src/ui/channels.rs`                                                | Lines 14-31: `ChannelRow {id, title, connected, subscriber_count, video_count, view_count}` — replace with `ChannelRow {id, channel_url, star, connected, syncing, last_synced_at}`. Lines 95-113: table headers `title, OAuth, subs, videos, views` — replace with `URL (truncated), star, connected, syncing, last_synced_at`.                                                                                                                                                                                                                                                                                                                                                                          |
| `src/ui/channel_detail.rs`                                          | Lines 11-37: `ChannelInfo` carries the Alpha shape — refactor to the new shape; replace KV pairs accordingly. Show: full URL with `[ view ]` action invoking `xdg-open` (platform-appropriate); keys for star (`s`), connected (`c`), sync (`Y`), delete (through confirmation flow).                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `src/ui/channel_new.rs`                                             | New flow: prompt for URL with format hint; client-side regex check before submit.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `src/ui/channel_edit.rs`                                            | Edit: URL displayed locked; star + connected toggleable.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `src/ui/search.rs`                                                  | Lines 20-32: `SearchChannelHit {id, title, subscriber_count, connected}` — **remove** the channel-search hit type. Channel-search UI is removed (Searchable is dropped server-side). Replace with a simple "browse channels" link from the search screen, or drop the channel-results section entirely.                                                                                                                                                                                                                                                                                                                                                                                                   |
| `src/ui/confirm.rs`                                                 | Confirmation flow used by both single and bulk destructive actions, mirrored from web.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `src/app.rs`                                                        | Three mapping sites at lines 81-100, 199-230, 273-296 currently map old → new struct shapes. Refactor each to the new 7-field Channel struct.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `src/widgets/table.rs`                                              | Channel-agnostic; no required change. May be adopted by the new channels screen if useful.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `tests/api_channel_test.rs` (NEW — no tests exist in pito-sh today) | Channel struct deserialization from the new JSON shape. Roundtrip parsing with all 7 fields populated and with optional fields null. Assert that boolean fields parse from `"yes"`/`"no"` strings (NOT from JSON `true`/`false`) via the `yes_no` serde module, and that serialization emits `"yes"`/`"no"` strings; assert deserialization rejects `true`, `false`, `1`, `0`, `"on"`, etc. with an error.                                                                                                                                                                                                                                                                                                |
| `tests/ui_channel_test.rs` (NEW)                                    | UI render snapshots / unit tests for the channel list, detail, new, and edit screens.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `tests/url_validation_test.rs` (NEW)                                | Client-side URL format validation — same regex / behavior as the server. Positive + negative cases mirroring the model spec, ensuring no drift between Rust client and Rails server.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `tests/bulk_picker_test.rs` (NEW)                                   | Bulk picker flow: select 1+ channels (toggle selection); trigger bulk action (`D` or `Y`); preview screen renders with skip-badges for already-syncing channels; confirm with `y` calls the bulk MCP tool with `confirm: true`; cancel with any other key returns to the list with no API call.                                                                                                                                                                                                                                                                                                                                                                                                           |
| `tests/skip_badge_render_test.rs` (NEW)                             | Already-syncing channels render with a skip-badge in the in-TUI confirmation preview screen.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

### Repo: `pito-dev-kb`

| File                                                     | Purpose                                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `plans/beta/03-channel-revamp/plan.md`                   | Phase plan with checkboxes (created elsewhere, not here).                       |
| `plans/beta/03-channel-revamp/log.md`                    | Session log (created elsewhere, not here).                                      |
| `plans/beta/03-channel-revamp/specs/channel-revamp.md`   | This file.                                                                      |
| `decisions/0002-app-first-then-terminal-mcp-parallel.md` | No skips this phase; document explicitly that both Lane 2 surfaces participate. |

---

## 4. Implementation steps

### Phase A — Foundation (Lane 1, sequential)

These steps must land on `main` of the `pito` repo before any Lane 2 work
begins.

**A1. Tenant + User schema**

- Action: write migrations creating `tenants` and `users` tables; add models
  with validations and `Current` attributes; add the `before_action` shim.
- Expected outcome: `bin/rails db:migrate` is clean;
  `Tenant.create!(name: "Primary")` and `User.create!(...)` work;
  `Current.tenant`/`Current.user` available in controllers.
- Rollback: `bin/rails db:rollback STEP=2`.

**A2. Owner credentials block**

- Action: document the `:owner` schema in `pito/docs/setup.md`; user populates
  via `bin/rails credentials:edit`.
- Expected outcome: `Rails.application.credentials.owner` returns a hash or
  `nil`.
- Rollback: remove the block from credentials.

**A3. Channel migration**

- Action: write `revamp_channels` migration that drops Alpha columns, adds the
  new ones, adds the four indexes and the unique B-tree index on `channel_url`.
- Expected outcome: `Channel.column_names` matches the locked spec exactly.
- Rollback: `bin/rails db:rollback STEP=1` recreates Alpha columns as nullable;
  data restored from the most recent backup if needed.

**A4. Channel model**

- Action: rewrite `app/models/channel.rb` with associations, regex validation,
  lock-on-update guard, scopes, and `after_*_commit` callbacks. **Remove**
  `include Searchable`. Remove
  `encrypts :oauth_access_token, :oauth_refresh_token`. Drop the `public_only`
  scope. Drop `title` and `youtube_channel_id` validations.
- Expected outcome: model specs pass; updating `channel_url` on a persisted
  record raises; `Channel.included_modules` does not contain `Searchable`.
- Rollback: revert the file.

**A4b. Drop Searchable from Channel — surrounding cleanup**

- Action: remove `Channel` from `app/jobs/reindex_all_job.rb` iteration list;
  remove the Channel branch in `app/services/search/meilisearch_engine.rb` and
  `app/services/search/engine.rb`; remove the Channel branch in
  `app/controllers/search_controller.rb` (lines 13, 21); drop the
  channel-results table in `app/views/search/show.html.erb` (lines 21-41);
  update `spec/services/search/meilisearch_engine_spec.rb` and
  `spec/models/concerns/searchable_spec.rb` to drop Channel assertions.
- Expected outcome: `Channel` is no longer indexed, queried, or rendered through
  the search surface; specs green.
- Rollback: revert all files in this step.

**A4c. SavedView label refactor**

- Action: edit `app/models/saved_view.rb` line 31 — replace `entity&.title` with
  kind-aware dispatch (`kind == "channels" ? entity&.id&.to_s : entity&.title`).
  Update `spec/models/saved_view_spec.rb` and
  `spec/components/saved_views_section_component_spec.rb`. Note: Channel labels
  use `id.to_s` for now; when YouTube sync lands and channels gain a synced
  title or display field, this rule may be revisited.
- Expected outcome: saved-view labels render the channel id (as a string) for
  channel-kind saved views; video-kind saved views unaffected;
  `display_name_with_deletions` continues to work.
- Rollback: revert the file.

**A5. ChannelSync job + cron**

- Action: implement `ChannelSync` (Sidekiq) with the locked lifecycle; add
  `SyncStarredChannelsJob`; register in `config/sidekiq_cron.yml`.
- Expected outcome: enqueuing `ChannelSync.perform_async(channel.id)` flips
  `syncing` and stamps `last_synced_at`; deleting the channel mid-job does not
  raise.
- Rollback: revert files; `bin/sidekiq` no longer schedules the cron.

**A6. ChannelsController + routes**

- Action: rewrite controller. Strong params: `[:channel_url, :star, :connected]`
  for `create`; `[:star, :connected]` for `update`. Drop the
  auto-`youtube_channel_id = "local_..."` line in `create`. Replace every
  `.order(title: :asc)` with `.order(channel_url: :asc)` or
  `.order(created_at: :desc)`. Add member `sync` and collection `bulk_sync` /
  `bulk_destroy` routes; respond to JSON. Update
  `app/controllers/deletions_controller.rb` lines 35 and 63 to use
  `.order(channel_url: :asc)`.
- Expected outcome: request specs pass; URL-change attempt returns 422 with
  structured error.
- Rollback: revert.

**A6b. Confirmable concern + SyncsController**

- Action: extract `app/controllers/concerns/confirmable.rb` from
  `DeletionsController` (`load_items`, `cancel_path`, type→model dispatch).
  Include in `DeletionsController`. Create `app/controllers/syncs_controller.rb`
  mirroring DeletionsController, using `Confirmable`. Add routes
  `get/post "syncs/:type/:ids"`. Implement pre-flight skip logic in `load_items`
  and `create`: partition channels by `syncing: true`/`false`; for
  already-syncing channels, create the `bulk_operation_item` directly with
  `status: :skipped` and `error_message: "already syncing"`. Mark this step
  "should-do — defer if disruptive."
- Expected outcome: `DeletionsController` and `SyncsController` both delegate to
  `Confirmable`; existing deletion specs still green; new syncs request specs
  green.
- Rollback: revert; if Confirmable extraction is too disruptive mid-phase, leave
  duplicated code in `SyncsController` and document in `dropped.md`.

**A6c. BulkOperation + BulkOperationItem enum extensions**

- Action: extend `BulkOperation.kind` enum from 5 to 6 values (`bulk_sync: 5`);
  extend `BulkOperationItem.status` enum from 3 to 4 values (`skipped: 3`). No
  migration — both are integer-backed. Update factory and existing specs.
- Expected outcome: `BulkOperation.kinds.size == 6`;
  `BulkOperationItem.statuses.size == 4`; no schema change required.
- Rollback: revert the model files.

**A7. Views + UX**

- Action: implement index/show/new/edit views per the locked design rules.
  Refactor every Channel-using view: `_picker.html.erb`, `_pane.html.erb`,
  `_form.html.erb`, `panes.html.erb`, `_add_pane_dialog.html.erb`,
  `show.html.erb` to drop Alpha-field references and use `channel_url`. Refactor
  `app/views/videos/_form.html.erb` line 8: `Channel.order(:title)` →
  `Channel.order(:channel_url)`, display by `:channel_url`. Refactor
  `app/views/videos/index.html.erb`, `_pane.html.erb`,
  `_add_pane_dialog.html.erb` (replace `video.channel.title` with
  `video.channel.channel_url` truncated, or drop the column). Refactor
  `app/controllers/dashboard_controller.rb` lines 5, 14-19, 49
  (`views_by_channel` chart): GROUP BY `channels.channel_url`. Note:
  single-delete is **already** routed through `/deletions/channel/:id`; no
  JS-confirm migration needed.
- Expected outcome: `bin/dev` renders all four views; clicking `[ delete ]` on a
  single channel routes to the confirmation page (already wired); clicking
  `[ sync ]` on a syncing channel from a bulk submission shows it as `[ skip ]`.
- Rollback: revert.

**A7b. Skip-state branches across the bulk-operation UI**

- Action: add `elsif status == "skipped"` branch in
  `app/views/bulk_operations/_item_row.html.erb` rendering red bracketed
  `[ skip ]`. Add `else if (item.status === "skipped")` branch in
  `app/javascript/controllers/operation_progress_controller.js` `_applyState`
  writing the same `[ skip ]` markup so the JSON-fallback path matches the cable
  path. Render `<span class="bracketed text-danger">[ skip ]</span>` in
  `#item_status_<id>` on `app/views/syncs/progress.html.erb` for already-skipped
  rows. On `app/views/syncs/show.html.erb`, render skip rows in red `[ skip ]`
  with casual muted message ("already humming away"); add footer note ("X
  channels will be skipped (already syncing)"); disable submit if all rows are
  skipped.
- Expected outcome: skip badge renders consistently across the cable path,
  JSON-fallback path, the confirmation page, and the progress page.
- Rollback: revert.

**A7c. bulk_select_controller updates**

- Action: in `app/javascript/controllers/bulk_select_controller.js` (lines
  68-87), add `syncAction` Stimulus target and `syncTypeValue`. Mirror the
  `[ delete N ]` link generation to render `[ sync N ]` linking to
  `/syncs/${syncTypeValue}/${ids}` with the `bracketed` class (NOT
  `text-danger`).
- Expected outcome: bulk-select on the channels index renders both
  `[ delete N ]` and `[ sync N ]` action chips with correct routing.
- Rollback: revert.

**A8. BulkSyncJob**

- Action: implement `app/jobs/bulk_sync_job.rb` mirroring
  `app/jobs/bulk_delete_job.rb`. `Sidekiq::Job`, queue `bulk_sync`, three
  private broadcast helpers (`broadcast_status`, `broadcast_progress`,
  `broadcast_item_status`), broadcasting via
  `Turbo::StreamsChannel.broadcast_replace_to` to stream
  `"bulk_operation_#{id}"`. **Do NOT fail-fast** — sync errors mark per-item
  failed and the loop continues. When iterating, `next` on items already in
  `:skipped` and do not broadcast a new state. Pre-load the progress counter
  with the skipped count (e.g. `2 of 5` at submit time).
- Expected outcome: `spec/jobs/bulk_sync_job_spec.rb` (cloned from
  `bulk_delete_job_spec.rb`) passes including the "with already-syncing channel"
  context. System spec confirms the progress bar starts at the pre-skipped count
  and per-channel done events arrive over Turbo Streams.
- Rollback: revert.

**A9. Seeds**

- Action: rewrite `db/seeds.rb` to read `:owner`, seed Tenant + User, seed 100
  channels with the deterministic distribution and stable RNG-derived URLs.
  Stagger `created_at` across the past 60 days.
- Expected outcome: `bin/rails db:seed` is idempotent on a fresh DB; counts and
  distribution match (7 starred, 6 connected, 2 in intersection); seeds spec
  passes.
- Rollback: revert; truncate via `bin/rails db:reset`.

**A10. Lane 1 reviewer pass**

- Action: reviewer agent runs the full suite (RSpec, Brakeman, bundler-audit,
  Rubocop) and produces a manual playbook in
  `pito-dev-kb/orchestration/playbooks/03-channel-revamp.md`.
- Expected outcome: all green; playbook exists.
- Rollback: fix issues, re-run; do not proceed to Phase B until green.

### Phase B — Parallel fan-out (Lane 2a + Lane 2b)

After A10 merges, A11 and A12 spawn simultaneously and run independently.

**A11. Lane 2b — MCP tools**

- Action: refactor existing channel tools (`create_channel.rb`,
  `update_channel.rb`, `get_channel.rb`, `list_channels.rb`) to the new shape;
  add `bulk_delete_channels.rb` and `bulk_sync_channels.rb` with the two-step
  `confirm` flow (see step A11b for the full refactor); refactor references in
  `delete_records.rb` (drop Channel branch), `get_dashboard.rb`,
  `search_content.rb` (drop the Channel branch since Channel is no longer
  searchable), and `app_status.rb`. **Drop** any single-record
  `sync_channel(id:)` or `delete_channel(id:)` tools from registration. Reject
  URL changes in `update_channel` either silently (drop the param) or with a
  structured error.
- Expected outcome: `bundle exec rspec spec/mcp/tools` green; manually invoking
  each tool against the running MCP server returns the new shape.
- Rollback: revert tool files; restore the previous registration.

**A12. Lane 2a — pito-sh terminal app**

- Action: update `src/api/models.rs` and `src/api/client.rs` to the new shape;
  rewrite the channel UI screens; wire `[ view ]` to platform-appropriate open;
  implement the confirmation flow mirroring the web confirmation page; add
  tests.
- Expected outcome: `cargo test` green; running `pito-sh` against a live `pito`
  server lists the seeded 100 channels with correct icons and indicators;
  star/connected toggles persist; sync triggers visible syncing state.
- Rollback: revert files; rebuild.

**A11b. Lane 2b — MCP confirm-flag refactor (bulk_delete_channels +
bulk_sync_channels)**

- Action: drop any registered single-record `sync_channel(id:)` and
  `delete_channel(id:)` tools from MCP server registration. Refactor
  `delete_records` to drop its Channel branch (channel deletes flow through
  `bulk_delete_channels`). Implement `bulk_delete_channels.rb` and
  `bulk_sync_channels.rb` with the two-step confirm flow: input schema
  `{ ids: [int], confirm: bool }`. First call (no `confirm` or
  `confirm: false`): build and return a structured preview. NO `BulkOperation`
  created, no items, no job enqueued. Second call (`confirm: true`): build the
  `BulkOperation` (`kind: :bulk_delete` or `:bulk_sync`), build items (with
  `status: :skipped` pre-marked for already-syncing channels in the sync case),
  enqueue the corresponding job, return `{ operation_id, progress_url }`.
  Document the schema inline or in `app/mcp/tools/SCHEMA_DOCS.md`.
- Expected outcome: `bundle exec rspec spec/mcp/tools/bulk_*_channels_spec.rb`
  green; manually invoking each tool against the running MCP server returns a
  preview on the first call and creates a `BulkOperation` on the second call.
- Rollback: revert the new tool files and the registry change.

**A12b. Lane 2a — pito-sh terminal bulk-flow refactor**

- Action: refactor any existing single-channel delete / sync key bindings so
  they no longer immediately fire. Highlighted channel becomes the implicit
  selection of one; pressing `D` opens the bulk delete preview; pressing `Y`
  opens the bulk sync preview. The preview is an in-TUI confirmation screen (NOT
  a system dialog) listing selected channels with skip badges for any
  already-syncing. User presses `y` to confirm or any other key to cancel. On
  confirm, the terminal calls the corresponding bulk MCP tool with
  `confirm: true`. Implement client-side URL format validation in
  `src/api/client.rs` (or a new `src/validation.rs`) matching the server regex.
- Expected outcome: `cargo test` green including the new
  `tests/bulk_picker_test.rs`, `tests/skip_badge_render_test.rs`,
  `tests/url_validation_test.rs`. Manual run shows: highlighting a channel and
  pressing `D` opens preview, `y` deletes, any other key cancels.
- Rollback: revert files; rebuild.

**A13. Lane 2 reviewer pass**

- Action: reviewer agents (one per lane) run their suites and append findings to
  the playbook.
- Expected outcome: green on both lanes.
- Rollback: per-lane fix and re-run.

**A14. Dashboard chart sync persistence (Stimulus + ERB)**

- Action: add `data-chart-id="<slug>"` attributes to every chart container in
  `app/views/dashboard/index.html.erb` with deterministic slugs (`daily-views`,
  `views-by-channel`, `top-videos`, `daily-engagement`). For sync-capable line
  charts only, also set `data-chart-sync-target="chart"` and render the existing
  `[ ] sync` `CheckboxComponent` in the chart header, wired with
  `data-chart-sync-target="checkbox"`, `data-chart-id="<slug>"`, and
  `data-action="change->chart-sync#toggle"`. Bar charts (e.g., `top-videos`) get
  the `data-chart-id` only — no sync target, no checkbox. Extend the existing
  `app/javascript/controllers/chart_sync_controller.js` to own seeding +
  persistence: on `connect()`, read
  `localStorage.getItem("pito_dashboard_charts_synced")`; if null, write the
  full set of sync-capable chart slugs present on the page (default ACTIVE); for
  each chart, set the checkbox `checked` state AND set/remove the chart
  container's `data-sync-group="dashboard"` based on the array. On `toggle`,
  update the array, persist, re-apply. Attach the controller to the dashboard
  root via `data-controller="chart-sync"` in
  `app/views/dashboard/index.html.erb`. **No chart-hiding / chart-visibility
  toggle is added** — there is no `[ ] include` or `[ ] show` checkbox; the only
  checkbox per chart is the existing `[ ] sync` for crosshair sync. Use
  `CheckboxComponent` (design-system `md-check`); never a native
  `<input type="checkbox">`.
- Expected outcome: first visit shows all charts, all checkboxes checked,
  localStorage written with the full slug array. Unchecking a chart hides it and
  removes its slug from the array. Refresh preserves visibility state. Different
  browsers / devices behave independently (per-browser by design).
- Rollback: revert the controller and the partial edits.

**A15. Comprehensive test coverage pass**

- Action: walk the spec section by section and verify every restriction,
  enforcement, and format rule has explicit test coverage in at least one of the
  three lanes (Rails RSpec, MCP RSpec, pito-sh `cargo test`). Use the "Test
  scenarios" list in section 5 as the canonical checklist. For any gap
  discovered, add the missing spec.
- Expected outcome: every named scenario in section 5 maps to one or more
  concrete spec files; `bundle exec rspec` and `cargo test` both green; the
  reviewer playbook records which scenarios were exercised manually.
- Rollback: not applicable — this step only adds tests.

**A16. ux-defaults.md update (parallel — not in this repo)**

- Action: tracked in parallel by the architect-spec stream. The
  `pito-dev-kb/orchestration/ux-defaults.md` file is updated to extend the
  existing "`[ ] sync` checkboxes default to active on all sync-capable charts"
  rule with the localStorage persistence behavior (key
  `pito_dashboard_charts_synced`, JSON array of synced chart slugs, first-visit
  initialization to all-on for every sync-capable chart, design-system bracketed
  checkbox via `CheckboxComponent` only).
- Expected outcome: `ux-defaults.md` reflects the persistence behavior;
  cross-referenced from this spec.
- Rollback: not applicable in this phase folder.

---

## 5. Acceptance criteria

- [ ] `tenants` and `users` tables exist with the locked columns and indexes.
- [ ] `users` table has exactly:
      `id, tenant_id, username, email, password_digest, created_at, updated_at`.
      NO `name` column.
- [ ] `users.username` and `users.email` each have a single-column unique index
      — NOT scoped to `tenant_id`.
- [ ] `User` username regex is exactly `\A[A-Za-z][A-Za-z0-9]*\z`. Specs cover
      positive (`asdk123`, `M23kony`) and negative (`123abc`, `Catalin Ilinca`)
      cases.
- [ ] `channels` table contains exactly:
      `id, tenant_id, channel_url, star, connected, syncing, last_synced_at, created_at, updated_at`.
- [ ] All Alpha columns on `channels` are dropped.
- [ ] Unique B-tree index on `channels.channel_url` is case-sensitive.
- [ ] Indexes exist on `(tenant_id, star)`, `(tenant_id, connected)`,
      `(tenant_id, syncing)`, `(last_synced_at)`.
- [ ] `Channel` validates URL against
      `\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z`.
- [ ] Updating `channel_url` on a persisted record raises.
- [ ] Controller `update` permits only `:star, :connected`.
- [ ] `Channel.after_create_commit` and
      `Channel.after_update_commit (when star toggled on)` enqueue
      `ChannelSync`.
- [ ] `ChannelSync` flips `syncing` true on entry, false in `ensure`, and stamps
      `last_synced_at` if the record still exists.
- [ ] `SyncStarredChannelsJob` runs at midnight UTC via `sidekiq-cron`.
- [ ] `BulkSync` mirrors `BulkDelete` (same operation framework, Turbo Streams
      over ActionCable, Stimulus controller, confirmation page).
- [ ] `BulkSyncJob` does NOT fail-fast on per-item errors; the loop continues
      for remaining items.
- [ ] `BulkOperation.kind` enum has exactly 6 values (`update_metadata`,
      `update_privacy`, `add_to_playlist`, `remove_from_playlist`,
      `bulk_delete`, `bulk_sync`).
- [ ] `BulkOperationItem.status` enum has exactly 4 values (`pending`,
      `succeeded`, `failed`, `skipped`).
- [ ] Channels with `syncing: true` render in red as `[ skip ]` on the bulk-sync
      confirmation page AND the progress page.
- [ ] The skip badge renders consistently via the cable path, the JSON-fallback
      path in `operation_progress_controller.js`, and the static partial.
- [ ] Bulk-sync progress starts pre-loaded with the skipped count.
- [ ] `Confirmable` concern exists at `app/controllers/concerns/confirmable.rb`
      and is included by both `DeletionsController` and `SyncsController` (or
      this is documented as deferred in `dropped.md`).
- [ ] Single delete routes through the action confirmation page (this was
      already true pre-phase; verified to remain true).
- [ ] `Channel` does NOT include `Searchable`; `Channel.included_modules` is
      asserted to exclude it.
- [ ] `ReindexAllJob` no longer touches `Channel`.
- [ ] The search engine and search controller no longer have a Channel branch.
- [ ] `app/views/search/show.html.erb` no longer contains the channel-results
      table.
- [ ] `SavedView#entity_labels` renders `id.to_s` for `kind == "channels"` and
      `title` for `kind == "videos"`.
- [ ] `bulk_select_controller.js` exposes a `[ sync N ]` action chip in addition
      to `[ delete N ]`.
- [ ] Every channel view shows `[ view ]` linking to the canonical URL with
      `target="_blank" rel="noopener noreferrer"`.
- [ ] `Tenant`, `User`, and `Channel` specs cover the locked behavior including
      `find_by_username_or_email`.
- [ ] `db/seeds.rb` produces 100 channels with the locked distribution from
      `:owner` credentials, with stable URLs across re-runs.
- [ ] All seven MCP tools are registered and pass their specs.
- [ ] `pito-sh` `cargo test` green; UI shows the new fields and supports
      star/connected/sync/delete via the confirmation flow.
- [ ] Brakeman clean; bundler-audit clean.
- [ ] Manual playbook exercised end-to-end by the user.

### 5b. Restrictions / enforcements / format rules — explicit coverage checklist

Every item in this list MUST have at least one corresponding test (Rails RSpec,
MCP RSpec, or pito-sh `cargo test`).

- [ ] URL format regex enforced: positive case
      `https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ` accepted;
      negatives `youtube.com/@handle`, `https://youtu.be/...`,
      `https://www.youtube.com/c/somename`,
      `https://www.youtube.com/user/legacy`,
      `http://www.youtube.com/channel/UC...` (http not https),
      `https://youtube.com/channel/UC...` (missing `www.`), empty string — all
      rejected.
- [ ] URL locked on update: model `before_update` guard, controller strong
      params (no `:channel_url` permitted in `update`), MCP `update_channel`
      rejection. All three layers tested.
- [ ] Username regex `\A[A-Za-z][A-Za-z0-9]*\z` enforced: positive `asdk123`,
      `M23kony`; negative `123abc`, `Catalin Ilinca`, `me_too`.
- [ ] Username + email global uniqueness (single-column unique indexes; not
      scoped to tenant).
- [ ] Tenant name length 3..30 enforced.
- [ ] Channel `syncing` flag set true on job start, false on job end (in
      `ensure`).
- [ ] `ChannelSync` graceful nil — deleted-channel-mid-job does not raise;
      `Channel.exists?(id:)` check before final update.
- [ ] Channel destroy works while a sync job is queued (no exception when job
      runs against deleted channel).
- [ ] `BulkOperationItem` rows in `:skipped` status are NOT invoked by
      `BulkSyncJob` (no broadcast, no service call).
- [ ] Confirmation page renders skip badges for already-syncing channels (web,
      MCP preview, pito-sh in-TUI).
- [ ] `bulk_select_controller.js` generates correct URLs for delete
      (`/deletions/:type/:ids`) and sync (`/syncs/:type/:ids`); accepts 1 or
      many comma-separated IDs.
- [ ] Star toggle to true enqueues `ChannelSync` (after_update_commit).
- [ ] Cron enqueues `ChannelSync` for all starred channels daily at midnight
      UTC.
- [ ] Channels list filters by star, by connected, by syncing.
- [ ] No JavaScript `alert`, `confirm`, `prompt`, or `data-turbo-confirm`
      anywhere in code touched by this phase — specifically the channel UX, the
      syncs UI, and any dashboard chart partials (grep gate; SavedView delete is
      exempt as legacy, not touched this phase).
- [ ] Dashboard chart `[ ] sync` (crosshair-sync) state persists in localStorage
      across page reload under key `pito_dashboard_charts_synced`. First-visit
      seeds all sync-capable chart-ids as checked. The `[ ] sync` checkbox uses
      `CheckboxComponent` (bracketed design-system style); native
      `<input type="checkbox">` is not used on the dashboard.

### 5c. Test scenarios (named, gating)

Each named scenario must exist as a concrete test (or named `it` / `describe`
block) in at least one spec file. Use these names verbatim where possible.

- [ ] "Create channel happy path" (web request spec + MCP
      `create_channel_spec.rb`)
- [ ] "Create channel rejects invalid URL" (web request spec + MCP
      `create_channel_spec.rb`; covers all negative URL cases)
- [ ] "Update channel rejects URL change" (web request spec + MCP
      `update_channel_spec.rb`; returns 422 on web, structured rejection on MCP)
- [ ] "Bulk sync 5 channels with 2 already syncing" (web request spec for
      `SyncsController#create` + MCP `bulk_sync_channels_spec.rb`; assert
      progress starts at `2 of 5`, ends at `5 of 5`)
- [ ] "Sync single channel via bulk URL" (web request spec; `/syncs/channel/:id`
      with one comma-separated ID works exactly like multi-id case)
- [ ] "Delete channel propagates to syncing job (graceful nil)"
      (`spec/jobs/channel_sync_spec.rb`; channel destroyed mid-job does not
      raise; `ensure` block runs)
- [ ] "Star toggle to true enqueues ChannelSync" (`spec/models/channel_spec.rb`;
      `after_update_commit` callback)
- [ ] "Cron enqueues ChannelSync for all starred channels daily at midnight UTC"
      (`spec/jobs/sync_starred_channels_job_spec.rb`)
- [ ] "Channels list filters by star, by connected, by syncing"
      (`spec/requests/channels_spec.rb` + `spec/system/channels_spec.rb`)
- [ ] "Saved views label renders correctly with new Channel column"
      (`spec/models/saved_view_spec.rb`; channel-kind labels use `id.to_s`,
      video-kind still use `title`)
- [ ] "Dashboard chart `[ ] sync` state persists in localStorage" (system spec
      or Stimulus-only test; toggle one sync-capable chart's checkbox, refresh,
      assert it stays unchecked and the container's `data-sync-group` is gone)
- [ ] "Seed integrity" (`spec/seeds_spec.rb`; counts: Tenant=1, User=1,
      Channel=100; distribution: star=7, connected=6, intersection=2; URL format
      on all 100)
- [ ] "BulkSync no-fail-fast" (`spec/jobs/bulk_sync_job_spec.rb`; one item
      raises and the loop continues for remaining items)
- [ ] "MCP bulk_delete_channels two-step confirm"
      (`spec/mcp/tools/bulk_delete_channels_spec.rb`; first call preview only,
      no `BulkOperation`; second call creates and enqueues)
- [ ] "MCP bulk_sync_channels two-step confirm"
      (`spec/mcp/tools/bulk_sync_channels_spec.rb`; same as above)
- [ ] "Terminal bulk picker → confirmation → execute"
      (`tests/bulk_picker_test.rs`; full happy path)
- [ ] "Terminal client URL validation matches server regex"
      (`tests/url_validation_test.rs`; no drift between Rust and Rails)

---

## 6. Manual test recipe

Run each step. Stop and report on the first failure.

1. `bin/rails credentials:edit` — populate `:owner` with tenant_name, username,
   email, password.
2. `bin/rails db:drop db:create db:migrate db:seed` — should print no warnings;
   should report 100 channels seeded.
3. `bin/dev` — start Web Puma, MCP Puma, Sidekiq, Tailwind.
4. Visit `https://app.pitomd.com/channels` — list shows 100 rows; 7 starred
   icons; 6 connected icons; `last_synced_at` blanks initially. Toggle the
   `starred` filter chip; URL becomes `?starred=yes` (NOT `=true`/`=1`); list
   narrows to 7. Hit `/channels.json` — `star`, `connected`, `syncing` render as
   `"yes"`/`"no"` strings, never as JSON booleans.
5. Click a starred channel; click `[ sync ]`; observe `syncing` pill on index
   within ~1 second; pill clears within a few seconds; `last_synced_at`
   populates.
6. Visit `/channels/new`, paste `https://www.youtube.com/@somehandle` — form
   rejects with the example URL message.
7. Paste `https://www.youtube.com/channel/UC2T-WgvF-DQQfFNQieoRuQQ` — channel
   created; observe `ChannelSync` runs immediately (after-create callback).
8. Edit the new channel; URL field is readonly/disabled; toggle star on; submit;
   observe `ChannelSync` re-enqueues (after-update star-toggled).
9. From the index, select 5 channels including **2 already syncing**; click
   `[ sync ]`; on the confirmation page, the 2 syncing rows render red as
   `[ skip ]` with the casual muted message and a footer "2 channels will be
   skipped (already syncing)"; submit; on the progress page the 2 skipped rows
   still show `[ skip ]` (red bracketed) while the other 3 progress through
   `dot-loader` → `dot-done`; counter starts at `2 of 5` and ends at `5 of 5`.
10. From the index, select 3 channels; click `[ delete ]`; confirmation page
    renders; submit; observe rows disappear; Turbo Streams progress completes.
    10b. Visit a saved-view list that includes a channel-kind saved view; verify
    the label renders the channel `id.to_s` (not a blank or "title" call).
    Verify a video-kind saved view still renders the video title. 10c. Visit
    `/search?q=youtube` — the channel-results table should NOT appear; only
    video / playlist results render.
11. Click `[ view ]` on any row; new tab opens at the canonical URL with
    `noopener noreferrer`.
12. Run `bundle exec rspec` — green.
13. Open `pito-sh` against the running server. List shows 100 channels with
    icons. Press `s` on a channel — star toggles. Press `Y` — sync triggers and
    the syncing indicator appears. Trigger delete — confirmation flow appears,
    accept, channel disappears. 13b. In `pito-sh`: highlight a single channel
    and press `D` — bulk delete preview opens (NOT an immediate delete). Press
    any non-`y` key — preview closes, no API call. Repeat with a multi-select
    (space to toggle 3 channels), press `D`, press `y` — bulk delete fires.
    Repeat the flow with `Y` for bulk sync, including a selection containing 1+
    already-syncing channels — preview shows red `[ skip ]` badges for them.
14. Open the MCP server (`bin/mcp` or via the configured client). Call
    `list_channels(star: "yes")` — returns 7. Calling with `star: true`
    (boolean) is rejected with a clear error. Inspect a returned channel —
    `star`, `connected`, `syncing` are emitted as `"yes"`/`"no"` strings. Call
    `update_channel(id: <one>, channel_url: "https://...")` — returns rejection
    or ignores URL. Call `bulk_sync_channels({ids: [a,b,c]})` (no `confirm`) —
    returns a preview structure
    `{ total: 3, syncable: [...], skipped: [...], message: "..." }` with NO
    `BulkOperation` created. Call again with
    `bulk_sync_channels({ids: [a,b,c], confirm: true})` — creates the
    `BulkOperation`, returns `{ operation_id, progress_url }`, and progress
    becomes visible in the web UI. 14b. Repeat step 14 for
    `bulk_delete_channels({ids: [d,e]})` and
    `bulk_delete_channels({ids: [d,e], confirm: true})`.
15. Wait until the next midnight UTC (or manually trigger
    `SyncStarredChannelsJob.perform_async`). Confirm exactly 7 `ChannelSync`
    jobs enqueue. 15b. Visit `/dashboard`. Confirm every sync-capable chart's
    `[ ] sync` checkbox renders as `[x]` on first visit (default ACTIVE). The
    bar chart `top videos by views` has NO `[ ] sync` checkbox (not
    sync-capable) — that is correct. Open browser devtools, inspect
    `localStorage.getItem("pito_dashboard_charts_synced")` — expect a JSON array
    containing every sync-capable chart slug present on the page (e.g.,
    `["daily-views","views-by-channel","daily-engagement"]`). Uncheck one
    chart's `[ ] sync`; observe the indicator becomes `[ ]`; observe the chart
    container's `data-sync-group` attribute is removed (devtools Elements panel)
    and the array in localStorage no longer contains that slug; hovering that
    chart no longer drives the crosshair on the others. Refresh the page; the
    checkbox stays `[ ]`; the array still excludes that slug. Re-check it; the
    indicator becomes `[x]`; `data-sync-group="dashboard"` returns; the slug
    returns to the array. **Note:** there is no chart-hiding behavior — toggling
    `[ ] sync` only affects crosshair sync, never visibility.
16. Brakeman + bundler-audit + Rubocop — clean. Grep gate:
    `rg -n 'data-turbo-confirm|window\.confirm|window\.alert|window\.prompt' app/`
    should return zero hits in the channels surface.

---

## 7. Risks and open questions

- **Resolved (audit #4)**: the bulk-operation framework lives in `BulkOperation`
  (kind enum) + `BulkOperationItem` (status enum) + `BulkDeleteJob` (Sidekiq) +
  `Turbo::StreamsChannel.broadcast_replace_to "bulk_operation_#{id}"` for
  realtime + `operation_progress_controller.js` (Stimulus) +
  `DeletionsController` (action-confirmation). Pito uses **Turbo Streams via
  ActionCable**, not custom ActionCable channels. `BulkSync` is structurally
  identical: extend the kind enum, add `BulkSyncJob`, add `SyncsController`, add
  `syncs/{show,progress}.html.erb`, add `[ skip ]` branches.
- **Resolved (audit #1)**: `videos.channel_id`, `playlists.channel_id`,
  `video_uploads.channel_id` continue to reference `channels.id`. They survive
  untouched this phase. Their owning models are revamped in later phases. No
  `youtube_channel_id`-keyed queries remain (the column is dropped); seed-side
  title-template lookups currently keyed on `Channel.title` rekey to
  `Channel.id` or a deterministic index.
- **Resolved (audit #2)**: pito-sh existing struct + screen layout enumerated
  above (8-field Channel struct in `src/api/models.rs`; `ChannelRow` in
  `src/ui/channels.rs:14-31`; `ChannelInfo` in `src/ui/channel_detail.rs:11-37`;
  `SearchChannelHit` in `src/ui/search.rs:20-32`; mapping sites in
  `src/app.rs:81-100,199-230,273-296`; mock channels in
  `src/api/client.rs:24-57` and search filter at `client.rs:444`).
  Channel-search UI is removed.
- **Resolved (audit #1 + late clarification 2)**: existing Channel MCP tools are
  `create_channel`, `update_channel`, `get_channel`, `list_channels`. Tools that
  reference Channel and need refactor: `delete_records` (drop Channel branch),
  `get_dashboard`, `search_content`, `app_status`. New tools:
  `bulk_delete_channels`, `bulk_sync_channels` — both with the two-step
  `{ ids, confirm }` flow. There are **NO** single-record `sync_channel(id:)` or
  `delete_channel(id:)` tools; single-record actions ride the bulk tools with
  `ids: [single_id]`. Registration mechanism: implementer adapts to whatever the
  existing tools use.
- **Resolved (audit #5)**: the framework is `DeletionsController` +
  `app/views/shared/_action_screen.html.erb`. Naming: "action screen".
  `SyncsController` is a sibling that mirrors `DeletionsController`'s shape via
  the new `Confirmable` concern. The remaining JS `confirm()` dialogs are all on
  SavedView delete actions — out of scope for this phase.
- **Cache `Current` lifetime**: `Current` is request-scoped per Rails
  convention. This is fine for web, but the MCP request flow (HTTP transport)
  and Sidekiq job context must each set `Current` explicitly. ChannelSync runs
  without a `Current` shim today; that is acceptable because Channel access uses
  `Channel.find_by(id: …)` directly. Confirm in code review that no service
  called from within ChannelSync depends on `Current`.
- **Race condition**: deletion-during-sync is exercised in the job spec; the
  `ensure` block uses `Channel.exists?(id: …)` to avoid resurrecting a deleted
  row.
- **Time travel**: `last_synced_at` uses `Time.current`. Test specs that freeze
  time must use `ActiveSupport::Testing::TimeHelpers#travel_to`.
- **Open question — implementer-resolvable**: should `update_channel` MCP tool
  reject URL silently (drop the param) or raise a structured error? Decision
  allows both; the implementer picks one and records the choice in
  `additions.md`.
- **Risk — disruptive refactor**: the `Confirmable` concern extraction (step
  A6b) is small but touches an existing controller. If extraction proves too
  disruptive mid-phase, the implementer may defer it and document the deferral
  in `dropped.md`. The phase still succeeds with duplicated code in
  `SyncsController`.
- **By design — localStorage is per-browser**: dashboard chart `[ ] sync`
  preferences do NOT sync across devices or browsers. A user who unchecks
  `[ ] sync` on a chart on their laptop will still see it synced on their phone.
  This is intentional for this phase; cross-device sync would require a
  server-side per-user preference store, which is out of scope (User schema is
  locked to identity columns only).
- **By design — bulk pattern is the foundation for future operations**: the
  `BulkSync` + `SyncsController` + `Confirmable` triple is a reusable skeleton.
  Future bulk operations (bulk metadata update, bulk privacy change, bulk
  add-to-playlist, bulk thumbnail update) will extend the `BulkOperation.kind`
  enum and add a sibling controller + job. Naming and shape are locked here so
  future contributors do not re-invent the pattern.

---

## 8. Out of scope

- No `Auth::Concern`, no controller-level authentication, no token authorization
  on either Puma. Auth lands in the deferred Phase 3 successor.
- No login UI, no signup, no password reset, no session controller.
- No Doorkeeper, no OAuth server, no scoped tokens, no `ApiToken` model.
- No Google OAuth, no Google sign-in.
- No real YouTube Data API or YouTube Analytics calls — `ChannelSync` is a
  placeholder.
- No video workflow features (upload form, scheduling, thumbnails, playlists,
  calendar).
- No new dashboard charts and no changes to existing chart data sources.
  **However**, this phase DOES add a small dashboard feature: per-chart
  `[ ] sync` (crosshair-sync) state persisted to `localStorage` (key
  `pito_dashboard_charts_synced`). The existing `[ ] sync` checkboxes default to
  active per `orchestration/ux-defaults.md`; this phase extends that rule with
  persistence behavior. See section 4 step A14 and section 2 for details. **No
  chart-hiding / chart-visibility toggle is introduced** — the dashboard's only
  per-chart checkbox is the existing `[ ] sync`. The `views_by_channel` chart's
  GROUP BY column also changes from `channels.title` to `channels.channel_url`
  (or the chart is dropped per implementer's call) because `title` no longer
  exists on Channel. No other dashboard changes.
- No multi-tenant UI: no tenant switcher, no tenant admin, no signup flow.
- No `pito-website` work, no `pito-dev-kb` content beyond this phase folder.
- No Hetzner deployment, no Kamal config changes.
- No backup/restore tooling.
- No observability dashboards.
- No security-hardening pass beyond Brakeman + bundler-audit clean as a quality
  gate.
- No Lane 2 skips: both `pito-sh` and the MCP surface fully participate.
  `decisions/0002-app-first-then-terminal-mcp-parallel.md` skip-list is
  unchanged.
- No Searchable on Channel anymore. Channel is dropped from search indexing, the
  search controller, the search engine, and the search UI on both web and
  pito-sh. Restoring channel search is a future phase concern.
- SavedView delete keeps its existing Turbo / JS confirm dialog. Migrating
  SavedView delete to the action-confirmation framework is **out of scope** for
  this phase.
- Single-channel delete migration to the action-confirmation framework is
  **not** in scope because the audit confirms it is already wired
  (`channels/show.html.erb:6` links to `/deletions/channel/#{@channel.id}`).
- No `User#name` column or display name field. Identity is `username` + `email`
  only. A separate display name lands in a future phase if and when needed.
- **No JavaScript `alert`, `confirm`, `prompt`, or `data-turbo-confirm` dialogs
  in code touched by this phase** (project-wide hard rule going forward). The
  action confirmation page is the canonical replacement for every destructive or
  expensive action. Any spec or template touched in this phase that lists
  `data-turbo-confirm` or `confirm:` link options must be amended to remove
  them. SavedView delete keeps its existing JS confirm dialog because it is not
  touched in this phase; migrating SavedView delete to the action-confirmation
  framework is tracked separately. The rule applies forward, not retroactively.
- No single-record MCP tools for sync or delete. Single-record actions on
  channels go through the bulk tools (`bulk_sync_channels`,
  `bulk_delete_channels`) with `ids: [single_id]`. The two-step `confirm` flow
  applies even for one-id calls.

## 9. Forward-looking notes

- The `BulkSync` + `SyncsController` + `Confirmable` concern triple is designed
  as a **foundation**. Future operations will reuse this skeleton:
  - bulk update metadata (title, description, tags)
  - bulk privacy change (public / unlisted / private)
  - bulk add-to-playlist / remove-from-playlist
  - bulk thumbnail update
  - bulk schedule / unschedule
- Each future bulk operation extends `BulkOperation.kind` with a new enum value,
  adds a sibling controller (or a generic `BulkOperationsController` if a third
  operation justifies the abstraction), adds a sibling job
  (`BulkUpdateMetadataJob`, etc.), and reuses the same
  `Turbo::StreamsChannel.broadcast_replace_to "bulk_operation_#{id}"` pattern.
- The MCP two-step `confirm` flow (`{ ids, confirm }` schema with
  preview-then-execute semantics) is the canonical shape for every future bulk
  MCP tool. New bulk tools must follow this shape exactly.
- The pito-sh in-TUI bulk picker + confirmation flow is the canonical UX for
  every future bulk action in the terminal. New bulk actions register a key
  binding (`D`, `Y`, future: `M` for metadata, `P` for privacy, etc.) that opens
  the same preview-then-confirm screen.
- The `pito_dashboard_charts_synced` localStorage key is the first of a likely
  family of per-browser UX preferences. Future preferences (e.g., default
  channel filter, default time range, sidebar collapse state) follow the same
  pattern: a stable string key, JSON value, Stimulus controller managing
  read/write, first-visit initialization to a sensible default. Cross-device
  sync via server-side per-user preferences is a separate future phase.
