# Handoff — /channels revamp + Live Updates feature

**Date:** 2026-05-19 **Author:** Master agent + user planning session **Pair
docs:**

- `docs/orchestration/follow-ups.md` (Live Updates entry + /channels next-phase
  scope entry — already captured, do not re-edit from here)
- `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` (deferred spec
  debt to engage in Wave F)
- `docs/realignment-2026-05-09.md` Unit 3 (foundational direction for the
  /channels surface)

This document is the architect-spec-ready foundation for the next session's work
on /channels and the Live Updates feature. Read it end-to-end before opening any
plan / spec files.

---

## 1. Way of work (locked)

These three rules govern the entire phase. Re-read at the start of every
dispatch:

- **Layout-first with mocked data.** The page is revamped step-by-step against
  mocks — real-shape but fake values via a `Channels::MockData.*` service
  module. Implementation swap to real data happens ONLY after the user validates
  the visual layout end-to-end. This is the iteration loop, not a shortcut.
- **No RSpec during the layout phase.** Specs are a dedicated consolidation pass
  after the user signs off on visuals. Iteration agents write code only; spec
  writing is its own wave.
- **No write operations on channels.** /channels is a read-only YouTube mirror
  this phase. The single exception is channel removal (revoke), which already
  exists via `Channels::BulkRevokesController`. No description editing, no
  banner upload, no metadata mutation surface of any kind.

---

## 2. /channels scope — IN / OUT

### IN — channel basics (lifetime)

| Field          | Source                                                                       | Notes                                  |
| -------------- | ---------------------------------------------------------------------------- | -------------------------------------- |
| name           | `channels.title`                                                             |                                        |
| handle         | `channels.handle`                                                            |                                        |
| channel URL    | `channels.channel_url`                                                       |                                        |
| Studio URL     | derived helper: `"https://studio.youtube.com/channel/#{youtube_channel_id}"` | no new column                          |
| avatar         | `channels.avatar_url`                                                        | same asset family as thumbnail         |
| banner         | `channels.banner_url`                                                        | readonly mirror                        |
| subscribers    | `channels.subscriber_count`                                                  |                                        |
| views lifetime | `channels.view_count`                                                        |                                        |
| watch time hrs | Analytics API `estimatedMinutesWatched`                                      | renderer divides by 60                 |
| videos count   | `channels.video_count`                                                       | YouTube count, NOT pito-imported count |
| joining date   | `channels.published_at`                                                      | render as date + days-since            |

### IN — analytics (Wave A and B)

- Top Content — filtered to `creatorContentType==VIDEO_ON_DEMAND` (no Shorts, no
  Lives; user only ships Videos)
- Impressions (Wave D cross-report — column exists, NULL today)
- Impressions CTR (Wave D cross-report)
- Average view duration
- How viewers find your videos (traffic-source breakdown)
- Content suggesting you (`RELATED_VIDEO` traffic source)
- External sites / apps (`EXTERNAL` traffic source)
- YouTube search terms (`YT_SEARCH` traffic source, top-N capped)
- Audience geography (country breakdown)
- Watch time from subscribers (`subscribedStatus` dim)
- Formats your viewers watch (`creatorContentType` dim — VOD-effectively)
- Gender
- Age
- Device Type (device breakdown)
- When your viewers are on YouTube (day x hour heatmap)

### IN — Desktop additions

- Time-range filters: 7d / 28d / 90d / **365d** / lifetime. Add `'365d'` to the
  `WINDOWS` enum + a migration to backfill rolling-window summaries.
- Per-year breakdown
- Per-month breakdown
- Year + month combo
- Latest content shelf (5 videos, from the uploads playlist)
- Trend indicators (subs / views / watch time → rising / steady / dropping over
  last 28d). Compute as `(current_28d - prior_28d) / prior_28d * 100`, store as
  numeric delta percent on `channel_window_summaries` (new columns — see
  schema-ADD section below). Display TBD at design time (arrows / text / both —
  open question for the spec).

### OUT — explicitly dropped this phase

- `star` concept entirely (drop column + scope + controller + route + callback
  - sort + filter + view + all references)
- Shorts (no `creatorContentType=SHORTS` rows)
- Live streams (no `creatorContentType=LIVE_STREAM` rows)
- Playlists (model stays for future, no display this phase)
- "What your audience watches" (other channels) — Studio-only, not in API
- "Channels your audience watches" — Studio-only
- "Popular with new viewers / casual / regular" — Studio-only
- "Audience by watch behaviour" — Studio-only
- "Top subtitle / CC language" — dropped (verify-needed item, user opted to
  drop)
- "Monthly audience" (unique viewers per month) — dropped (verify-needed item)
- "Playlist featuring you" — dropped
- All write operations on channels (no edit/update, no description editing, no
  banner upload). Revoke is the single allowed mutation.

### OUT — schema columns to drop in migration

The migration cascade in Wave B drops:

