# Realignment — 2026-05-09

> **Status:** direction map written by architect-spec on 2026-05-09 from a
> 2-hour Claude Mobile session and a follow-up direction conversation with the
> user. **This is not a feature spec.** It is the top-level routing document for
> every existing phase, every parked pre-spec, and every new scope introduced by
> the Mobile notes. Each named upcoming spec gets its own architect dispatch
> later.

## Brief context

On 2026-05-09 the user dropped eight notes into `docs/notes/` during a 2-hour
Claude Mobile session. The notes are a reference build-up across four domains:
Video model + Data API v3 surface; Channel + video Analytics API v2 surface;
Game model + IGDB / Twitch surface; tenant scope + IDOR; calendar +
notifications; ONCE-style distribution research; and a closing supersession note
that drops the tenant model entirely. The notes are intact in `docs/notes/` —
they are the durable trail of how thinking shifted.

A follow-up direction conversation between the user and the master agent locked
the meta-decisions: drop tenants (ADR 0003), collapse MCP scopes to `dev` +
`app` (ADR 0004), keep Doorkeeper for Claude Mobile (ADR 0005), make YouTube
management the core driver, treat the pre-publish checklist as a manual reminder
rather than enforcement, model games like Steam shelves, build the calendar /
notifications surface with Discord + Slack webhook delivery, and ship
distribution local-first now with a possible Hetzner pivot in ~6 months.
Pre-specs 08 / 09 / 10 from Phase 7.5 (Timelines, MCP sync, Terminal sync) are
reconsidered against the new direction in this doc.

This document is the at-a-glance state of every spec, every phase, and every
surface in the repo, plus an ordered roadmap of work units to dispatch as the
realignment is implemented. Phase numbering is intentionally NOT introduced here
— the user wants thematic grouping and will revisit phase numbers in a separate
decision later.

## Categorized state of every spec / phase / surface

### Keep as-is

Items unaffected by the realignment. Brief rationale per item.

- **Phase 2 — Postgres / Redis / Meilisearch / extensions / process model.**
  Datastore choices, port assignments, Docker volumes are all sound. No changes.
- **Phase 3 / 5 ApiToken bearer-token surface.** `ApiToken` model, HMAC-SHA256
  digest, `:tokens.pepper` credential, `last_token_preview`, `last_used_at`,
  `revoked_at`, `expires_at` all stay. Only the `tenant_id` column on the table
  goes away (per ADR 0003). The auth flow, the seed dev token ceremony, the
  rate-limit audit, the rack-attack throttle all stay.
- **Phase 5 `Api::AuthConcern` + `Mcp::ToolAuth.require_scope!`.** The
  controller mixin and MCP scope-check helper API are unchanged. Only the scope
  strings they consume change (per ADR 0004).
- **Phase 6A sessions + login UI.** Session cookies, DB-backed sessions
  (`sessions` table), the login form, password reset, "remember me", the
  rate-limit on failed logins, `/settings/sessions` revocation UI. Only
  `tenant_id` column on `sessions` goes away.
- **Phase 6B Doorkeeper / OAuth-application surface.** Survives the tenant drop.
  See ADR 0005 for the rationale. Drops `tenant_id` columns; otherwise
  unchanged.
- \*\*Phase 7 `GoogleIdentity` model + `Youtube::Client` +
  `Youtube::PublicClient`
  - `youtube_api_calls` audit.\*\* Encrypted access / refresh token storage,
    OAuth authorization-code flow, quota tracking via `youtube_api_calls`,
    `needs_reauth` banner — all sound design and stays. Drops `tenant_id`
    columns from `google_identities` and `youtube_api_calls`.
- **Phase 7.5 keyboard shortcuts spec (04).** `?` modal + key bindings mirroring
  the `pito` CLI schema. Independent of tenant model. Lands as written.
- **Phase 7.5 footage thumbnails experiment spec (06).** Rails + CLI rendering.
  Already partially shipped. Independent of realignment.
- **Phase 7.5 `pito-assets` Docker volume spec (05).** Volume + env var.
  Independent of realignment.
- **Phase 7.5 hygiene sweeps (specs 01 + 02).** Already shipped.
- **Phase 7.5 spec 03 — decorator slim resolution.** Already shipped (kept
  decorators as-is).
- **Phase 4 Project / Footage / Note / SavedView / Collection.** The project
  workspace data model and UI are sound. Drop `tenant_id` from each table;
  otherwise unchanged. Footage thumbnails, note editor, project panes, footage
  importer all stay.
- **Action confirmation framework.** `_action_screen.html.erb`,
  `DeletionsController`, `SyncsController`, `Confirmable` concern,
  `ConfirmModalComponent`, the bulk-as-foundation URL pattern
  `/<action>s/:type/:ids` — all stay. Independent of tenant model.
- **MCP transport architecture.** stdio (`bin/mcp`) + HTTP (`bin/mcp-web`) on
  port 3028 + Cloudflare Tunnel to `mcp.pitomd.com`. The dual-Puma process
  model. The MCP rack app's auth-then-delegate pattern. All stay.
- **Dev KB MCP surface (`list_docs`, `read_doc`, `save_note`).** Mobile capture
  flow stays exactly as designed. The capture loop is the substrate the Mobile
  session that produced these notes used. Survives untouched. The `dev` scope
  (post-ADR 0004) gates the three tools; `dev` is stripped on release packaging.
- **Voyage AI per-target flags + Meilisearch indexing.** Phase 4's Voyage setup
  and the deferred Meilisearch parity follow-up stay. Search isn't affected by
  the realignment beyond losing `tenant_id` filters.
- **Bulk operations framework.** `BulkOperation`, `BulkOperationItem`,
  `BulkDeleteJob`, `BulkSyncJob`, the Turbo Streams broadcast pattern. All stay.
  Drop the `tenant_id` columns; otherwise unchanged.
