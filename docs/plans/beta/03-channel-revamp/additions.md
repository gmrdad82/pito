# Phase 3 — Scope Additions and Deviations

The original `03-plan.md` was Auth Foundation. The current phase replaces that
scope with the Channel Revamp + data-only Tenant/User models. Auth Foundation
(auth concern, scopes, ApiToken, login UI, Doorkeeper) is deferred to a future
phase.

## Channel model revamp — entire phase

Original 03-plan.md scope: User, Tenant, ApiToken, scope catalog,
Api::AuthConcern, tenant scoping, settings UI for tokens.

Current scope: Channel model fully refactored to 6 new fields (channel_url,
star, connected, syncing, last_synced_at, tenant_id) + Tenant + User schema-only
models + ChannelSync placeholder job + cron + BulkSync mirror + dashboard chart
visibility localStorage.

**Why:** the user wants visible, iterable Channel UX as the next deliverable,
ahead of auth plumbing. Schema is cheap to redo since data is seed-only.

## Tenant + User schema-only — no auth concern

Tenant + User models, validations, factories, seeds. No `Api::AuthConcern`. No
`ApiToken`. No scope catalog. No login UI. No Doorkeeper. No `Current` request
lifecycle wiring beyond `before_action :set_current_tenant_and_user` reading
from seeded singletons.

**Why:** auth is non-trivial and the user wants Channel-first delivery. The
schema being in place means future auth phase doesn't require model migrations
on Channel/Tenant/User.

## Channel URL — locked after create

URL field is `string` (case-sensitive), unique B-tree index, immutable
post-create. `before_update :prevent_url_change` raises if
`channel_url_changed?`.

**Why:** YouTube channel ID `UC<22>` is the immutable identifier. Handles
change; we want the canonical immutable form.

## ChannelSync job — placeholder with full lifecycle

Job stub with `syncing` flag flip + `last_synced_at` timestamp + graceful nil on
deleted channels. Real public API + OAuth API work lands later phases.

**Why:** wiring the lifecycle now means future YouTube sync work just fills in
the placeholder body. The UI (syncing pill, [ sync ] button, bulk_sync flow) can
be tested end-to-end with the placeholder.

## Bulk-as-foundation pattern

Single delete and single sync go through the bulk operation flow with one ID.
URL pattern `/syncs/:type/:ids` mirrors `/deletions/:type/:ids`. MCP tools
`bulk_delete_channels` and `bulk_sync_channels` accept 1 or N IDs and require
`confirm: bool` two-step flow. Terminal app uses bulk picker for both.

**Why:** one mental model across surfaces; code reuse; confirmation is a
feature; future bulk operations inherit the pattern.

## No JavaScript alert/confirm/prompt — hard rule

Forward-going project-wide rule. The action confirmation page framework
(`shared/_action_screen.html.erb` + `DeletionsController` shape) is the
canonical pattern. Single-channel delete already uses it (Alpha-era).

**Why:** consistent professional UX; testable; can carry rich context (skip
badges, breakdowns).

## Dashboard chart visibility persists in localStorage

Each chart gets a stable `data-chart-id` slug. Stimulus controller reads/writes
`localStorage["pito_dashboard_charts_visible"]` (JSON array of slugs). On first
visit, all checkboxes checked (per existing UX default). On revisit, last state
restored.

**Why:** user wants per-browser memory of which charts they care about.
localStorage is the simplest mechanism; per-device only is acceptable.

## Searchable concern dropped from Channel

Channel no longer includes `Searchable`. Removed from `ReindexAllJob`'s
iteration list. `meilisearch_engine_spec.rb` Channel branch dropped.
`search_controller#index` and `search_content` MCP tool drop the channel branch.

**Why:** Channel has no `title` or `description` to index. Search is a
video-only feature for now. When YouTube sync lands and channels have synced
metadata, Searchable can be re-added.

## Tenant + User credentials in :owner block

`Rails.application.credentials.dig(:owner)` carries `tenant_name`, `username`,
`email`, `password`. Seed reads from this block; falls back to placeholders +
STDOUT warning if missing.

**Why:** mirror the `:postgres` pattern. Secrets in encrypted credentials only,
never in `.env*`.