- `country`
- `default_language`
- `handle_changed_at`
- `title_changed_at`
- `hidden_subscriber_count`
- `watermark_url`, `watermark_timing`, `watermark_offset_ms`
- `links` (jsonb array)
- `star` (boolean — and every reference site: scope, controller, route,
  callback, sort, filter, view, navbar pin, keybinding)
- `last_synced_at` (replaced by the split pair — see ADD section)

**Schema retention (locked 2026-05-19, user reversal):** `description` and
`keywords` are NOT dropped. Both columns survive Wave B as index-only fields
feeding `Meilisearch::ChannelIndexer` (Phase B Omnisearch expansion). Neither
has a display surface; both are populated via `ChannelDataSync` from the YouTube
Data API (`snippet.description` and `brandingSettings.channel.keywords`
respectively). See follow-ups doc "Omnisearch channels expansion" for the
indexer wiring and the future channel-recommendation flow on the game detail
page that consumes these signals.

### ADD — new schema columns

On `channels`:

- `data_synced_at` (timestamp) — replaces `last_synced_at` for the data half
- `analytics_synced_at` (timestamp) — replaces `last_synced_at` for the
  analytics half
- `data_syncing` (boolean) — mutex for `ChannelDataSync`
- `analytics_syncing` (boolean) — mutex for `ChannelAnalyticsSync`
- `data_sync_error` (text) — last data sync failure message
- `analytics_sync_error` (text) — last analytics sync failure message

The existing single `last_sync_error` column (if present) is replaced by the
split pair.

On `channel_window_summaries`:

- `subscriber_count_trend_28d_pct` (numeric)
- `view_count_trend_28d_pct` (numeric)
- `watch_time_trend_28d_pct` (numeric)

---

## 3. YouTube API mapping — summary

A short reference for the values the architect needs at hand. The full 42-row
audit lives inline below rather than in a side playbook this phase; if it grows,
the architect breaks it out into
`docs/orchestration/playbooks/youtube-api-mapping-channels-phase-2026-05-19.md`
as a side deliverable when the Wave B spec is written.

### Summary table (in-scope items → API surfaces)

| Surface                           | API                                                                           | Notes                                  |
| --------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------- |
| name, handle, avatar, video_count | Data API `channels.list?part=snippet,statistics,brandingSettings`             |                                        |
| banner                            | `brandingSettings.image.bannerExternalUrl`                                    | readonly                               |
| subscribers, views                | `statistics.subscriberCount`, `viewCount`                                     |                                        |
| watch time hours lifetime         | Analytics API `estimatedMinutesWatched`                                       | MINUTES — divide by 60 at render       |
| Top Content                       | Analytics API top-videos report, filter `creatorContentType==VIDEO_ON_DEMAND` | **[VERIFY GA]**                        |
| traffic-source breakdown          | Analytics API dim `insightTrafficSourceType`                                  |                                        |
| YT search terms                   | `insightTrafficSourceDetail` filtered to `YT_SEARCH`                          | top-N capped                           |
| audience geography                | dim `country`                                                                 |                                        |
| watch time from subs              | dim `subscribedStatus`                                                        |                                        |
| formats                           | dim `creatorContentType`                                                      |                                        |
| gender / age                      | dim `gender,ageGroup`                                                         |                                        |
| device type                       | dim `deviceType`                                                              |                                        |
| viewer time heatmap               | dim `day,hour`                                                                | day x hour                             |
| impressions + CTR                 | impressions report (Wave D cross-report)                                      | ADR 0011 — currently NULL on summaries |

### Key constants the architect needs

- **Watch time unit:** API returns MINUTES (`estimatedMinutesWatched`). The
  renderer divides by 60.
- **Avatar vs thumbnail:** same asset, different sizes
  (`snippet.thumbnails.{default,medium,high}`). No separate channel-thumbnail
  asset.
- **Banner readonly:** `brandingSettings.image.bannerExternalUrl`.
- **Quota math:** ~30 units per channel per day for the full surface. 20
  channels = ~6.2% of the 10k budget. Comfortable.
- **Top Content filter:** `filters=creatorContentType==VIDEO_ON_DEMAND` (drops
  Shorts + Lives). **[VERIFY GA status of the `creatorContentType` dimension
  live before specing the affected wave.]** Fallback if not GA: client-side
  filter via `videos.list?part=snippet,contentDetails` checking
  `liveBroadcastContent` plus a duration < 60s heuristic.

---

## 4. Sync architecture (locked)

