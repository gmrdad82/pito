# Architecture

This document captures the runtime topology and the platform decisions Pito
relies on. It is the seed file from Phase 1 / Phase 2; further phases append
rather than rewrite.

## Datastore — Postgres 17 (Phase 2)

Pito's primary relational store is Postgres 17 via the `pgvector/pgvector:pg17`
Docker image. Running on `127.0.0.1` and (in development) listening on host port
`5433` so it never collides with a host-installed Postgres on `5432`.

### Extensions

A single migration (`db/migrate/<TS>_enable_postgres_extensions.rb`) enables
three extensions at the database level:

- `pgcrypto` — `gen_random_uuid()` and other crypto helpers.
- `citext` — case-insensitive text type. Used by `saved_views.url` and by
  `users.username` / `users.email`.
- `vector` — pgvector. Installed but no columns yet. Phase 10 (embeddings) adds
  the first vector column.

### Timezone

The Rails app pins both `config.time_zone = "UTC"` and
`config.active_record.default_timezone = :utc` so Groupdate aggregates render
predictably under Postgres `timestamptz`. Charts use UTC bucket boundaries.

### Connection pool sizing

`config/database.yml` sets `pool` to
`max(RAILS_MAX_THREADS, MCP_THREADS, SIDEKIQ_CONCURRENCY)`. With current
defaults (Web Puma 3 threads, MCP Puma 5 threads, Sidekiq concurrency 5) the
pool resolves to 5. Each Puma process maintains its own pool; Sidekiq has its
own.

### Credentials

Postgres credentials live in Rails encrypted credentials under the `:postgres`
block (`development` and `test` sub-keys). The seed-time tenant/user values live
under the `:owner` block (see `setup.md`).

`.env.development` / `.env.test` carry connection metadata only
(`POSTGRES_HOST`, `POSTGRES_PORT`). Database name, username, and password live
exclusively in Rails encrypted credentials. No secrets in env files.

### json vs jsonb

All JSON columns use `jsonb` (better indexing, faster queries). `t.json` is
forbidden in new migrations.

## Tenant + User schema (Phase 3 — Channel Revamp)

Phase 3 was reframed from "Auth Foundation" to "Channel Revamp". The Auth
surface (Doorkeeper, scoped tokens, login UI, `Api::AuthConcern`, `ApiToken`) is
**deferred** to a later phase. Phase 3 lays only the schema-level primitives:

- `tenants(id, name, timestamps)`. `Tenant` validates `name` presence, length
  3..30. `has_many :users`, `has_many :channels`.
- `users(id, tenant_id, username citext, email citext, password_digest, timestamps)`.
  `username` matches `\A[A-Za-z][A-Za-z0-9]*\z` (must start with a letter,
  alphanumerics only). `username` and `email` are **globally unique**
  (single-column unique B-tree indexes; not scoped to tenant). `User` uses
  `has_secure_password` and exposes `find_by_username_or_email(login)`.
- `Current` (`ActiveSupport::CurrentAttributes`) carries `:tenant`, `:user`,
  `:token`. `ApplicationController` sets `Current.tenant = Tenant.first` /
  `Current.user = User.first` in a `before_action` so the app continues to
  operate single-tenant / single-user.

There is no signup, no login, no session, no token, no UI. Both rows are seeded
from the `:owner` credentials block.

## Channel model (Phase 3 — Channel Revamp)

The Alpha-era `Channel` was rewritten. Surviving columns:

- `id`, `tenant_id` (FK NOT NULL), `channel_url` (string, case-sensitive, unique
  B-tree)
- `star` (bool default false), `connected` (bool default false), `syncing` (bool
  default false)
- `last_synced_at` (timestamp), `created_at`, `updated_at`

Indexes: unique on `channel_url`; secondary on `last_synced_at`, `tenant_id`,
and `(tenant_id, star)`, `(tenant_id, connected)`, `(tenant_id, syncing)`.

Behaviour:

- `belongs_to :tenant`. `has_many :videos`, `:playlists`, `:video_uploads` (all
  dependent: :destroy).
- `channel_url` validation:
  `\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z` — only the
  canonical immutable form.