## Workflow — direct commits to main

No more `step-NN` branches or PRs on pito or pito-sh. Direct commits to main
with one-line meaningful messages. Architect commits + pushes after user
validates the manual playbook.

**Why:** early stages, move fast, no need for multi-reviewer PR overhead.

## Original Auth Foundation deferred

The work in original `03-plan.md` (Api::AuthConcern, scope catalog, ApiToken
with full Beta scope catalog, settings UI for tokens) is deferred to a future
phase. The deferred phase will not need to re-do schema (Tenant + User exist),
only add the auth surface.

**Why:** Channel Revamp delivers visible value faster. Auth is non-trivial and
benefits from being its own focused phase.

## pito-sh adds the `open` crate dependency

Original plan (spec): `[ view ]` action in `src/ui/channel_detail.rs` would
invoke `xdg-open` (platform-appropriate) for the canonical URL.

Addition: pito-sh's `Cargo.toml` now depends on `open = "5"` (cross-platform
crate that delegates to `xdg-open` on Linux, `open` on macOS, `start` on
Windows). The terminal app uses `open::that(url)` rather than shelling out to a
hard-coded `xdg-open` binary.

**Why:** the spec phrased the requirement as "platform-appropriate" without
naming a crate; `open` is the de-facto standard Rust crate for this and works on
all three host OSes without conditional compilation. Picking it now also
future-proofs distribution to non-Linux developers.

## `Confirmable` controller concern extracted (not deferred)

Original plan (spec, step A6b): the `Confirmable` concern extraction is marked
"should-do — defer if disruptive." If extraction proves too disruptive
mid-phase, the implementer may defer it and document in `dropped.md`.

Addition: the `Confirmable` concern WAS extracted at
`app/controllers/concerns/confirmable.rb` and is included by both
`DeletionsController` and `SyncsController`. No deferral. Both controllers
delegate `load_items`, `cancel_path`, and the type→model dispatch helper through
the concern. Specs green.

**Why:** the `pito-bulk-sync` agent found the duplication risk between
`DeletionsController` and the new `SyncsController` was the larger of the two
evils and lifted the concern out cleanly. Future bulk operations (per the spec's
section 9 forward-looking notes) immediately benefit from the shared base.

## ChannelSync cron cadence locked at daily / midnight UTC

Original plan (spec, section 5): "`SyncStarredChannelsJob` runs at midnight UTC
via `sidekiq-cron`."

Addition: `config/sidekiq_cron.yml` registers `sync_starred_channels` with cron
`"0 0 * * *"` (daily at midnight UTC). The earlier draft considered
every-6-hours and hourly; both were rejected. The placeholder ChannelSync is
cheap, but YouTube quota is finite — once the real public/OAuth API integration
lands in a future phase, daily is the right cadence for "starred" semantics (a
manually flagged subset, not all connected channels). The "uncomment when beta
YouTube integration is implemented" stubs in the same yml document the future
every-6-hours cron for connected-channel sync as a separate job.

**Why:** locking the cadence here so future contributors do not flip it
casually. Daily-at-midnight-UTC is the single source of truth for the
starred-channel cron. Other syncs get their own cron entries.

## SavedView for `kind == "channels"` labels with `id.to_s` (deliberate placeholder)

Original plan (spec): `app/models/saved_view.rb` line 31 — replace
`entity&.title` with kind-aware dispatch
(`kind == "channels" ? entity&.id&.to_s : entity&.title`). Note: "when YouTube
sync lands and channels gain a synced title or display field, this rule may be
revisited."

Addition: confirmed in implementation. The `entity_labels` channel branch reads
`entity&.id&.to_s` — labels show numeric IDs in saved-view widgets for now. This
is a deliberate placeholder; once Phase 7 / 8 (YouTube OAuth + sync) lands and
Channel gains a synced display field, this rule needs to be revisited. The
`display_name_with_deletions` test in
`spec/components/saved_views_section_component_spec.rb` was updated accordingly.

**Why:** documenting the trade-off explicitly so the next phase that touches
Channel display fields knows to revisit `saved_view.rb` line 31.