```
Channel#sync!(scope: :all | :data | :analytics)
  enqueues ChannelDataSync      if scope in [:all, :data]
  enqueues ChannelAnalyticsSync if scope in [:all, :analytics]

ChannelDataSync (per channel):
  1. Set channels.data_syncing = true (early return if already true)
  2. Call Youtube::Client#fetch_channel — refresh basics
  3. On success: data_syncing = false, data_synced_at = now, data_sync_error = nil
  4. On failure: data_syncing = false, data_sync_error = err.message
  (data_synced_at is NOT stamped on failure)

ChannelAnalyticsSync (per channel):
  Same shape, for Top Content + window summaries + slices.
  analytics_syncing mutex + analytics_synced_at + analytics_sync_error.

Daily CRON (sidekiq-cron):
  Channel.find_each do |c|
    ChannelDataSync.perform_later(c)
    ChannelAnalyticsSync.perform_later(c)
  end
  # 2N parallel jobs total; Sidekiq concurrency bounds throughput.

Manual [sync] UI on channel detail page:
  - Two muted-when-syncing links: [sync data] + [sync analytics]
  - Each independently respects its respective mutex
  - OR a single [sync] menu exposing both options (design choice for the spec)
```

---

## 5. Multi-channel-per-Google-account picker

When the OAuth callback returns N discovered channels (a single Google account
can own multiple YouTube channels — common with brand accounts):

- Show a picker modal: "select which channels to add"
- Each row pre-checked; the user unchecks the ones to skip
- Submit → enqueue `ChannelDataSync` + `ChannelAnalyticsSync` for each
  newly-added channel
- Replaces the current auto-add behavior

This is the path the long-term "unified dashboard across my channels" goal flows
through — the picker UX should make adding ALL channels as easy as one click.

---

## 6. Channel-add picker UI (modal pattern)

Pattern reference: the bundle modal from /games.

- **Header:** `select channels to add from <google_account_email>`
- **Body:** discovered channels — avatar + name + handle + checkbox per row
- **Footer:** `[ add selected ]` + `[ cancel ]`

Muted styling on `[ cancel ]` per the confirmation/decision-dialog convention.
Pre-check each row by default; the common case is "add everything".

---

## 7. Live Updates feature integration

The Live Updates feature (captured in `docs/orchestration/follow-ups.md`
2026-05-19) ships ALONGSIDE the /channels work in this phase. Four sub-features:

1. **Client-side relative-time ticker** — every `~Xs ago` / `~Xm ago` label
   ticks itself. Stimulus controller, cadence-aware downshift (per-second under
   1m → per-minute under 1h → per-hour beyond).
2. **Sessions table push** — out of /channels scope but in this phase since Live
   Updates is being built once. Via ActionCable on `Session`
   `after_create_commit` / `after_update_commit` / `after_destroy_commit`.
3. **Stack tables push** — `/settings` Postgres / Meilisearch / Voyage AI /
   assets / notes panes. Out of /channels scope but in this phase.
4. **NEW: /channels detail page push** — when `ChannelDataSync` or
   `ChannelAnalyticsSync` completes, broadcast updated sections via Turbo
   Stream:
   - Data sync done → re-render basics card (name, avatar, banner, subs, views,
     video count) + `data_synced_at` label
   - Analytics sync done → re-render analytics sections + `analytics_synced_at`
     label
   - Either failure → re-render the appropriate `*_sync_error` panel

**[VERIFY before implementing]** Is `StackStatsChannel` currently push or poll?
Confirm before wiring stack push. If poll, convert to push as part of this work.

---

## 8. Phase wave plan

### Wave A — Mocked layout (no real API yet)

- Build the channel detail page layout against a `Channels::MockData.*` service
  module
- Pages: index (list of channels), show (channel detail with all sections),
  revoke flow (use existing `Channels::BulkRevokesController` + UI buttons)
- All sections pre-populated with real-shape but mocked values
- User validates the layout end-to-end before any API wiring

### Wave B — Real API wiring

- Replace `Channels::MockData.*` with `Channels::Stats.*` real query layer
- Activate existing `ChannelAnalyticsSync` + add new `ChannelDataSync` jobs
- Wire `Channel#sync!` orchestration
- Add new schema columns (`data_syncing`, `analytics_syncing`, etc.)
- Drop unused schema columns (`country`, `default_language`, etc.) via migration
- Drop `star` cascade (all reference sites)
- Add multi-channel picker UI replacing auto-add

### Wave C — Channel-rollup analytics tables (fill `NotImplementedError` stubs)

- `channel_daily_by_country` table +
  `Youtube::AnalyticsClient#channel_geography` wiring
- `channel_demographics` table + `#channel_demographics` wiring
- `channel_daily_by_device_type` table + new method
- `channel_daily_by_traffic_source` table + new method
- `channel_viewer_time_buckets` table + new method

### Wave D — Cross-report queries (ADR 0011 — backfill NULL columns)

- Impressions report → fills `video_thumbnail_impressions` +
  `video_thumbnail_impressions_click_rate`
- Card-performance report → fills `card_*` columns

### Wave E — Trend deltas

- Add `*_trend_28d_pct` columns on `channel_window_summaries`
- Compute via two-window queries (current vs prior 28d)
- Render direction badge

### Wave F — Spec reactivation + factory updates + system-spec debt sweep