- URL is **locked after create**: `before_update :prevent_url_change` raises
  `Channel::UrlLockedError` if `channel_url_changed?`.
- Scopes: `starred`, `connected`, `syncing`. (The Alpha `public_only` scope was
  dropped.)
- `Searchable` is **not** included on `Channel`. With no `title`/`description`,
  there is nothing to index. `Channel` is also removed from `ReindexAllJob`'s
  iteration list and from the search engine / search controller.
- All Alpha columns (`title`, `description`, `subscriber_count`, `view_count`,
  `video_count`, `thumbnail_url`, `youtube_channel_id`, `oauth_*`) are gone.

### Sync triggers

- `after_create_commit` enqueues `ChannelSync.perform_async(id)`.
- `after_update_commit` enqueues `ChannelSync` when `saved_change_to_star?` and
  `star?` (toggling star to true).
- The channel show view's `[ sync ]` button routes through `/syncs/channel/:id`,
  which queues `BulkSyncJob` for a single id (bulk-as-foundation pattern).
- `SyncStarredChannelsJob` runs daily at `0 0 * * *` (midnight UTC) via
  sidekiq-cron and enqueues a `ChannelSync` per starred channel.

## ChannelSync placeholder job

`app/jobs/channel_sync.rb` — class name `ChannelSync` (flat, no `Job` suffix).
Sidekiq job on the `default` queue, retry 3.

Lifecycle:

1. `Channel.find_by(id:)` — returns silently if the channel was deleted
   mid-flight.
2. `update!(syncing: true)`.
3. Placeholder no-op body. Real public + OAuth API integration lands in a later
   phase.
4. `ensure` block: if the channel still exists,
   `update(syncing: false, last_synced_at: Time.current)`.

## Bulk operations framework

`BulkOperation` + `BulkOperationItem` carry the abstraction; `BulkDelete` and
`BulkSync` are the two kinds shipping today. The pattern is the **foundation**
for future bulk actions (metadata update, privacy change, playlist add/remove,
etc.).

- `BulkOperation.kind` enum: `update_metadata`, `update_privacy`,
  `add_to_playlist`, `remove_from_playlist`, `bulk_delete`, `bulk_sync` (6
  values).
- `BulkOperationItem.status` enum: `pending`, `succeeded`, `failed`, `skipped`
  (4 values; `skipped` is used by sync for already-syncing rows).

### Action confirmation framework

The Alpha-era `app/views/shared/_action_screen.html.erb` is the canonical UX for
any destructive or significant action. The URLs `/deletions/:type/:ids` and
`/syncs/:type/:ids` **are** the confirmation resources:

- `GET` renders the preview (item rows, skip badges, totals, `[ cancel ]` /
  submit buttons).
- `POST` creates the `BulkOperation`, items, and enqueues the job; renders the
  live progress page.

`:ids` is a comma-separated list — single-record actions are bulk operations
with a one-element list. There are no JS `alert` / `confirm` / `prompt` dialogs
anywhere; the action confirmation page is the canonical replacement.

### Confirmable concern

`app/controllers/concerns/confirmable.rb` extracts the shared logic between
`DeletionsController` and `SyncsController`:

- `load_items` parses `:type` / `:ids`, dispatches per type (`channel` →
  `Channel.where(id:).order(channel_url: :asc)`; `video` → eager-loaded with
  aggregated stats), redirects on unknown type or empty result.
- `cancel_path` returns the index path for the type.
- `model_for(type)` is the type → AR class dispatch helper.
- `action_verb` is overridden by including controllers (`"delete"` / `"sync"`).

### BulkSync flow (mirror of BulkDelete)

`SyncsController#show` renders the preview using `Confirmable#load_items` and a
per-type partition (`@already_syncing` vs `@syncable` for channels; videos
default to all-syncable).

`SyncsController#create` creates `BulkOperation(kind: :bulk_sync)`, creates one
`BulkOperationItem` per id (pre-marked `:skipped` with
`error_message: "already syncing"` for partitioned rows), then enqueues
`BulkSyncJob.perform_in(3.seconds, operation.id)` and renders the progress page
immediately (controller does **not** block on the job).

`BulkSyncJob` (queue: `bulk_sync`):

- Iterates items. Skipped items count toward the progress denominator but
  trigger no broadcast and no work.
