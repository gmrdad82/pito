# Architecture

This document captures the runtime topology and the platform decisions pito
relies on. It is the seed file from Phase 1 / Phase 2; further phases append
rather than rewrite.

## Datastore — Postgres 17 (Phase 2)

pito's primary relational store is Postgres 17 via the `pgvector/pgvector:pg17`
Docker image. Running on `127.0.0.1` and (in development) listening on host port
`54327` so it never collides with a host-installed Postgres on `5432` or with
sibling projects on neighbouring ports. The `27` suffix is pito's port marker;
see `docs/setup.md` for the full local port table. Data is persisted in the
`pito-postgres-data` Docker volume.

### Extensions

A single migration (`db/migrate/<TS>_enable_postgres_extensions.rb`) enables
three extensions at the database level:

- `pgcrypto` — `gen_random_uuid()` and other crypto helpers.
- `citext` — case-insensitive text type. Used by `saved_views.url` and by
  `users.email`.
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
block (`development` and `test` sub-keys). The seed-time owner credentials live
under the `:owner` block (`{ email, password }`; see `setup.md`).

`.env.development` / `.env.test` carry connection metadata only
(`POSTGRES_HOST`, `POSTGRES_PORT`). Database name, username, and password live
exclusively in Rails encrypted credentials. No secrets in env files.

### json vs jsonb

All JSON columns use `jsonb` (better indexing, faster queries). `t.json` is
forbidden in new migrations.

## Single-install, multi-user — User + ApiToken schema

pito is a **single-install, multi-user** application (ADR 0003). The whole
database belongs to one install; every authenticated user has install-wide
read/write access. There is no `Tenant` model, no `tenant_id` columns on domain
tables, and no per-user data isolation. Multi-user exists purely as
authentication ergonomics — "more than one person can log in" — not as a
boundary. The 12-rule IDOR specification originally drafted for a multi-tenant
shape is archived as a future-SaaS reference at
`docs/decisions/archives/idor-spec.md`; if pito ever pivots to multi-tenancy at
pito.com, that document is the starting point for re-introducing tenant columns.

`docs/auth.md` is the authoritative reference for the auth model. This section
captures the architectural high level; full request flow, scope-per-tool tables,
and the bootstrap ceremony live in `docs/auth.md`.

### Schema

- `users(id, email citext UNIQUE NOT NULL, password_digest, timestamps)`. Auth-
  only model; no `username`, no `tenant_id`, no `admin`, no role column. Email
  is case-insensitive unique via citext. `has_secure_password`. Login is
  email-and-password (Phase 8).
- `api_tokens(id, user_id, name, token_digest UNIQUE, last_token_preview, scopes jsonb, expires_at, last_used_at, revoked_at, timestamps)`.
  Digest is HMAC-SHA256 with the `:tokens.pepper` credential.
  `last_token_preview` stores the last 4 characters for identification.
  Plaintext is shown once at creation and never re-displayed.

### `Current`

`ActiveSupport::CurrentAttributes` carries `:user`, `:token`, `:session`.

- HTML routes — `Sessions::AuthConcern` resolves the cookie-backed session and
  sets `Current.user` / `Current.session` for the duration of the request.
  Unauthenticated requests redirect to `/login`.