- Reactivate channel specs (audit which exist; drop dead ones from earlier
  deletions like `channel_revoke_spec.rb`)
- Add new specs for `ChannelDataSync`, `ChannelAnalyticsSync`, `Channel#sync!`,
  the picker UI, Live Updates broadcasts
- Update `spec/factories/channels.rb` to match the new column set (drop unused
  columns, add the new ones)
- Engage the system-spec debt cluster from
  `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` (the 2
  TODO-skipped `games_index` examples + any other carry-overs)

### Wave G — Navbar + keybindings reactivation

- Reactivate `/channels` in `config/keybindings.yml` (currently dropped)
- Convert `[channels]` navbar entry from currently-live to active link (already
  a link — verify routing)
- Add channel-specific `page_actions` (sync data, sync analytics, etc.)

---

## 9. Open follow-ups (captured for next session)

- **The 8 Studio-only dropped items** — document in the channel detail page
  footer:
  `For advanced audience insights see YouTube Studio (mobile or web). Pito surfaces the metrics the public API exposes.`
- **`[VERIFY]` items from the YouTube API audit** (creatorContentType GA, etc.)
  — the architect verifies live before specing the affected wave.
- **Multi-channel unified dashboard** — user's stated long-term goal of "combine
  my multiple channels into a unified dashboard". Out of scope this phase but
  key context for design decisions (e.g., the picker UX should make adding ALL
  channels as easy as one click).
- **StackStatsChannel push/poll verification** (Live Updates dependency).
- **`[-]` destructive action target** — Wave A1 confirmed `[-]` is destructive
  (red-styled per design.md hard rule). The actual delete flow (URL,
  confirmation page, bulk-ids shape) stays TBD beyond Wave A1; Wave A1 ships a
  placeholder href="#". Wire to the existing `/deletions/channels/:ids`
  framework (per CLAUDE.md bulk-as-foundation) when the wired-up handler slice
  arrives.

---

## 10. Next-session entry points

1. Read this HANDOFF doc end-to-end.
2. Read `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` for the
   deferred spec debt that Wave F engages.
3. Read `docs/realignment-2026-05-09.md` Unit 3 for the foundational context.
4. Architect spec: open `docs/plans/beta/<next-phase-NN>-channels-revamp/` and
   write the Wave A spec first (mocked layout — fastest path to user feedback).
5. Run `bin/test all 2>&1 | tee /tmp/test-mega.log` to confirm starting-state
   green (after running `bin/parallel_setup` post-migration).

---

## Implementation plan

Concrete wave breakdown for the /channels phase. **/channels is the ONLY
channels route this phase — a single-page combined dashboard**, NOT a multi-pane
workspace.

### Wave A1 layout (locked 2026-05-19, user) — supersedes the original sketch below for the first iteration

**Title bar row:** `channels [+][-]` — destructive red on `[-]` per design.md
hard rule. Both bracketed; both placeholder href="#" for Wave A.

**Below the title bar — left column = two filter chip rows, right column =
channel avatar shelf:**

```
channels  [+][-]
[ ] 7d [ ] 28d [ ] 3m [ ] 365d [ ] alltime                              [ ]|   | [ ]|   | [ ]|   |
[ ] 2025 [ ] 2026 [ ] Apr [ ] May                                          |___|    |___|    |___|
─────────────────────────────────────────────────────────────────────────────────────────────────  (hairline)
```

- **Chip row 1 (time windows):**
  `[ ] 7d  [ ] 28d  [ ] 3m  [ ] 365d  [ ] alltime`