- For each non-skipped item, dispatches by convention: calls
  `ChannelSync.perform_async(target.id)` when the target is a `Channel`. (The
  intent is `<TargetType>Sync.constantize.perform_async(target_id)`; only
  `ChannelSync` is wired today.)
- Per-item errors mark the item failed and continue (no fail-fast — a single bad
  item does not abort the rest, in contrast to `BulkDeleteJob`).
- Broadcasts via
  `Turbo::StreamsChannel.broadcast_replace_to("bulk_operation_#{id}", ...)` —
  same pattern as `BulkDeleteJob`. No custom ActionCable channel.

## Sidekiq queues

- `default` — `ChannelSync`, `SyncStarredChannelsJob`.
- `bulk_deletion` — `BulkDeleteJob`.
- `bulk_sync` — `BulkSyncJob`.
- `search` — `ReindexAllJob` (daily reindex). `Channel` is no longer in the
  iteration list.

Concurrency 5 (`config/sidekiq.yml`). Web UI at `/sidekiq` with HTTP basic auth.

## Search — Meilisearch 1.13

Search index lives in Meilisearch (`meilisearch_data` Docker volume). Reindex is
auto-enqueued via the `Searchable` concern on every save/destroy. `Searchable`
is included by `Video` only (Phase 3 dropped `Channel`). The search controller
and the `search` MCP tool only query videos.

## Background jobs — Sidekiq

Backed by Redis (`redis:7` Docker volume `redis_data`). See "Sidekiq queues"
above.

## Process model — dual Puma + worker

`Procfile.dev` declares:

- `web` — Web Puma on port 3000 (3 threads).
- `mcp` — MCP HTTP Puma on port 3001 (5 threads).
- `worker` — Sidekiq.
- `css` — Tailwind watcher.
- `tunnel` — cloudflared tunnel exposing `app.pitomd.com` and `mcp.pitomd.com`.

Both Pumas share `database.yml`; each maintains its own connection pool sized by
the rule above.

## Dashboard chart sync persistence

`app/javascript/controllers/chart_sync_controller.js` (Stimulus) is attached to
the dashboard root. Every chart container has a stable `data-chart-id` slug
(e.g. `daily-views`, `views-by-channel`, `top-videos`, `daily-engagement`).
Sync-capable line charts also carry `data-chart-sync-target="chart"` and a
`[ ] sync` `CheckboxComponent` (design-system bracketed style — never a native
`<input type="checkbox">`) wired as `data-chart-sync-target="checkbox"` with
`data-chart-id="<slug>"` and `data-action="change->chart-sync#toggle"`. Bar
charts (e.g. `top-videos`) are not sync-capable and do not get a `[ ] sync`
checkbox.

State is persisted per-browser in `localStorage["pito_dashboard_charts_synced"]`
as a JSON array of chart-id slugs that are CURRENTLY synced. On first visit (key
absent) the controller writes the full set of sync-capable slugs (default ACTIVE
— every `[ ] sync` starts as `[x]`). On subsequent visits it restores the user's
last toggle state. Applying state means: setting the hidden native `<input>`'s
`checked` (drives the `[ ]` / `[x]` indicator via `.md-check-indicator::before`)
AND setting/removing `data-sync-group="dashboard"` on the chart container (read
by the crosshair plugin in `app/javascript/application.js` to share hover index
across charts in the same group). Toggling `[ ] sync` does NOT hide the chart —
it only opts the chart in or out of the shared crosshair.

## Things explicitly NOT in scope

- **Auth Foundation** — `Api::AuthConcern`, scope catalog, `ApiToken`, login UI,
  Doorkeeper, Google OAuth. Deferred to a later phase. The `Tenant` and `User`
  schema is in place so the future phase does not re-do migrations.
- **Real YouTube sync** — `ChannelSync` is a placeholder; no API calls. Comes
  back when the YouTube OAuth + API foundation phase ships.
- **Multi-tenant request lifecycle** — there is no per-request tenant
  resolution. `Current.tenant` is just `Tenant.first` for now.

Phase 3 in this codebase = Channel Revamp. The original "Phase 3 (auth)" framing
in earlier copies of this document is obsolete.