- **Sidekiq queues + sidekiq-cron + `SyncStarredChannelsJob`.** All stay.
- **Visual style / design system.** Bracketed link convention, monospace font,
  13px base, color tokens, charts no-animation no-red. All stay.
- **Hard rules.** No JS `alert` / `confirm` / `prompt`; bulk-as-foundation URL
  pattern; yes / no for external booleans; secrets in
  `Rails.application.credentials`. All stay. (The "yes / no for external
  booleans" rule applies cleanly to the new surfaces — calendar / game /
  notification tools.)

### Modify

Items that survive but need rework. Per item: what changes.

- **Channel schema.** Today's surviving columns are
  `id, url, star, oauth_identity_id, last_synced_at, timestamps` (post-Path-A2 +
  post-tenant-drop the `tenant_id` is gone). The Mobile notes signal a
  substantial expansion is coming for the post-Phase-7 YouTube management work.
  Note 1 (Video) doesn't expand `Channel` directly, but the YouTube management
  surface on top of Phase 7 wants channel metadata back: title, description,
  subscriber_count, view_count, video_count, thumbnail_url, banner_url,
  watermark_url, country, made-for- kids effective state, plus a canonical
  `youtube_channel_id` separate from `url`. **Path A2's "thin reference" stance
  is reversed for owned channels once sync ships.** A new spec ("Channel data
  sync + edit surface") covers schema expansion + edit forms + sync trigger +
  banner / avatar / watermark previews.
- **Video schema.** Today:
  `id, url, star, oauth_identity_id, last_synced_at, timestamps`. Note 1 calls
  for the full Data API v3 modeled set: `youtube_video_id` (PK from YouTube's
  side); `title`, `description`, `tags[]` (jsonb), `category_id`;
  `thumbnail_url` (one tier — usually `maxres` falling back to `high`);
  `privacy_status`, `publish_at` (nullable); `self_declared_made_for_kids`,
  `contains_synthetic_media`; `made_for_kids_effective` (read-only mirror);
  `etag`; `last_synced_at`. Plus a join:
  `playlist_videos(video_id, playlist_id, position)`. Plus edit forms for the
  writable subset, plus a pre-publish checklist modal (note 2 adds end screen to
  the original three: game, age, paid promotion, end screen). **Reverses Path A2
  retraction for these fields.** A new spec ("Video schema expansion + edit
  surface + pre-publish checklist") covers it.
- **Game schema.** Today: minimal — Phase 4 introduced `Game` as a project-
  workspace concept with cover art (Active Storage). Note 4 expands to a full
  IGDB-backed model with bundles, composite covers via libvips, and Steam-shelf
  listing UX. New columns per note 4's "suggested local schema" table; new
  `bundle` + `bundle_member` tables; new `video_game_link` join table for
  analytics attribution. New spec ("Game model expansion + IGDB sync + bundles +
  composite covers") covers it.
- **MCP scopes.** 9 scopes → 2 (`dev` + `app`). Per ADR 0004. Catalog rewrites
  in `app/lib/scopes.rb`; every `require_scope!` callsite updates;
  `docs/auth.md` §2 + `docs/mcp.md` scope-per-tool table rewrites; new surfaces
  (calendar / notification / game / IGDB tools per notes 4 + 6) all use `app`.
  Token migration is a TBD open question (see below).
- **Search subsystem (Meilisearch + future Voyage embeddings).** Currently
  stubbed for Channel (no `title`/`description` to index). Note 3 (analytics)
  doesn't depend on search. Note 6 (calendar / notifications) doesn't reference
  it. **Recommend: keep stubbed, re-evaluate after Channel + Video schema
  expansion lands.** Once `Channel#title / description` and
  `Video#title / description / tags` are real columns, Meilisearch indexing for
  those tables becomes worth ringing up. Hold off on the per-target flag work
  until then.
- **Phase 4 `Game` Active Storage cover art.** Active Storage stays for ad-hoc
  local cover art, but note 4's `cover_image_id` (IGDB-sourced URL, built at
  render time, not stored) becomes the primary path once IGDB sync lands. Active
  Storage may degrade to "manual override only." Implementation spec resolves
  the boundary.
- **`docs/architecture.md`.** Rewrite the "Tenant + User + ApiToken" and
  "BelongsToTenant" sections to remove tenant scoping. Add a "Single- install,
  multi-user" section pointing at ADR 0003.
- **`docs/auth.md`.** §2 (scope catalog), §3 (tool scope map), §5
  (`belongs_to_tenant`), §10 (departures from Phase 3 plan). Multiple rewrites
  driven by ADRs 0003 + 0004.
- **`docs/mcp.md`.** Scope-per-tool table rewrites. Add catalog entries for new
  tools (calendar / notifications / games / IGDB) once their specs land — but
  stays declarative, the new tools' MCP-tool spec drives the table additions.

### Drop

Items that become irrelevant.

- **The 12-rule IDOR specification (note 5).** Archived as v2-SaaS reference per
  ADR 0003. Stays in `docs/notes/` (or moves to `docs/decisions/archives/` at
  the docs agent's discretion).
- **`BelongsToTenant` concern + `app/models/concerns/belongs_to_tenant.rb`.**
  Removed.
- **`tenant_id` column on every domain table.** Schema migration drops them all.
  Same migration drops the indexes (`tenant_id` single, `(tenant_id, *)`
  composites, `(tenant_id, foreign_key)` joins).
- **`tenants` table + `Tenant` model.** Dropped. (Or downgraded to a single-row
  `AppInstall` table — TBD per the implementation spec, see open questions
  below.)
- **`Current.tenant` from `ActiveSupport::CurrentAttributes`.** Removed.
- **IDOR cross-tenant test obligations.** The cross-tenant leak spec retires;
  per-endpoint IDOR fixtures retire. Auth-required tests stay.
- **Tenant-namespaced storage paths.** Composite covers, exports, thumbnails,
  footage paths shed `tenant-{id}/` prefix. One-time rename script.
- **`yt:destructive` scope.** Folds into `app` per ADR 0004. The destructive
  operations (delete_records, sync_records) gate on `app` like every other write
  tool.
- **Per-tenant credentials (every secret in `Rails.application.credentials`
  thinking of itself as scoped per-tenant).** Collapses to install credentials.
  One Voyage AI key, one IGDB / Twitch credential set, one Cloudflare token, one
  Discord webhook list, one Slack webhook list, one YouTube OAuth client.
- **Phase 6C tenant-leak audit.** Most of the work becomes moot once the tenant
  column is gone. The auth-required-on-every-endpoint property is preserved as a
  separate concern. Drop the cross-tenant assertions.

### Pending — clarified by Mobile notes

Substantial new scope confirmed by user. Each gets its own implementation spec
downstream of this realignment.

- **Channel + Video sync + edit surface.** Per notes 1 + 4. Reverse Path A2
  retraction for owned channels and videos; bring back the metadata columns the
  YouTube management workflow needs. Edit forms expose the writable subset (note
  1's table with the ✅ Write column). Sync triggers and read-modify-write
  semantics for the destructive PUT-per-part API shape. Owned content only —
  public-content sync (Phase 8 territory) stays separate.
- **Pre-publish checklist UI.** Per note 1 + note 2's addendum. Four-item modal
  (game / age / paid promotion / end screen) shown before flipping
  `privacyStatus` to `public` / `unlisted` or scheduling via `publishAt`. Studio
  deep-links per item. Manual reminder, not enforcement (the user ticks each;
  pito doesn't validate).
- **YouTube Analytics tables + dashboards.** Per note 3, the full set:
  `channel_daily`, `video_daily`, `video_daily_by_<slice>` (country, device, OS,
  traffic source, subscribed status, age × gender), `channel_window_summary`,
  `video_window_summary`, `top_videos_window`, `video_retention`. Plus the
  windowed-summary write paths (C1-C5, V1-V9). Plus retention-curve weekly
  refresh. Plus cross-video locals (when-to-publish, best-duration,
  topics-that-work, thumbnail-decay) computed by joining locally — not
  Analytics-API-sourced. Monetization stays schema-ready, sync-disabled.
  Dashboard renders Studio-faithful ratios via the windowed-summary tables (do
  not derive from `video_daily` SUMs).
- **Game model expansion + IGDB sync.** Per note 4. IGDB v4 + Twitch OAuth
  client-credentials + Apicalypse query language + on-demand sync +
  last-write-wins (re-sync overrides local IGDB-field edits). Local-only fields
  (`platform_owned`, `played_at`, `notes`, `hours_of_footage_manual`) survive
  re-sync. Bundles (`series` / `collection` / `genre` / `custom`) with composite
  cover art generation via libvips (per Active Storage variant pipeline). Five
  layouts (2 / 3 / 4 / 5-9 / 10+). Steam-shelf listing UI for games and bundles.
- **Calendar surface.** Per note 6. `calendar_entry` table with derived / manual
  / auto sources, eight `entry_type` values, type-specific metadata jsonb,
  `release_precision`, `manual_date_override`. `purchase_planned` entries linked
  to `game_release` entries with quick-pick storefronts and notify-anyway flag.
  Manual milestones. Auto-tracked milestones via `milestone_rule` table with
  idempotent firing semantics. Calendar views (day / week / month /
  upcoming-game-releases / upcoming-without-purchase / recent-milestones /
  stream-of-occurred-milestones).
- **Notification surface + delivery channels.** Per note 6. `notification` rows
  as first-class. `delivery_channel` rows with kind / config / immediate-kinds
  list / digest-enabled / digest-at-local-time. Formatter component rendering
  Discord embeds / Slack blocks / MCP payloads / in-app JSON. Per-channel
  routing (default `urgent` immediate on webhooks, all kinds in-app).
  Game-release reminder logic with T-30 / T-7 / T-1 / T-0 offsets, suppression
  on `purchase_planned` link, severity escalation.
- **Single-binary distribution + ONCE-style installer (deferred ~6 months).**
  Per note 7's research. Option 1 from that note: keep pito as a CLI/TUI app,
  add a one-line bash installer + `pito setup` TUI wizard + `pito update`
  self-update. Distribution channel via GitHub Releases or self-hosted endpoint.
  Don't compete with ONCE the platform; mirror the feel without the architecture
  change. Option 2 (split into daemon + client) parked as a follow-up if
  architectural pressure justifies it later.
- **Future install wizard.** Per note 8 part 2. Resumable, self-validating,
  one-screen-per-service end-user wizard for non-developer setup (admin user,
  YouTube OAuth, IGDB/Twitch app, Voyage AI, Discord webhook, Slack webhook,
  Cloudflare DNS / `cloudflared` tunnel). Deferred — captured in note 8 and
  referenced from this realignment doc as "future hook." No spec dispatched in
  the current realignment cycle.

### Resolved — Phase 7.5 pre-specs 08 / 09 / 10 (2026-05-10)

The user resolved the three Phase 7.5 pre-spec questions on 2026-05-10. The
recommendations below are pinned in the **Resolved ambiguities** section near
the bottom of this doc. Sections #### Spec 08 / 09 / 10 below remain as the
historical analysis that shaped the recommendations; the user's calls override
them.

### (Historical) — original architect recommendations on Phase 7.5 pre-specs 08 / 09 / 10

#### Spec 08 — Timelines resurrection (pre-spec)

Today's state. Phase 4 created the `timelines` table + state machine
(`editing → exported → uploaded`) and a bare model. Phase 7's Path A2 retract
removed the placeholder title-write so the state machine is metadata-thin. Phase
7.5 parked the resurrection question pending user input.

How the realignment shifts the question. The Mobile notes do NOT mention
Timelines. Note 1 (Video) reaches into pre-publish workflow (the checklist
modal) but doesn't extend into the rendered-video / NLE-export side. Note 6
(Calendar) introduces `video_scheduled` and `video_published` calendar entries
that DO touch the publish-side workflow but bypass the Timeline lifecycle
entirely (a publish event is sync-derived, not Timeline-export-derived).

**Architect's recommendation: defer.** The Timeline lifecycle's headline value
(linkage from a rendered NLE export to a published YouTube video) needs the
Video metadata expansion to be useful. With note 1's full metadata coming back
(and the pre-publish checklist landing), the Timeline → Video transition becomes
a real surface — but only after the Video edit surface ships. Defer the
Timelines spec to a post-YouTube-management work unit. Continue keeping the
Phase 4 table + state machine as-is; do not rip out. Resurrect after the YouTube
management surface stabilizes — at which point Timeline-export-driven import (a
`pito timeline import` subcommand mirroring the footage importer) becomes the
natural next surface.

User open question: confirm or override (Q11.a from spec 08).

#### Spec 09 — MCP sync (pre-spec)

Today's state. Pre-spec parked four interpretations of "MCP sync"
(state-mirroring web↔MCP via Turbo Streams; notes-capture-loop tightening; MCP
tools that drive DB sync; or other).

How the realignment shifts the question. Note 6's MCP tools section is explicit
about what the MCP surface should do for the calendar / notifications domain:
`calendar_list`, `calendar_create`, `calendar_update`, `calendar_delete`,
`purchase_create`, `notifications_unread`, `notifications_mark_read`,
`milestone_rule_create`, `milestone_rule_list`, `milestone_rule_disable`. These
are concrete tools, not abstract "sync." Note 4's IGDB section similarly implies
game-management tools (`game_sync`, `bundle_create`, `bundle_member_add`, etc.).
Note 1's pre- publish checklist work implies tools (`update_video`,
`publish_video`) that already exist or follow the existing `update_video`
pattern.

**Architect's recommendation: drop the abstract "MCP sync" framing; replace with
concrete MCP tool surface specs per the domain notes (4 + 6).** The "sync" word
is a misnomer for what the user actually wants — they want the MCP surface to
grow alongside the Rails surface. The right work unit is "MCP tool catalog
expansion: calendar / notifications / games / IGDB" which lives downstream of
each domain's Rails spec landing. The pre-spec file at `09-mcp-sync-prespec.md`
closes with a one-line pointer to "MCP tool surface specs land per-domain
alongside their Rails counterparts — see realignment-2026-05-09.md".

User open question: confirm or override.

If the user actually meant Interpretation A (state-mirroring web ↔ MCP via Turbo
Streams), that's a separate, smaller work unit — file as a follow-up under
`docs/orchestration/follow-ups.md` and pick up after the new domain surfaces
stabilize.

#### Spec 10 — Terminal sync (pre-spec)

Today's state. Pre-spec parked four interpretations of "terminal sync" (live
state mirroring CLI ↔ web via SSE / websocket; `pito sync <thing>` subcommand;
bidirectional notes sync; or other).

How the realignment shifts the question. The single-install, single-database
shape locked by ADR 0003 makes Interpretation A's value lower than it seemed:
both the CLI and the web app hit the same Postgres; refresh / re-fetch is cheap;
the existing post-confirm polling window in `extras/cli/src/app.rs` already
gives "after I do something, animate the result" and that's most of the
perceived live-state value. A push channel (SSE or websocket) is a substantial
new infrastructure surface for marginal benefit. Interpretation B
(`pito sync <thing>` subcommand) is a natural shape for the new domains —
`pito calendar sync` could pull calendar entries from a local iCal file;
`pito games sync` could batch-import a list of IGDB IDs. Both fit cleanly into
the existing CLI subcommand pattern.

**Architect's recommendation: drop in this form. The CLI gets parity surfaces
with each new Rails domain (calendar / notifications / games / IGDB) as part of
each domain's CLI parity dispatch. If a `pito sync ...` subcommand emerges
naturally from a domain (e.g., bulk-import games), spec it then.** Do not build
live state-mirroring (Interpretation A) — the existing polling window plus
on-demand refresh covers the perceived need. Interpretation B's "subcommand
mirroring footage" is captured by the "CLI parity" work unit in the ordered
roadmap.

User open question: confirm or override. If the user actually wanted live
state-mirroring, file as a follow-up.

### New scope from Mobile notes — needs new spec(s) downstream

Each item is an upcoming architect-spec dispatch. The realignment doc names
them; each gets its own brief later.

- **Channel data sync + edit surface.** Schema expansion + edit forms + sync
  trigger + banner / avatar / watermark previews. Reverses Path A2 for owned
  channels.
- **Video schema expansion + edit surface + pre-publish checklist.** Schema,
  read-modify-write `videos.update` semantics per note 1's "destructive PUT per
  part" warning, edit forms, four-item pre-publish modal, Studio deep-links.
- **Analytics sync engine + tables + dashboard.** Big — split into sub-units in
  a later spec. Phase 8 territory (the YouTube data sync engine work that was
  always coming) gets its scope locked by note 3.
- **Game model expansion + IGDB sync.** Schema, IGDB v4 client, Twitch
  client-credentials auth, last-write-wins re-sync, bundles, composite covers
  via libvips, Steam-shelf listing UI.
- **Steam-shelf game listing UI.** Lives alongside the Game model spec but worth
  calling out as its own UX work. Hundreds of games, dozens of bundles. Shelves
  at top with composite covers; omnipresent listing surface; fast scroll /
  filter / search.
- **Calendar surface.** `calendar_entry` model + views (day / week / month /
  upcoming) + milestone rules + purchase-planned + reminders.
- **Notification surface.** `notification` + `delivery_channel` + formatter
  - webhook delivery + scheduler.
- **MCP tool catalog expansion.** `calendar_*`, `purchase_*`, `notifications_*`,
  `milestone_rule_*`, `game_*`, `bundle_*`, plus expanded `update_video` /
  `update_channel` for the YouTube management surface. Each domain's MCP tools
  land as a sub-unit alongside the domain's Rails spec.
- **CLI parity for new domains.** TUI surfaces for each new domain. Lane 2a per
  existing convention. Big — split into sub-dispatches per domain.
- **Single-binary distribution + ONCE-style installer.** Deferred ~6 months.
  Captured here for traceability; not in the immediate roadmap.

## Ordered roadmap of work

Themed work units in execution order. No phase numbers. Each unit gets its own
architect-spec dispatch later.

> **Convention:** "Lane: rails" means architect dispatches `pito-rails-impl` (or
> `rails-impl`, depending on agent re-prefix follow-up status). "Lane: rust" →
> `cli-impl`. "Lane: docs" → `docs-keeper`. "Lane: mcp" → `mcp-impl`. "Lane:
> architect" means a new architect-spec dispatch (no code).

### 1. Tenant drop

**Scope.** Schema migration drops `tenant_id` from every domain table and drops
the `tenants` table; remove `BelongsToTenant` concern; remove `Current.tenant`;
collapse session / API / MCP auth to `Current.user` only; collapse per-tenant
secrets to install secrets; rename storage paths; update tests; update docs.

**Prerequisites.** Nothing. This is the first dispatch.

**Lane.** rails (primary) + rust (CLI cleanup of any tenant references) + docs
(rewrite `architecture.md` "Tenant + User + ApiToken" section, rewrite `auth.md`
§5 + §10, update `setup.md`, update `mcp.md`). One architect-spec dispatch
produces the implementation spec; one rails-impl dispatch executes; one
docs-keeper dispatch updates the prose docs; one cli-impl dispatch sweeps any
CLI references to tenants.

**Effort.** Big. ~6-10 hours of careful work plus full RSpec suite churn. Schema
migration is the load-bearing piece.

**Delivers.** ADR 0003's commitment becomes code. Doorkeeper, sessions,
`ApiToken`, `GoogleIdentity`, every domain table all clean. `Current.user` is
the only thing the auth flow populates.

- **Migration posture.** Destructive-and-reseed (no production data exists; see
  ADR 0003 "Migration posture" section). Drop tables / columns / concern /
  `Current.tenant`; reseed via `db:seed`.
- **Target folder.** `docs/plans/beta/08-tenant-drop/` — phase 8 was unused; the
  work is hefty enough to warrant its own folder.

### 2. MCP scope simplification

**Scope.** Collapse `Scopes::ALL` to `[DEV, APP]`; rewrite every
`require_scope!` callsite; data-migrate (or rotate-on-deploy — open question)
existing tokens' `scopes` jsonb arrays; update the Settings tokens UI scope
picker; update `docs/auth.md` §2 + §3; update `docs/mcp.md` scope-per-tool
table.

**Prerequisites.** Tenant drop landed.

**Lane.** rails + docs.

**Effort.** ~2-3 hours. Mostly mechanical.

**Delivers.** ADR 0004's commitment becomes code.

### 3. Channel data sync + edit surface

**Scope.** Reverse Path A2 retraction for owned `Channel`. Restore `title`,
`description`, `subscriber_count`, `view_count`, `video_count`, `thumbnail_url`,
`banner_url`, `watermark_url`, `country`, `youtube_channel_id` columns. Sync via
`Youtube::Client` (Phase 7's foundation). Edit forms for the writable subset.
Banner / avatar / watermark preview render in the channel detail page.

**Prerequisites.** Tenant drop + scope simplification landed.

**Lane.** rails (Lane 1) — first; cli + mcp parity (Lanes 2a + 2b) follow.

**Effort.** Big. Schema migration, sync wiring, edit forms, preview rendering,
RSpec coverage. The sync wiring shares plumbing with the Video sync that
follows.

**Delivers.** Channel detail / list pages look real. The Phase 7 OAuth + client
foundation gets exercised end-to-end.

### 4. Video schema expansion + edit surface + pre-publish checklist

**Scope.** Reverse Path A2 retraction for owned `Video`. Full Note 1 field set
(`youtube_video_id`, `title`, `description`, `tags[]` jsonb, `category_id`,
`thumbnail_url`, `privacy_status`, `publish_at`, `self_declared_made_for_kids`,
`contains_synthetic_media`, `made_for_kids_effective`, `etag`,
`last_synced_at`). Read-modify-write semantics for `videos.update` per note 1's
destructive-PUT-per-part warning. Edit forms for the writable subset.
`playlist_videos` join. Pre-publish checklist modal (game / age / paid promotion
/ end screen) gating publish-state transitions; Studio deep-links per item;
user-tick manual reminder, no validation. Post-publish-state-transition path
skips the modal (e.g., taking a video down from public → private).

**Prerequisites.** Channel data sync + edit surface landed (shared sync
plumbing).

**Lane.** rails (Lane 1) first; cli + mcp parity follow. The MCP `update_video`
tool gains the full writable field set.

**Effort.** Big. The pre-publish modal is its own UI primitive. The
read-modify-write semantics for `videos.update` are subtle (sending the
`snippet` part without a tag wipes existing tags) — RSpec coverage on this is
load-bearing.

**Delivers.** YouTube management's headline workflow ships: edit a video's
title, tags, category, thumbnail; schedule it via `publishAt`; tick the
four-item checklist; publish. The Studio deep-link UX makes the unmanaged fields
(game, age, paid promotion, end screen) explicit.

- **Project ↔ Video association absorbs the dropped Timeline model.** A direct
  nullable `project_id` column on `Video` replaces the Timeline intermediary.
  Imported videos: `project_id = NULL`. Future videos: assigned at creation.
  Project page shows linked videos via direct join. (Resolves Phase 7.5 pre-spec
  08; see Resolved ambiguities #1.)

### 5. Analytics sync engine + tables + dashboard

**Scope.** Phase 8 territory. Note 3 locks the design: `channel_daily`,
`video_daily`, `video_daily_by_<slice>` (country / device / os / traffic source
/ subscribed status / age×gender), `channel_window_summary`,
`video_window_summary`, `top_videos_window`, `video_retention`. C1-C5 + V1-V9
query implementations. Daily nightly sync (refresh last 3 days for revision
lag). Weekly retention refresh. Active-video classification. Cross-video locals
(when-to-publish, best-duration, topics-that-work, thumbnail-decay) computed by
joining locally. Monetization schema-ready / sync-disabled. Dashboard renders
Studio-faithful ratios from windowed-summary tables.

**Prerequisites.** Video schema expansion landed (Analytics depends on `Video`
having metadata for the cross-video locals to join against).

**Lane.** rails (Lane 1) — split into multiple sub-units in a separate spec:
schema migration, sync engine, dashboard views. Probably 3-4 architect
dispatches over a couple of waves.

**Effort.** Very big. The largest single domain expansion in the realignment.

**Delivers.** Analytics dashboard becomes real. The current placeholder charts
(Phase 4) get backed by real per-day metrics.

### 6. Game model expansion + IGDB sync

**Scope.** Per note 4. Schema expansion (`igdb_id`, `igdb_slug`,
`igdb_checksum`, ratings cluster, time-to-beat columns, external store IDs,
local-only fields). IGDB v4 client (POST / Apicalypse / Twitch
client-credentials auth / token refresh / 4-req/s rate limit). On-demand sync
with last-write-wins. `bundle` + `bundle_member` tables; bundle types `series` /
`collection` / `genre` / `custom`; IGDB-source provenance. Composite cover art
generation via Active Storage variant + libvips: 5 layouts (2 / 3 / 4 / 5-9 /
10+); regen trigger on checksum-of-member-image-ids change; 600×800 JPEG.
`video_game_link` join table for analytics attribution. Steam-shelf listing UX
(shelves at top with composite covers, omnipresent listing surface).

**Prerequisites.** Tenant drop + scope simplification (uses the new `app`
scope). Independent of YouTube management — can run in parallel with units 3 / 4
/ 5.

**Lane.** rails (Lane 1) first; cli + mcp parity follow.

**Effort.** Big. The IGDB client + composite cover generation are each their own
sub-unit.

**Delivers.** Games library becomes the Steam-style shelf the user described.
Bundles surface for the analytics-by-game attribution.

### 7. Calendar model + views

**Scope.** Per note 6. `calendar_entry` table + the eight `entry_type` values +
type-specific metadata jsonb + `release_precision` + `manual_date_override`.
Derived entries (`channel_published`, `video_published`, `video_scheduled`)
written by sync jobs. Manual entries (game releases, milestones, custom).
`purchase_planned` entries linked to `game_release` entries with quick-pick
storefronts. `milestone_rule` table + idempotent firing semantics. Calendar
views (day / week / month / upcoming-game-releases / upcoming-without-purchase /
recent-milestones / stream-of-occurred-milestones).

**Prerequisites.** Game model expansion landed (so `game_release` entries can
reference `game_id` / `igdb_id`). YouTube management's video sync landed (so
`video_published` / `video_scheduled` derivation has real data to derive from).

**Lane.** rails (Lane 1) first; cli + mcp parity follow.

**Effort.** Big. The calendar UI is its own UX surface; the `milestone_rule`
evaluator integrates with the analytics sync engine.

**Delivers.** A user-facing calendar surface with derived + manual + auto
entries.

- **UI shape.** Month grid + Schedule view (Google Calendar style). Day / week
  views deferred. (Resolves Resolved ambiguities #5.)

### 8. Notification model + delivery channels + formatter + webhook delivery

**Scope.** Per note 6. `notification` table (kind, subject_entry_id,
subject_rule_id, payload, severity, read_at). `delivery_channel` table (kind,
name, config, enabled, digest_enabled, digest_at_local_time, immediate_kinds).
Formatter component rendering Discord embeds / Slack blocks / MCP / in-app.
Default per-channel routing (urgent immediate on webhooks, all kinds in-app).
Game-release reminder logic (T-30 / T-7 / T-1 / T-0 offsets, suppression on
`purchase_planned` link, severity escalation, `release_precision` gating).
Scheduler runs every minute for digest assembly + immediate dispatch. Webhook
URLs encrypted at rest.

**Prerequisites.** Calendar model landed (notifications are derived from
calendar entries + milestone rules).

**Lane.** rails (Lane 1) first; cli + mcp parity follow.

**Effort.** Medium-big. The formatter is its own component; the scheduler
plumbing builds on the existing Sidekiq + sidekiq-cron setup.

**Delivers.** Discord + Slack daily digest + immediate webhook delivery. In-app
inbox.

- **All-users-see-all.** No per-user opt-in, no per-user read state. App
  stream + Slack webhook + Discord webhook + MCP all surface the same
  notifications. Webhooks are install-level — one each, shared. (Resolves
  Resolved ambiguities #6.)

### 9. MCP tool catalog expansion

**Scope.** Per note 6's MCP tools section + note 4's implied tools. New tools
land alongside their domain's Rails spec. Per-domain consolidated:

- `update_video` / `update_channel` (existing, expanded to writable field set)
- `game_sync`, `bundle_create`, `bundle_update`, `bundle_member_add`,
  `bundle_member_remove`
- `calendar_list`, `calendar_create`, `calendar_update`, `calendar_delete`
- `purchase_create`, `purchase_update`, `purchase_delete`
- `notifications_unread`, `notifications_mark_read`
- `milestone_rule_create`, `milestone_rule_list`, `milestone_rule_disable`

Plus parity expansion of existing tools to the new schema columns.

**Prerequisites.** Each tool lands once its domain's Rails spec lands. This unit
is mostly a tracking / dispatch convention rather than a single work unit — each
domain spec triggers an `mcp-impl` parallel dispatch.

**Lane.** mcp.

**Effort.** Medium per domain. Cumulative effort is large but distributed across
the prior units' dispatches.

**Delivers.** Mobile interop with every new domain. Claude Mobile can manage the
calendar, notifications, games, channels, videos via MCP tool calls.

- **Per-domain coverage matrix.** Web is canonical; MCP is best-effort parity.
  Each new domain spec declares its own MCP coverage (yes / no per action). Some
  actions remain web-exclusive — e.g., YouTube upload. (Resolves Phase 7.5
  pre-spec 09; see Resolved ambiguities #2.)

### 10. CLI parity for new domains

**Scope.** The `pito` CLI gets TUI surfaces for each new domain. Per the
existing Lane 2a convention. Big surface area:

- Game library shelves + game detail
- Calendar day / week / month views
- Notification inbox
- Channel + video edit forms
- Pre-publish checklist (in-TUI overlay)

**Prerequisites.** Each domain's Rails spec landed. Lane 2a per existing
convention runs in parallel with Lane 2b (mcp).

**Lane.** rust.

**Effort.** Big. Distributed across each domain's dispatch.

**Delivers.** TUI parity with the new web surfaces.

- **Per-domain coverage matrix.** Web is canonical; CLI is best-effort parity.
  Same posture as MCP (work unit 9). Each new domain spec declares its own CLI
  coverage. (Resolves Phase 7.5 pre-spec 10; see Resolved ambiguities #3.)

### 11. Phase 7.5 pre-specs 08 / 09 / 10 resolution

**Scope.** Per the pre-spec sections above, the architect's recommendations are:

- 08 (Timelines) — defer to a post-YouTube-management work unit.
- 09 (MCP sync) — drop the abstract framing; replaced by the per-domain MCP
  catalog expansion (unit 9).
- 10 (Terminal sync) — drop in this form; absorbed by the per-domain CLI parity
  (unit 10).

**Prerequisites.** User confirms or overrides each recommendation.

**Lane.** docs (close out the pre-spec files with one-line pointers; add
follow-ups to `docs/orchestration/follow-ups.md` for any deferred
interpretations).

**Effort.** Tiny — a docs-keeper dispatch closes the three pre-spec files.

**Delivers.** Phase 7.5 pre-specs 08 / 09 / 10 stop being open questions.

### 12. Single-binary distribution + ONCE-style installer

**Scope.** Per note 7, Option 1 (keep pito as a CLI / TUI app, add a ONCE-style
installer wrapper). One-line bash installer; `pito setup` TUI wizard;
`pito update` self-update; `pito backup` / `pito restore`; GitHub Releases or
self-hosted endpoint for binary distribution.

**Prerequisites.** Domain stability (units 3-8 settled). Deferred ~6 months per
the user's direction.

**Lane.** rust + cli + ops.

**Effort.** Big. A few weeks of focused work for an MVP per note 7's estimate.

**Delivers.** A self-hosted-end-user installable pito.

### Next concrete dispatch

After the user reviews this realignment doc, the very first architect-spec
dispatch should be **Tenant drop** (work unit 1). It is the prerequisite for
every other unit and is the largest single risk in the realignment.
Specifically: `architect-spec` produces a single implementation spec under
`docs/plans/<phase>/specs/tenant-drop.md` (the phase-folder name is itself an
open question — see Phase numbering below). The implementation spec covers
schema migration, model unwind, controller / MCP rack-app simplification,
storage path migration, test obligation removal, and the docs-keeper-driven
prose-doc rewrites in `architecture.md` + `auth.md` + `setup.md` + `mcp.md`.

## Open ambiguities for user to resolve

1. **Phase 7.5 pre-spec 08 (Timelines) — defer or resurrect?** Architect's
   recommendation: defer to a post-YouTube-management work unit. User confirms
   or overrides.

2. **Phase 7.5 pre-spec 09 (MCP sync) — drop abstract framing or build
   state-mirroring (Interpretation A)?** Architect's recommendation: drop the
   abstract framing; per-domain MCP catalog expansion supersedes it. If the user
   actually meant Interpretation A (Turbo Streams from MCP mutations to web),
   file as a follow-up rather than a primary unit.

3. **Phase 7.5 pre-spec 10 (Terminal sync) — drop in current form or build live
   state-mirroring?** Architect's recommendation: drop in current form.
   Per-domain CLI parity (unit 10) covers the natural subcommand surface. If the
   user meant live state-mirroring, file as a follow-up.

4. **Token migration on scope simplification — rotate-on-deploy or in-place
   rename via data migration?** Architect's lean: in-place rename. The install
   only has the user's own tokens; a clean mapping table is easier to audit than
   a "you must re-mint everything" deploy note.

5. **Calendar UI shape — full-page calendar grid, list view, both?** Note 6
   lists views (day / week / month / upcoming) but doesn't lock visual shape.
   The user's preferences (Steam shelves for games suggest visual / spatial;
   "one calendar per tenant" suggests unified) will route the UX dispatch.

6. **Notification "all users see all notifications" or "per-user opt-in"?**
   Doesn't matter much given no per-user data isolation, but the read- state
   model differs (single `notification.read_at` column vs.
   `notification_read(notification_id, user_id, read_at)` join). Note 6 leans
   optional: "today, one user per tenant — extensible later via a
   `notification_read(...)` join when needed." User confirms current shape.

7. **Pre-publish checklist scope — also for video metadata edits (title /
   description) or only for publish-state transitions?** Note 1 says "this check
   applies to: direct publish, scheduled publish. It does not apply to: going
   from public → private/unlisted, or to metadata edits on an already-public
   video." User confirms current shape.

8. **Phase numbering.** The user instructed "no new phase numbers in this
   dispatch — group work thematically; leave phase numbering to a separate
   decision later." This realignment doc carries the thematic grouping. Open
   question: when the first new spec dispatch happens (the Tenant drop), where
   does it physically live in the docs tree —
   `docs/plans/beta/realignment-2026-05-09/specs/tenant-drop.md`?
   `docs/plans/beta/08-tenant-drop/specs/...`? A separate decision.

9. **`Tenant` model: drop entirely vs. downgrade to single-row `AppInstall`
   table?** ADR 0003 leaves this open. Master agent's lean: drop entirely.
   Install-level settings can live on a single `AppSetting` row (already exists
   for `max_panes` / `pane_title_length` / theme). Less moving parts.

10. **Path A2 reversal scope — reverse for both owned AND tracked channels /
    videos, or only owned?** ADR 0003 doesn't touch this; the Mobile notes
    assume owned content (the OAuth-token flow is the sync path). Tracked
    content sync (Phase 8 territory, Path A2's `Youtube::PublicClient`) hasn't
    been touched yet. Master agent's lean: reverse for owned content only
    initially; tracked content's metadata expansion follows as a separate work
    unit when tracked sync ships.

## Resolved ambiguities (2026-05-10)

The user resolved every open ambiguity above on 2026-05-10. Each answer is
pinned here. The numbering matches the **Open ambiguities** list above.

1. **Phase 7.5 pre-spec 08 (Timelines) — drop the Timeline model entirely.**
   Replace with direct `Video.project_id` (nullable). Imported videos:
   `project_id = NULL`. Future videos: assigned at creation. Project page shows
   linked videos via direct join. Folded into work unit 4 (Video schema
   expansion).
2. **Phase 7.5 pre-spec 09 (MCP sync) — stays alive, reframed as a per-domain
   "mirroring coverage matrix".** For each web action, the domain spec declares
   MCP coverage (yes / no). Web is canonical, MCP is best-effort parity. Some
   actions remain web-exclusive (e.g., YouTube upload).
3. **Phase 7.5 pre-spec 10 (Terminal sync) — same posture as #2, but for the
   Rust CLI.** Per-domain coverage matrix; web is canonical; CLI is best-effort
   parity.
4. **Token migration on scope simplification — rotate-on-deploy.** Force re-auth
   on Claude Mobile + Web MCP once. Single user, trivially safe.
5. **Calendar UI shape — month grid + Schedule view (Google Calendar style).**
   Day / week deferred.
6. **Notification model — all-users-see-all.** No per-user opt-in. App stream +
   Slack webhook + Discord webhook + MCP all surface the same notifications.
   Webhooks are install-level (one each, shared).
7. **Pre-publish checklist scope — publish / schedule transitions only.**
   Metadata edits skip the checklist.
8. **Phase numbering for tenant-drop spec — `docs/plans/beta/08-tenant-drop/`.**
   Phase 8 is otherwise unused; the work is hefty enough to warrant its own
   folder.
9. **Tenant model disposition — full drop, DB reseed.** No `AppInstall`
   downgrade. ADR 0003 + git history are the artifacts.
10. **Path A2 reversal scope — retired entirely.** No "owned vs. tracked"
    distinction. Every Channel and Video is owned by definition.

Two structural calls outside the original 10:

- **Login-with-Google dropped.** Captured in
  `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`. Phase
  7's `GoogleIdentity` role narrows to YouTube API connection only (likely
  renamed to `YoutubeConnection` in the architect-driven Phase 7 revision). The
  login page offers local password auth only.
- **Tenant-drop migration posture — destructive-and-reseed, no backfill.**
  Captured in ADR 0003's "Migration posture" section. No production data exists;
  reseed via `db:seed` is the easiest path.

## Cross-references

- ADR `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- ADR `docs/decisions/0004-mcp-scope-simplification-dev-app.md`
- ADR `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md`
- ADR `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`
- Mobile notes — load-bearing (still under `docs/notes/` until their target spec
  lands):
  - `docs/notes/2026-05-09-17-56-06-video-model-youtube-api.md`
  - `docs/notes/2026-05-09-18-02-30-video-model-addendum-end-screen.md`
  - `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md`
  - `docs/notes/2026-05-09-18-54-00-game-model-igdb.md`
  - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md`
- Mobile notes — captured durably elsewhere and deleted in the 2026-05-10 docs
  sweep:
  - `2026-05-09-19-00-35-tenant-scope-and-idor.md` → archived at
    `docs/decisions/archives/idor-spec.md` (v2-SaaS reference per ADR 0003).
  - `2026-05-09-19-32-19-once-distribution-model-research.md` → captured in
    `docs/future/install-wizard.md` (Cloudflare specifics, distribution shape,
    ONCE relationship) plus work unit 12 below.
  - `2026-05-09-19-56-01-drop-tenant-and-future-install-wizard.md` → captured in
    ADR 0003 + `docs/future/install-wizard.md`.
  - `2026-05-09-21-23-41-realignment-report.md` → captured in this doc
    (architect's recommendations + ordered roadmap above).
  - `2026-05-09-21-41-38-user-answers-to-realignment-ambiguities.md` → captured
    in this doc's **Resolved ambiguities (2026-05-10)** section.
- Phase 7.5 pre-specs being closed:
  - `docs/plans/beta/7.5-followups-and-foundations/specs/08-timelines-resurrection-prespec.md`
  - `docs/plans/beta/7.5-followups-and-foundations/specs/09-mcp-sync-prespec.md`
  - `docs/plans/beta/7.5-followups-and-foundations/specs/10-terminal-sync-prespec.md`
- Per-phase additions / dropped tracking (created in this dispatch):
  - `docs/plans/beta/12-auth-ui-multi-user-readiness/dropped.md`
  - `docs/plans/beta/07-google-oauth-youtube-foundation/additions.md`
  - `docs/plans/beta/07-google-oauth-youtube-foundation/dropped.md`
  - `docs/plans/beta/7.5-followups-and-foundations/additions.md`
  - `docs/plans/beta/7.5-followups-and-foundations/dropped.md`
- `docs/orchestration/follow-ups.md` — appended with realignment entries.