- **Chip row 2 (calendar):** `[ ] 2025  [ ] 2026  [ ] Apr  [ ] May`
- **Avatar shelf (right):** each channel renders as `[ ]` checkbox + circular
  avatar (`border-radius: 50%`, per design.md "Channel avatars" subsection).
  - Avatar size: **2× chip-row text line-height + the inter-row gap** — the
    avatar spans BOTH chip rows vertically. The underlying tile is square (width
    = height) and the circle is applied via `border-radius: 50%`.
  - Checkbox sits row-1-aligned (next to the avatar's top edge).
  - Match the chip text + gap from `app/components/games/filter_row_component.*`
    so the avatar height tracks any future chip-row sizing change.
- **Hairline** below the title+chips+avatars block (existing visual rule).
- **Below the hairline:** ID-card shelf — one `Channels::IdCardComponent` per
  active channel inside a headless `ShelfComponent` row. Card shape locked
  2026-05-19 (see "ID card dimensions" below). Beneath the shelf, the main
  content area is blank for Wave A1 (subsequent A-steps fill the metric
  sections).

**ID card dimensions (locked 2026-05-19, after several iterations).** Diverges
from the original ISO/IEC 7810 ID-1 (1.586:1) sketch.

- **Outer card:** **158 px tall × 314 px wide** (landscape). 25% wider than the
  prior ISO ID-1 footprint at the same height; the extra 63 px flows entirely
  into the right column.
- **Border:** 1px `var(--color-cover-border)`, 2 px radius.
- **Background:** `var(--color-channel-id-card-bg)` — theme-aware, `#eef0f3`
  light / `#2f3142` dark. Values copied from `--color-pane-bg-a` for surface
  parity; the token is **independent** so future tweaks decouple.
- **Left column:** **125 px fixed** (`flex-shrink: 0`). Avatar + handle. Extends
  through the full body height; the in-body footer hairline and footer live in
  the right column only.
- **Right column:** **189 px flex** (auto-expand). 3-row stat grid + footer.
- **Avatar (inside card):** **105 px square**, `border-radius: 50%`,
  `aspect-ratio: 1/1`, `flex-shrink: 0`. Circle treatment per design.md
  §"Channel avatars".
- **Name row:** 13 px body bold, `padding: 6px 8px`, CSS ellipsis on overflow.
- **Stat grid:** `grid-template-columns: 1fr auto auto` (number / unit / arrow),
  `column-gap: 6px`. Number cell `justify-self: end`, unit cell
  `justify-self: start`, arrow cell `justify-self: end` with ~6 px right padding
  so the three arrows align at the card's right edge. Stat font-size 13 px with
  `font-variant-numeric: tabular-nums`.
- **Footer:** **right-column only.** Hairline + footer copy live inside the
  right-column wrapper so the left column extends down through where the
  full-width footer would have spanned. Footer content: single
  `[YouTube Studio]` `BracketedLinkComponent` link in the bottom-right corner,
  pointing at `https://studio.youtube.com/channel/<youtube_channel_id>`. The
  brand-names-capitalized rule supplies the "YouTube Studio" copy (not
  `[studio]`).

Full design-system entry: `docs/design.md > Channel ID card`.

**Wave A1 chips + checkboxes are INERT visual placeholders** — no Stimulus
controller, no checked-state toggle, no URL persistence. The "no real actions"
rule applies. Toggle/persistence land in later A-steps once the visual is signed
off. The ID-card shelf is also inert — both the handle link and
`[YouTube Studio]` link are the only interactive surfaces on each card.

**ID-card shelf reinstated 2026-05-19.** The handoff's original A3b
"channel-card shelf below title bar" was briefly dropped in favor of an
avatar+checkbox right-shelf, but the iteration converged on a dedicated
landscape ID card after several rounds of refinement (card-shape locked above).
The card is now the canonical per-channel summary; the avatar shelf in the
title-bar right column stays as the channel-filter UI and the ID-card shelf
beneath the hairline is the rich render.

**Phase folder:** `docs/plans/beta/37-channels-revamp/` (next free number after
`36-web-app-freeze`).

**Keybinding (locked):** `C` as a direct root-menu entry in
`config/keybindings.yml#menus.root.items`, parallel to `S → /settings`. Capital
= navigation per the file's convention.

### Layout model (locked)

```
┌─────────────────────────────────────────────────────────────────┐
│ channels  [+][-]              [ ] c1  [ ] c2  [ ] c3            │  ← title bar
├─────────────────────────────────────────────────────────────────┤
│ [c1 card]  [c2 card]  [c3 card]                                 │  ← channel-card shelf
├─────────────────────────────────────────────────────────────────┤  ← hairline
│ "Hell on Earth" — all data, charts, aggregations                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Two distinct chrome surfaces:

1. **Title bar** — `channels [+][-]` on the LEFT, filter chips
   `[ ] c1 [ ] c2 ...` on the RIGHT (same chip pattern as /games platform
   chips). Each chip toggles ONE channel ON/OFF for the dashboard's combined
   data view.
   - `[+]` = add channel (opens OAuth picker modal)
   - `[-]` = TBD action ("new way of doing stuff" — user-locked as design-time
     discovery, NOT a feature for Wave A; placeholder only)
2. **Channel-card shelf** — channel cards (avatar + name + handle; exact card
   shape TBD at layout time). **Banner explicitly NOT displayed here** ("banner
   is for something else" — stays in schema, fetched during `ChannelDataSync`,
   dormant until a future use case is identified).
3. **Hairline** below the shelf.
4. **"Hell on Earth" main content** — all metric sections (basics totals, Top
   Content, window summaries, audience breakdowns, traffic sources, heatmap,
   trends). Each section's combine-vs-split-vs-both is decided at layout time.

**Chip ↔ card interaction (default):** unchecking a chip hides that channel's
card from the shelf AND drops its data from aggregations below. Same semantics
as /games platform chip filtering. (Confirm or push back at layout time.)

**Combine vs split per section** is decided at layout time:

- Some sections sum (subs, views, watch time, video count)
- Some weighted-average (CTR, avg view duration)
- Some render union with channel-of-origin badges (Top Content)
- Some render per-channel slices side-by-side (audience demographics, day×hour
  heatmaps)
- Some render both (e.g., aggregated bar + per-channel breakdown)

**No breadcrumb.**

**Channel filter persistence:** URL query param `?channels=id1,id2,id3` (matches
/games filter pattern + makes the dashboard URL shareable).

### Scope simplifications (locked post-HANDOFF-draft)

- **No `/channels/:id` detail page** — `/channels` is the ONLY route
- **FriendlyId teardown for Channel** — drop `friendly_id` declaration, drop
  `url_slug` method, drop `to_param` custom override, drop `Channel.friendly`
  finder. `friendly_id_slugs` polymorphic history table stays (used by other
  models like Game)
- **Sub-controllers dropped entirely:**
  - `Channels::AnalyticsController` — the body's query layer (`Analytics::*`
    services) gets called directly from the dashboard sections; the controller
    goes away
  - `Channels::AnalyticsRefreshController` — folded into manual sync UI
  - `Channels::ChangeLogsController` — change log dropped (no edits happen on
    read-only mirror)
  - `Channels::StarsController` — already dropping with star
  - Nested `:videos` action — dropped
- **`channel_change_logs` table** — drop in migration
- **Multi-pane workspace pattern** — NOT used in /channels this phase. SavedView
  code (`SavedView.channels` scope, panes URL, pane picker modal, friendly-URL
  resolution for panes) STAYS in the codebase for potential reuse in /videos
  later, but is **dormant** for /channels.
- **Channel toggle filter** is a new mechanism (URL query param), not the
  existing SavedView system.

### Wave A — Mocked dashboard layout (1-2 sessions)

Layout-first per the way-of-work rule. User validates visuals + decides
combine-vs-split per section as work progresses.

**Wave A1 superseded sketch** — see "Wave A1 layout (locked 2026-05-19, user)"
in the Implementation plan section below. The A3a/A3b/A4 row entries in the
table below are now historical sketch — implementation follows the locked block.

| Step | Scope                                                                                                                                                                                                                                                             |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1   | `/channels` dashboard shell (top shelf area + main content area + scaffolding for filter persistence)                                                                                                                                                             |
| A2   | `Channels::MockData` service module — single source for mock data: per-channel hashes + aggregated rollups for each metric                                                                                                                                        |
| A3a  | Title bar — `channels [+][-]` on the LEFT, filter chips `[ ] c1 [ ] c2 ...` on the RIGHT (same chip pattern as /games platform chips). `[+]` opens OAuth picker modal; `[-]` is a placeholder for the TBD action (no Wave A handler — design-time discovery only) |
| A3b  | Channel-card shelf below title bar — cards for each currently-selected channel (avatar + name + handle; exact card shape TBD at layout time). **Banner NOT rendered here.** Mocked: 3-5 channels                                                                  |
| A4   | Channel filter URL persistence — `?channels=id1,id2,id3` query param via Stimulus controller (similar to /games filter chips). Chip uncheck → hide card + drop data from aggregations                                                                             |
| A5   | Basics section: aggregated totals across selected channels (total subs / total views / total videos / total watch time hrs)                                                                                                                                       |
| A6   | Top Content section: union-merged ranked list across selected channels, each row badged with channel-of-origin                                                                                                                                                    |
| A7   | Window summaries section: tabs (7d / 28d / 90d / 365d / lifetime), aggregated metrics for the time window                                                                                                                                                         |
| A8   | Trend indicators section: rising/steady/dropping arrows + numeric deltas for the trio (subs / views / watch time) — display style TBD at this point                                                                                                               |
| A9   | Audience geography section: combined country breakdown across selected channels (or per-channel side-by-side — design choice at layout time)                                                                                                                      |
| A10  | Audience demographics (age × gender): aggregated viewer percentage OR per-channel side-by-side (design choice at layout time)                                                                                                                                     |
| A11  | Device Type breakdown                                                                                                                                                                                                                                             |
| A12  | When your viewers are on YouTube heatmap (day × hour)                                                                                                                                                                                                             |
| A13  | Traffic sources section (find-your-videos breakdown + external + search terms top-N capped)                                                                                                                                                                       |
| A14  | Latest content shelf — 5 latest uploads merged across selected channels (chronological), each badged with channel-of-origin                                                                                                                                       |
| A15  | Sync buttons + state UI per channel chip on the top shelf (data + analytics)                                                                                                                                                                                      |
| A16  | Multi-channel picker modal (the `[+]` button target — mocked discovered-channels list)                                                                                                                                                                            |
| A17  | Revoke flow UI buttons → wire to existing `Channels::BulkRevokesController` (mock the response)                                                                                                                                                                   |
| A18  | User validation gate — layout locked once signed off                                                                                                                                                                                                              |

### Wave B — Real API wiring (2-3 sessions)

| Step | Scope                                                                                                                                                                                                                                                                                                                                                     |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| B1   | Migration: drop unused Channel columns (`country`, `default_language`, `handle_changed_at`, `title_changed_at`, `hidden_subscriber_count`, `watermark_*`, `links`, `star`, `last_synced_at`). **`banner_url` STAYS** — fetched during `ChannelDataSync` but not displayed on the dashboard (banner is reserved for a future use case TBD; dormant column) |
| B2   | Migration: add new Channel columns (`data_synced_at`, `analytics_synced_at`, `data_syncing`, `analytics_syncing`, `data_sync_error`, `analytics_sync_error`)                                                                                                                                                                                              |
| B3   | Migration: drop `channel_change_logs` table + `ChannelChangeLog` model                                                                                                                                                                                                                                                                                    |
| B4   | FriendlyId teardown on Channel (declaration, methods, override, finder)                                                                                                                                                                                                                                                                                   |
| B5   | Drop sub-controllers + their views (Analytics, AnalyticsRefresh, ChangeLogs, Stars) + their routes                                                                                                                                                                                                                                                        |
| B6   | Drop `:show` route + action + view + partials                                                                                                                                                                                                                                                                                                             |
| B7   | Star cascade removal — `.starred` scope, `enqueue_sync_on_star` callback, sort/filter on index, any star UI                                                                                                                                                                                                                                               |
| B8   | New `ChannelDataSync` job class — `channels.list?part=snippet,statistics,brandingSettings,contentDetails` upsert                                                                                                                                                                                                                                          |
| B9   | Refactor `ChannelAnalyticsSync` — split-mutex shape (`analytics_syncing` + `analytics_sync_error`)                                                                                                                                                                                                                                                        |
| B10  | `Channel#sync!(scope:)` orchestrator — enqueues data/analytics/both based on scope arg                                                                                                                                                                                                                                                                    |
| B11  | `Channels::Aggregator` service — combine-rule logic per metric type (sum / avg / union / split). Each section component calls a method like `Channels::Aggregator.subscribers_total(channel_ids)`                                                                                                                                                         |
| B12  | Wire real data layer replacing `Channels::MockData.*` — constant swap at view layer, OR aggregator returns the section component's hash                                                                                                                                                                                                                   |
| B13  | Multi-channel picker UI wiring — replace auto-add in `YoutubeConnections::OauthCallbacksController` with picker modal                                                                                                                                                                                                                                     |
| B14  | Daily CRON via sidekiq-cron — `Channel.find_each { ChannelDataSync + ChannelAnalyticsSync }` (2N parallel jobs)                                                                                                                                                                                                                                           |
| B15  | StackStatsChannel push/poll verification + conversion to push if currently poll (Live Updates dependency)                                                                                                                                                                                                                                                 |
| B16  | Live Updates broadcast hooks — after each sync job → `Turbo::StreamsChannel.broadcast_replace_to` against affected section DOM ids (re-render aggregated sections for selected channels)                                                                                                                                                                  |

### Wave C — Channel-rollup tables (1-2 sessions)

Fill the existing `NotImplementedError` stubs in `Youtube::AnalyticsClient`.
These power the aggregator service for the audience/traffic/device/heatmap
sections.

| Step | Table + method                                                                                     |
| ---- | -------------------------------------------------------------------------------------------------- |
| C1   | `channel_daily_by_country` table + `Youtube::AnalyticsClient#channel_geography` (uncomment + wire) |
| C2   | `channel_demographics` table + `#channel_demographics` (ageGroup × gender)                         |
| C3   | `channel_daily_by_device_type` table + new method                                                  |
| C4   | `channel_daily_by_traffic_source` table + new method (top-N caps for high-cardinality detail rows) |
| C5   | `channel_viewer_time_buckets` table + new method (day × hour heatmap, UTC bucket + user-tz rollup) |
| C6   | Wire each into the `Channels::Aggregator` service + render in the corresponding dashboard section  |

### Wave D — Cross-report queries (1 session, ADR 0011 backfill)

| Step | Scope                                                                                                                                                |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| D1   | Impressions report `reports.query` → backfill `video_thumbnail_impressions` + `video_thumbnail_impressions_click_rate` columns (existing NULL today) |
| D2   | Card-performance report `reports.query` → backfill `card_*` columns                                                                                  |
| D3   | Render impressions + CTR + card metrics in the dashboard's window summary section                                                                    |

### Wave E — Trend deltas (1 session)

| Step | Scope                                                                                                                                 |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------- |
| E1   | Migration: add `subscriber_count_trend_28d_pct`, `view_count_trend_28d_pct`, `watch_time_trend_28d_pct` to `channel_window_summaries` |
| E2   | Compute during `ChannelAnalyticsSync`: two-window query (current 28d vs prior 28d), delta % stored as numeric                         |
| E3   | Aggregator method `Channels::Aggregator.trend(metric, channel_ids)` — combine deltas across selected channels                         |
| E4   | Render direction badges / numbers in the dashboard's trend section                                                                    |

### Wave F — Spec reactivation + factory updates + system-spec debt sweep (1-2 sessions)

| Step | Scope                                                                                                                                                           |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1   | Audit existing channel specs — drop dead ones (channel_revoke, change_logs, show.html specs gone with controllers, friendly URL tests gone)                     |
| F2   | Update `spec/factories/channels.rb` — match new column set (drop dropped columns, add new ones)                                                                 |
| F3   | Write specs for `ChannelDataSync`, `ChannelAnalyticsSync`, `Channel#sync!` orchestration                                                                        |
| F4   | Write specs for `Channels::Aggregator` service (per-metric combine rules)                                                                                       |
| F5   | Write specs for multi-channel picker UI flow                                                                                                                    |
| F6   | Write specs for Live Updates broadcast hooks                                                                                                                    |
| F7   | Write specs for the channel filter URL persistence (`?channels=...`)                                                                                            |
| F8   | Engage system-spec debt cluster — the 2 TODO-skipped `games_index_spec.rb:25, 65` examples (genre nested-shelf headings) — investigate + fix or formally retire |
| F9   | Add specs for Wave C channel-rollup tables (each new table + method)                                                                                            |
| F10  | Add specs for Wave D cross-report queries (mock API responses, assert backfill columns get populated)                                                           |
| F11  | Add specs for Wave E trend deltas (two-window computation + storage + aggregation)                                                                              |

### Wave G — Reactivation + closeout (1 session)

| Step | Scope                                                                                                                              |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------- |
| G1   | Reactivate `/channels` in `config/keybindings.yml` (currently dropped from leader-menu navigation)                                 |
| G2   | Convert `[channels]` navbar entry from currently-muted to active link (helper kwarg flip)                                          |
| G3   | Add channel-specific page_actions (`s d` = sync data of selected channels, `s a` = sync analytics, `f` = focus filter shelf, etc.) |
| G4   | Final visual validation pass — confirm dashboard render is stable + Live Updates broadcasts work end-to-end                        |
| G5   | Phase log entry + scope-drift bookkeeping (`additions.md` / `dropped.md` per beta convention)                                      |
| G6   | User validation gate before commit + push                                                                                          |

### Dependency / ordering notes

- **Wave A is the longest** because layout-first means iterating on each
  section + deciding combine-vs-split per metric. Expect 1-2 sessions of layout
  polish before user signs off.
- **Wave B depends on Wave A completion** — don't wire real data until layout is
  locked.
- **Wave C/D/E can be sequenced any order** after Wave B lands — they're
  independent table/column additions.
- **Wave F starts late** — specs after the surface stops moving. Per the user's
  way-of-work rule.
- **Wave G is last** — keybindings/navbar reactivation only after everything
  else stabilizes.

### Estimated session count: 7-10 sessions

Wave A: 1-2 / Wave B: 2-3 / Wave C: 1-2 / Wave D: 1 / Wave E: 1 / Wave F: 1-2 /
Wave G: 1

### Design-time decisions flagged for Wave A architect

1. **Aggregation rules per metric** — discover during layout iteration
2. **Channel filter URL shape** — lean is `?channels=id1,id2,id3`
3. **Section combine-vs-split-vs-both** — per-section decision at layout time
4. **Top shelf chip design** — avatar + name + checkbox shape, or alternate
5. **`[+]` button position** — top-right of shelf? inline with last channel?
   Trailing element?
6. **Trend indicator display** — arrows / numbers / both / micro-bars

---

## Test verification (2026-05-19 closeout)

Full `bin/test all` run completed cleanly before this handoff:

- **9361 examples, 0 failures, 2 pendings**
- Wall time: 23:07
- All 8 parallel workers green (1330 + 1174 + 1287 + 1049 + 1140 + 1228 +
  1064 + 1089)

The 2 pendings are TODO-skipped in `spec/system/games_index_spec.rb:25, 65`
(genre nested-shelf headings — SF3 agent's static read said the assertions
should pass but didn't want to guess-rewrite). Documented in:

- `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` (Cluster 4 —
  /games revamp drift)
- `feedback_dont_touch_games` memory entry (re-engagement deferred until /games
  surface stabilizes)

Re-engage these 2 TODO-skips during Wave F of the /channels phase (when the spec
consolidation pass naturally touches the system-spec layer anyway), OR sooner if
you spot the actual genre-rendering issue during /channels work.

### Known deprecation noise

9 `ostruct.rb` warnings from the Ruby 3.4.9 standard library — not actionable
today (Ruby 4.0 stdlib drop advance warning). Worth adding `ostruct` to the
Gemfile when Ruby 4.0 lands, but no action needed for the /channels phase.

---

## Footer

- Date: 2026-05-19
- Author: Master agent + user planning session
- Pair docs:
  - `docs/orchestration/follow-ups.md` (Live Updates entry + /channels
    next-phase scope entry)
  - `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md`
  - `docs/realignment-2026-05-09.md`
