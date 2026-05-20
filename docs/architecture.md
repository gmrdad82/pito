# Architecture

This document captures the runtime topology and the platform decisions pito
relies on. It is the seed file from Phase 1 / Phase 2; further phases append
rather than rewrite.

## ViewComponent-first architecture

pito's UI is structured as a tree of ViewComponents. Every visible HTML
element renders through a ViewComponent — single-use or shared, doesn't
matter. See CLAUDE.md "ViewComponents are kings" for the operational
contract. The bar for inlining is ultra-strict: only structural HTML with
zero classes, zero variants, zero styling.

Every ViewComponent ships with its `_spec.rb`. Specs lock the contract:
render output, kwargs, variants, i18n. No exceptions. See CLAUDE.md
"ViewComponents are kings" → "Every ViewComponent has a spec" for the
operational mandate.

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
  `users.username`.
- `vector` — pgvector. Installed but no columns yet. Phase 10 (embeddings) adds
  the first vector column.

### Timezone

The Rails app pins both `config.time_zone = "UTC"` and
`config.active_record.default_timezone = :utc` so Groupdate aggregates render
predictably under Postgres `timestamptz`. Charts use UTC bucket boundaries at
the storage layer. The full app-wide contract — UTC at rest, user-tz at render,
including the rollup pattern for analytics — lives below under "Timezone
rendering rule (Phase 26 — 01a / 01f)". This subsection covers only the
Postgres-side pinning.

### Connection pool sizing

`config/database.yml` sets `pool` to
`max(RAILS_MAX_THREADS, MCP_THREADS, SIDEKIQ_CONCURRENCY)`. With current
defaults (Web Puma 3 threads, MCP Puma 5 threads, Sidekiq concurrency 5) the
pool resolves to 5. Each Puma process maintains its own pool; Sidekiq has its
own.

### Credentials

Postgres credentials live in Rails encrypted credentials under the `:postgres`
block (`development` and `test` sub-keys). The seed-time owner credentials live
under the `:owner` block (`{ username, password }`; see `setup.md`).

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

- `users(id, username citext UNIQUE NOT NULL, password_digest, totp_secret, totp_enabled, timestamps)`.
  Auth-only model; no `email`, no `tenant_id`, no `admin`, no role column.
  Username is case-insensitive unique via citext. `has_secure_password`. Login
  is **username + password + mandatory TOTP**, browser-only gate (Phase 29 Unit
  A2). The TOTP factor is required for every browser sign-in; bearer-token
  surfaces (API + MCP) keep their own auth path and do not touch the TOTP gate.
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

### Games omnisearch (`/games`)

The `/games` omnisearch modal is a two-tier dispatch with two record-type
sections rendered top-to-bottom: **local** (games + bundles from the install's
own Postgres / Meilisearch corpus) above **IGDB** (remote `search_games` hits
from the IGDB v4 API). The dispatcher is `Games::SearchService` and the local
half is `Meilisearch::SearchGames`; both ship in Phase 27 alongside the
`/games` revamp.

**Always-search-both contract (2026-05-19).** `Games::SearchService` calls
both layers on every dispatch — local first, IGDB second — regardless of
local hit count. The earlier "lazy IGDB" mode (skip the IGDB call when the
local pane already had hits) was reversed because the user needs to compare
local rows against the IGDB-canonical row for the same query: the local row
may be a slightly different edition, a stale title, or a community-renamed
import, and the IGDB row is the canonical reference. With both halves always
present, the dedup post-filter (below) is what keeps the IGDB pane from
re-listing rows the user already imported.

**Dedup by `igdb_id`.** After both halves return, the dispatcher filters out
any IGDB row whose `id` matches an `igdb_id` on a local Game in the local
half of the same response. The local row wins — the user sees the game in
exactly ONE section, never twice. This rule is what makes the
always-search-both contract feel coherent rather than noisy: when the local
import IS the IGDB row, only the local entry renders; when it isn't (no
local match, or local match has a different `igdb_id`), both entries render
side-by-side and the user can compare.