- API / MCP routes — `Api::AuthConcern` (controllers) and `Mcp::RackApp` (the
  MCP Puma's rack app) populate `Current.token` / `Current.user` from the
  resolved bearer token, then reset in an `ensure` block / Rack `after_action`.

There is no `Current.tenant`; the install is the implicit scope.

### `Current.token` flow

For API and MCP requests, `Api::TokenAuthenticator` is the shared engine:
extracts the bearer header, digests + looks up the row, validates
revoked/expired status, populates `Current.token / user`, touches `last_used_at`
via `update_columns`, writes a JSON line to `log/auth_audit.log`. Failures bump
a per-IP rack-attack bucket (10 failures in 5 minutes triggers a 429). See
`docs/auth.md` §5 for the full flow diagram.

## Channel model (Phase 3 — Channel Revamp)

The Alpha-era `Channel` was rewritten. Surviving columns:

- `id`, `channel_url` (string, case-sensitive, unique B-tree)
- `star` (bool default false), `connected` (bool default false), `syncing` (bool
  default false)
- `last_synced_at` (timestamp), `created_at`, `updated_at`

Phase 7 added a foreign key for the YouTube OAuth connection. Phase 9 (per
ADR 0006) renamed it to `youtube_connection_id` (FK to `youtube_connections`,
nullable).

Indexes: unique on `channel_url`; secondary on `last_synced_at` and
`youtube_connection_id`.

Behaviour:

- `has_many :videos`, `:playlists`, `:video_uploads` (all dependent: :destroy).
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

Search index lives in Meilisearch (`pito-meilisearch-data` Docker volume).
Reindex is auto-enqueued via the `Searchable` concern on every save/destroy.
`Searchable` is included by `Video` only (Phase 3 dropped `Channel`). The search
controller and the `search` MCP tool only query videos.

## Background jobs — Sidekiq

Backed by Redis (`redis:7` Docker volume `pito-redis-data`). See "Sidekiq
queues" above.

## Process model — dual Puma + worker

`Procfile.dev` declares:

- `web` — Web Puma on port 3027 (3 threads).
- `mcp` — MCP HTTP Puma on port 3028 (5 threads).
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

## Google OAuth + YouTube API foundation (Phase 7, renamed Phase 9)

Phase 7 introduced the third-party-API limb of pito's auth surface: a delegation
channel from pito to Google, used by the YouTube Data and Analytics APIs. It is
independent of the bearer-token and session surfaces — different flow, different
model, different lifecycle.

Per ADR 0006, sign-in is **local-only** (email + password). Google OAuth is
**channel-only**: the OAuth dance authorizes pito to talk to YouTube on behalf
of the install, never as an identity provider. Phase 9 renamed the Phase 7
`GoogleIdentity` model to `YoutubeConnection` and stripped the dormant
sign-in-with-Google branch from the callback controller; the surviving surface
is documented below in its post-rename shape.

### Auth surface map

pito has three independent inbound auth surfaces and one outbound delegation,
each with its own lifecycle and storage:

- **Browser → Rails (Web Puma)** — cookie + DB-backed sessions. The `sessions`
  table from Phase 6A holds the server-side session record; the cookie carries
  only the session id. Login is email + password (Phase 8).
- **MCP / `pito` CLI → Rails (MCP Puma + API routes)** — bearer `ApiToken`s
  (Phase 3 / Phase 5). Tokens are HMAC-digested at rest, scoped, and
  authenticated by the shared `Api::TokenAuthenticator`.
- **Third-party clients → Rails** — Doorkeeper-issued OAuth 2.0 tokens (Phase
  6B). pito acts as the OAuth provider. Same `Api::AuthConcern` consumes the
  token; the storage and issuance flow differ. Doorkeeper survives the tenant
  drop (ADR 0005) because Claude Mobile's Authorization Code + PKCE flow is
  load-bearing.
- **pito → Google (outbound delegation)** — OAuth 2.0 authorization code flow. A
  `YoutubeConnection` row holds the encrypted access + refresh tokens that let
  pito act against the YouTube APIs on the install's behalf.

These surfaces do not share storage.

### `YoutubeConnection` model

`youtube_connections` belongs to a `User` and stores the materials needed to
delegate against Google's APIs. The model was originally introduced in Phase 7
as `GoogleIdentity`; Phase 9 renamed it (and every reference site) per ADR 0006
because the model's role narrowed to "an OAuth grant that gives pito access to
one or more YouTube channels" — never user identity.

- `access_token`, `refresh_token` — encrypted at rest via Active Record
  Encryption (`encrypts :access_token, :refresh_token`). The Rails master key
  decrypts; the database does not see plaintext.
- `expires_at` — when the access token expires. The client refreshes proactively
  when within a small grace window.
- `needs_reauth` — boolean flag. Set to `true` when Google returns
  `invalid_grant` on a refresh attempt (refresh token revoked, expired in
  Testing-mode TTL, or the user revoked consent at Google's side). The Settings
  UI surfaces a banner; the user clicks `[ reconnect ]` to walk the consent
  screen again.
- `scopes` — `jsonb` array of granted OAuth scopes (e.g.
  `["youtube.readonly", "yt-analytics.readonly"]`).
- Standard timestamps + `user_id`. `google_subject_id` carries a global unique
  index (Google subject IDs are globally unique).

**Cardinality.** `User has_many :youtube_connections, dependent: :destroy` —
destroying a user cascades to their connections. A single user can hold multiple
connections (one per Google account); each connection can cover one or more
channels under that account. The Phase 7-era "one-per-user (UI enforcement)"
framing retired with Phase 9's rename.

**Channel cascade.** `YoutubeConnection has_many :channels` with
`dependent: :nullify` — a channel survives the destruction of its connection
with `youtube_connection_id` reset to `NULL`. This preserves the user's star /
saved-view state for that channel across disconnect / reconnect cycles (see ADR
0006 and the Phase 9 spec).

**Disconnect.** Per decision 7.13, `[ disconnect ]` from the Settings UI runs
`Youtube::DisconnectChannel`, which detaches channels from the connection and
destroys the `YoutubeConnection` row when no channels remain bound to it. The
consent grant is gone; a subsequent reconnect creates a fresh row.

### YouTube client tier

Two thin clients sit above the `google-apis-youtube_v3` and
`google-apis-youtube_analytics_v2` gems. Both pin a single chokepoint for auth,
audit, and quota; nothing in the rest of the codebase calls those gems directly.

- **`Youtube::Client`** — OAuth-authenticated. Accepts a `YoutubeConnection` and
  uses its access token (refreshing transparently when expired). Calls the
  YouTube Data API v3 and the YouTube Analytics API. This is the path for any
  channel or video the user owns — anything that requires reading
  Analytics-level metrics.
- **`Youtube::PublicClient`** — API-key-authenticated. Uses the
  `:google_oauth.api_key` credential. Calls public-only endpoints on the Data
  API. This is the path for tracked-but-not-owned content (Phase 8 — channels
  and videos the user follows but does not own a YouTube account for). Analytics
  is not reachable through the public client.

**Quota chokepoint.** Per decision 7.5, every call routes through the client and
increments a per-connection per-day budget. The client computes the call's
declared cost (see `docs/youtube_quota.md` for the cost table), checks the
remaining daily budget for that connection, and either proceeds or raises
`Youtube::QuotaExhaustedError` (decision 7.6 — fail fast, no retries, no
queueing in this phase).

**Audit row.** Per decision 7.8, every call writes one row to
`youtube_api_calls(user_id, youtube_connection_id, endpoint, quota_cost, outcome, http_status, error_class, created_at)`.
Outcomes are `success`, `quota_exhausted`, `unauthorized`, `not_found`,
`rate_limited`, `other_error`. The audit table is the source of truth for "how
much quota did this connection burn today" and the basis for decision 7.5's
per-connection budget calculation.

**Refresh / `needs_reauth` flow.** When the access token expires, the client
attempts a refresh. On `invalid_grant` (refresh token revoked, expired, or user
removed consent), the client sets `needs_reauth = true` on the connection and
re-raises so the caller can short-circuit. The UI banner picks up the flag on
the next page load.

### Channel / Video schema philosophy (post-Path-A)

pito stores `Channel` and `Video` as **thin YouTube-reference records**, not
local caches of YouTube metadata. The columns are:

- `Channel`: `id`, `url`, `star`, `youtube_connection_id` (FK to
  `youtube_connections`, nullable), `last_synced_at`, timestamps.
- `Video`: `id`, `url`, `star`, `youtube_connection_id` (FK to
  `youtube_connections`, nullable), `last_synced_at`, timestamps.

All previously-stored YouTube metadata columns — title, description,
`subscriber_count`, `view_count`, `video_count`, `thumbnail_url`, `etag`,
`youtube_channel_id`, and the rest — were dropped. pito does **not** cache
YouTube metadata in this phase. Displays that previously rendered a title or
counter render the URL (or a URL-derived placeholder); a follow-up phase decides
which fields, if any, are worth caching locally.

Per ADR 0003 ("Owned vs. tracked framing retired"), the earlier `Path A2`
distinction between **owned** (OAuth-connected) and **tracked** (public-only)
records collapses with the single-install positioning: every `Channel` and
`Video` in pito is an owned record by definition. Sync goes through
`Youtube::Client` against the install's `YoutubeConnection`(s).

### Cloud Console linkage

The click-by-click setup for the Google Cloud project, OAuth consent screen,
test users, and OAuth Web client lives in `docs/setup.md` under "Google Cloud /
OAuth Setup". pito reads its credentials from
`Rails.application.credentials.google_oauth`:

- `:google_oauth.project_id` — Cloud project identifier (informational; used in
  error messages).
- `:google_oauth.client_id` / `:google_oauth.client_secret` — OAuth Web
  Application credentials. Drive the authorization-code flow.
- `:google_oauth.api_key` — API key. Drives `Youtube::PublicClient`.

The same OAuth client serves dev (`127.0.0.1:3027` via the cloudflared tunnel to
`app.pitomd.com`) and prod. See `docs/setup.md` for the rationale and the
multi-environment escape hatch (a second OAuth client in the same project for
staging or CI tunnels).

### Test fixture strategy

Phase 7 specs run against WebMock stubs that mirror canned response shapes — no
live calls in CI, no recorded cassettes yet. Per decision 7.16, VCR cassettes
are deferred to a post-implementation recording session against a real YouTube
account once the OAuth flow has been walked end-to-end at least once. Until
then, the canned shapes are conservative copies of the documented response
shapes from Google's API reference.

When the recording session lands, the WebMock stubs flip to VCR cassettes
without changing the spec assertions — the response shapes are the contract, not
the wire bytes.

## Things explicitly NOT in scope (this phase)

- **Real YouTube sync** — `ChannelSync` is a placeholder; no API calls. The
  Phase 7 foundation (OAuth + `YouTube::Client` + audit + quota tracking) is in
  place; per-record sync jobs that exercise it land in a later phase.
- **Multi-tenant SaaS** — explicitly off the roadmap (ADR 0003). pito is
  positioned as a single-install creator workflow. The IDOR specification
  drafted for a multi-tenant shape is archived at
  `docs/decisions/archives/idor-spec.md` as a future-SaaS reference.
- **User-creation UI / invite flow** — the seed mints a single owner User from
  the `:owner` credentials block; additional users today need a manual row
  insert. A simple invite surface may land in a later phase.
- **Token expiry sweep** — `expires_at` is honored on every authenticate call,
  but no background job marks/deletes expired rows. Future phase.
- **Pepper rotation** — set once at install (§7 of `docs/auth.md`), never
  rotated automatically. Future phase.