**Local-corpus shape.** `Meilisearch::SearchGames` queries the shared
`games_<env>` Meilisearch index, which holds both Game documents (written by
`Meilisearch::GameIndexer`) and Bundle documents (written by
`Meilisearch::BundleIndexer`) discriminated by a `kind` field (`"game"` vs
`"bundle"`). The same call always falls back to a Postgres ILIKE merge on
top of the Meilisearch ranking — the fallback guarantees obvious substring
matches surface even when the index is stale or partially populated, while
Meilisearch's relevance ordering wins for the leading entries.

**Alt-names search axis (2026-05-19).** `games.alternative_names` is a
Postgres `text[]` column populated from IGDB's `alternative_names` payload
on every sync (the IGDB API returns an array of `{id, name, comment}` rows;
`Igdb::GameMapper.extract_alternative_names` keeps the `name` strings,
deduplicated, blanks dropped). Three consumers read the column:

1. `Meilisearch::GameIndexer::SEARCHABLE_ATTRIBUTES` includes
   `alternative_names` immediately after `title` in the searchable list.
   Meilisearch weights the earlier entries higher — alt names rank above
   `summary` / developer / publisher / genre text bodies because alt names
   are effectively title synonyms ("SF6" for Street Fighter 6, "FF7
   Rebirth" for the canonical title, "TotK" for Tears of the Kingdom).
2. The Postgres ILIKE fallback in `Meilisearch::SearchGames#fallback_games`
   OR-matches `alternative_names` alongside `title` and `igdb_slug` via
   `EXISTS (SELECT 1 FROM unnest(alternative_names) AS alt WHERE LOWER(alt)
   ILIKE ?)`. A GIN index on the column (`index_games_on_alternative_names`)
   keeps the lookup cheap when the planner picks it up.
3. `Games::VoyageIndexer#combined_text` (and its mirror in
   `BulkVoyageIndexJob#game_text`) joins the alt names between the title
   and the summary when composing the Voyage embedding input —
   `"title — alt_names — summary"` (alt slot dropped when the array is
   empty; entries space-joined inside the slot). Alt names are short
   tokens, not prose, so the slot is a thin synonym hint that nudges the
   1024-dim vector toward neighboring titles in the series / locale /
   marketing-alias cluster. Two consumers of `summary_embedding` benefit
   from this signal: the `/games/:id` similar-games pgvector lookup, and
   the recommended-bundles ranking on the same page.

The column carries `default: [], null: false` — the empty-array invariant
makes the `EXISTS unnest` predicate safe to run unconditionally, and a
previously-populated row whose alt names were removed upstream stays in
sync (when IGDB omits the field on resync, the mapper resets to `[]`).

**Modes.** `Games::SearchService` exposes three modes:

- `:game_index` — IGDB-only. The "add from IGDB" flow on `/games`. Local
  half is empty; dedup is a no-op.
- `:bundle_add` — local games + IGDB. Used by the bundle edit form to
  surface candidate games. Already-in-bundle games are filtered out of the
  local half so a member never re-surfaces as an add candidate.
- `:games_search` — local games + local bundles + IGDB. The headline
  `/games` omnisearch surface. Result rows navigate to `/games/:id` or open
  the bundles modal on `/games`.

IGDB failures (network / auth / rate-limit) surface as a per-pane
`igdb_error` envelope. The local pane stays usable independent of IGDB
health; the IGDB pane renders the upstream-unavailable message in place of
the hit list.

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

Per ADR 0006, sign-in is **local-only** (username + password + mandatory TOTP,
browser-only gate — see "Single-install, multi-user — User + ApiToken schema"
above). Google OAuth is **channel-only**: the OAuth dance authorizes pito to
talk to YouTube on behalf of the install, never as an identity provider. Phase 9
renamed the Phase 7 `GoogleIdentity` model to `YoutubeConnection` and stripped
the dormant sign-in-with-Google branch from the callback controller; the
surviving surface is documented below in its post-rename shape.

### Auth surface map

pito has three independent inbound auth surfaces and one outbound delegation,
each with its own lifecycle and storage:

- **Browser → Rails (Web Puma)** — cookie + DB-backed sessions. The `sessions`
  table from Phase 6A holds the server-side session record; the cookie carries
  only the session id. Login is username + password + mandatory TOTP (Phase 29
  Unit A2); the TOTP gate is browser-only.
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

## Timezone rendering rule (Phase 26 — 01a / 01f)

pito stores every time value in UTC and renders every user-facing time value in
the authenticated user's timezone. This is the app-wide contract. There are no
exceptions and there is no per-surface override. Source-of-truth Mobile note:
`docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md` (§2
"User timezone support"). Foundation sub-spec: 01a. Architecture sub-spec: 01f.

### Storage rule (UTC at rest)

Every `time` / `datetime` / `timestamp` / `timestamptz` column in the schema is
UTC. The Rails app pins `config.time_zone = "UTC"` and
`config.active_record.default_timezone = :utc` (see "Datastore — Postgres 17"
above), so Active Record reads + writes UTC regardless of the request-time
`Time.zone`. Concretely this includes — but is not limited to — `created_at`,
`updated_at`, `last_synced_at` (channels + videos), the Phase 26 columns
`users.time_zone` carries (the IANA name itself is timezone-free),
`last_digest_run_at` (01e), every `*_at` column 01g / 01h add
(`video_viewer_time_buckets.last_synced_at`, scheduled-publish columns), and
every audit column on `youtube_api_calls`. Migrations adding a new time column
default to `t.datetime` (Rails maps to `timestamptz` in Postgres) and skip any
ad-hoc tz arithmetic at write time.

### Render rule (user-tz at the boundary)

Every user-facing time value passes through `l_user_tz` (the helper from 01a) on
the Rails side, or its CLI / MCP equivalent at those boundaries. The render
layer is the sole conversion site. `ApplicationController` sets
`Time.zone = Current.user&.time_zone || "Etc/UTC"` per request so any
`I18n.l(time)` / `time.in_time_zone` call downstream resolves to the user's zone
automatically; `l_user_tz` is the canonical entry point because it is nil-safe
and unifies the format conventions. Views, mailers, Slack / Discord webhook
bodies (01b / 01c), the daily digest email (01e), and the viewer-time heatmap
axis labels (01g) all use the helper.

### Calendar definitions

Analytics queries and the calendar surface (Phase 16+) interpret calendar units
in the user's local zone, never UTC.

- **Day** — `00:00:00` to `23:59:59.999999` in the user's tz. A row stamped
  `2026-05-09T22:30:00Z` belongs to **May 10** for a `Europe/Bucharest` user
  (UTC+3 in summer) and to **May 9** for an `America/Los_Angeles` user (UTC−7).
  The rollup converts at query time; the stored value is unchanged.
- **Week** — Monday 00:00 through Sunday 23:59:59.999999 in the user's tz.
  Monday-start is the v1 default; a future `users.week_start` preference is the
  documented hook for Sunday-start (and other) configurations. Out of scope for
  Phase 26.
- **Month / year** — calendar month and calendar year in the user's tz. Used by
  the calendar surface and by analytics drill-downs.

### Rollup query pattern

Analytics rollup queries apply the tz offset at `GROUP BY` time via Postgres'
`AT TIME ZONE` operator. The canonical pattern, parameterized by the user's IANA
zone:

```sql
SELECT
  date_trunc('day', utc_ts AT TIME ZONE :user_tz) AS local_day,
  COUNT(*) AS n
FROM events
GROUP BY local_day
ORDER BY local_day;
```

The same shape covers `hour`, `week`, `month`, and `year` via the matching
`date_trunc` precision. Hour-of-day / day-of-week rollups for the viewer-time
heatmap use `extract(hour FROM utc_ts AT TIME ZONE :user_tz)` and
`extract(dow FROM utc_ts AT TIME ZONE :user_tz)` — see "Viewer-time aggregation"
below for the exact query.

### Edge cases

The tz layer must absorb the calendar quirks without per-call adjustments:

- **DST spring-forward** — one local day has 23 hours; the rollup naturally
  reports a missing hour bucket for that day. No correction needed.
- **DST fall-back** — one local day has 25 hours; two UTC hours map to the same
  local-hour bucket, summed by `GROUP BY`. No correction needed.
- **Half-hour offsets** — `Asia/Kolkata` is UTC+5:30. `date_trunc('hour', …)` on
  the converted timestamp returns half-hour-shifted hour boundaries; the rollup
  honours them.
- **Quarter-hour offsets** — `Asia/Kathmandu` (UTC+5:45) and `Pacific/Chatham`
  (UTC+12:45 / +13:45 with DST). Same rule: `date_trunc` operates on the
  converted timestamp; the hour boundary is the user-local one.
- **`Etc/UTC` users** — the sentinel default. No conversion is observed at
  render but the helper still routes through `Time.zone`, so the contract
  applies uniformly.

### Cross-references

01a is the Rails-side foundation (`time_zone` column on `users`, browser-detect
Stimulus controller, Settings dropdown, `l_user_tz` helper, per-request
`Time.zone` wiring). 01e (daily digest scheduler) reads the user's zone to fire
the digest at the user's local "morning". 01g (viewer-time analytics) implements
the rollup pattern documented below. 01h (video scheduled publish) renders
scheduled-publish datetimes in the user's zone and validates user-side inputs
against it.

## Viewer-time aggregation (Phase 26 — 01g)

The "best time to publish" analytics surface — a day-of-week × hour-of-day
heatmap per video and per channel — is the first surface to commit to the
UTC-storage / user-tz-rollup contract end-to-end. This section pins the schema,
refresh cadence, and query patterns; the implementation lives in 01g.
Source-of-truth Mobile note: §3 "Viewer-time analytics" of
`docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md`.
Realignment context: `docs/realignment-2026-05-09.md` (YouTube Analytics work
unit 6).

### Source endpoint

The raw data comes from the YouTube Analytics API v2 via the existing
`Youtube::Client` chokepoint (Phase 7). v1 assumes hourly buckets per video per
day are available — the Mobile note flags "verify exact granularity"; the 01g
implementation confirms against the API docs during dispatch. If the API only
exposes daily buckets, the fallback is to approximate hourly distribution via
the traffic-source hourly slice (or a related endpoint) and document the
approximation in the rendered heatmap's empty-state copy. Quota cost rolls into
the per-connection daily budget on `youtube_api_calls` (decision 7.5).

### Storage schema (`video_viewer_time_buckets`)

```
video_viewer_time_buckets
  id                  bigint  PK
  video_id            bigint  FK -> videos.id  NOT NULL
  hour_of_day_utc     int     NOT NULL  CHECK (0..23)
  day_of_week_utc     int     NOT NULL  CHECK (0..6)   -- Postgres extract(dow), Sunday=0
  view_count          int     NOT NULL  DEFAULT 0
  watch_time_seconds  bigint  NOT NULL  DEFAULT 0
  last_synced_at      datetime
  created_at          datetime NOT NULL
  updated_at          datetime NOT NULL

  UNIQUE INDEX (video_id, day_of_week_utc, hour_of_day_utc)
  INDEX        (last_synced_at)
```

The `_utc` suffix on the two bucket columns is load-bearing: the row stores the
UTC bucket the API returned, never the user-local one. **The rollup applies the
tz offset at query time; never at write time.** This keeps a single source of
truth for every user — change a user's `time_zone` and every heatmap re-renders
without a re-sync.

### Refresh cadence

- **Daily refresh.** `ViewerTimeDailyRefreshJob` runs at `0 3 * * *` (03:00
  server time) via sidekiq-cron. The job fans out to one
  `VideoViewerTimeSyncJob.perform_later(video_id)` per owned video. Each
  per-video job calls the YouTube Analytics endpoint, upserts the 7 × 24
  buckets, stamps `last_synced_at`, and bumps `view_count` /
  `watch_time_seconds` atomically. Re-runs are idempotent.
- **Backfill.** One-shot rake task `pito:backfill_viewer_time_buckets` accepts a
  `DAYS=90` argument and enqueues per-video sync jobs over a rolling window
  (default 90 days). Rerunable. Used for first-time setup or after a long
  outage.
- **Quota.** Per-call quota cost flows through the Phase 7 chokepoint and is
  audited in `youtube_api_calls`. On `Youtube::QuotaExhaustedError` the daily
  refresh aborts cleanly and surfaces a Phase 16 notification (decision 7.6 —
  fail fast, no retries).
- **Cadence is locked at daily for v1.** A higher-frequency refresh (hourly, or
  on-demand) is a follow-up once Phase 7 quota tracking surfaces real numbers.

### Query patterns

The `Analytics::ViewerTimeRollup` service is the single read site. All queries
roll up via the user's tz offset.

1. **Per-video heatmap.**

   ```sql
   SELECT
     extract(dow  FROM (
       make_timestamp(2000, 1, 2 + day_of_week_utc, hour_of_day_utc, 0, 0)
       AT TIME ZONE 'UTC' AT TIME ZONE :user_tz
     )) AS dow,
     extract(hour FROM (
       make_timestamp(2000, 1, 2 + day_of_week_utc, hour_of_day_utc, 0, 0)
       AT TIME ZONE 'UTC' AT TIME ZONE :user_tz
     )) AS hod,
     SUM(view_count)         AS view_count,
     SUM(watch_time_seconds) AS watch_time_seconds
   FROM video_viewer_time_buckets
   WHERE video_id = :video_id
   GROUP BY 1, 2;
   ```

   The `make_timestamp` anchor uses an arbitrary Sunday (Jan 2 2000) so the
   `dow` extract honours the day-of-week → hour-of-day shape without smearing
   real calendar dates into the answer. The implementation may swap in a simpler
   offset-arithmetic form provided the result is equivalent for every IANA zone,
   including half- and quarter-hour offsets.

2. **Per-channel heatmap.** Joins through `videos`:

   ```sql
   SELECT … FROM video_viewer_time_buckets b
   JOIN videos v ON v.id = b.video_id
   WHERE v.channel_id = :channel_id
   GROUP BY 1, 2;
   ```

   Aggregation is a straight `SUM` across all the channel's videos. v1 does not
   normalize by per-video age or view-count; raw sums are the simplest
   interpretive surface. Documented as an open question for follow-up.

3. **Rolling window (7d / 28d / 90d).** Filtered by `last_synced_at`:

   ```sql
   WHERE last_synced_at >= NOW() - INTERVAL ':n days'
   ```

   The exact filter shape depends on whether the API returns true rolling
   windows or fixed lookbacks — 01g verifies during dispatch and adjusts the SQL
   pattern accordingly.

### Render contract

The heatmap ViewComponent (`ViewerTimeHeatmapComponent`) receives the rollup
data and the user's `time_zone`. Axis labels (Mon/Tue/.../Sun, 00/01/.../23) are
rendered via `l_user_tz` / the helper layer so the surface re-renders on a tz
change without re-querying. Colour is a single-hue intensity gradient; red
(`#cc0000`) is forbidden by the design system. Empty state copy explicitly
references the daily 03:00 refresh cadence so the user knows when fresh data
will arrive.

### Locked decisions (for future readers)

These were locked in the Phase 26 plan and 01f spec. Future agents should not
re-litigate without an ADR:

- Storage is UTC; rollup is user-tz; the heatmap re-renders on a tz change
  without a re-sync.
- Refresh cadence is daily at 03:00 server time. Locked for v1.
- Week starts Monday. Configurable later via `users.week_start`. Locked for v1.
- Per-channel aggregation is a raw `SUM` across videos. No normalisation. v1.
- MCP and CLI surfaces for viewer-time analytics are deferred to a later phase.
  Web is the only surface in v1.

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
