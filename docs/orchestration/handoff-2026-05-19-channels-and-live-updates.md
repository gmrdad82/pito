# Handoff — /channels revamp + Live Updates feature

**Date:** 2026-05-19
**Author:** Master agent + user planning session
**Pair docs:**

- `docs/orchestration/follow-ups.md` (Live Updates entry + /channels next-phase
  scope entry — already captured, do not re-edit from here)
- `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` (deferred spec
  debt to engage in Wave F)
- `docs/realignment-2026-05-09.md` Unit 3 (foundational direction for the
  /channels surface)

This document is the architect-spec-ready foundation for the next session's
work on /channels and the Live Updates feature. Read it end-to-end before
opening any plan / spec files.

---

## 1. Way of work (locked)

These three rules govern the entire phase. Re-read at the start of every
dispatch:

- **Layout-first with mocked data.** The page is revamped step-by-step against
  mocks — real-shape but fake values via a `Channels::MockData.*` service
  module. Implementation swap to real data happens ONLY after the user
  validates the visual layout end-to-end. This is the iteration loop, not a
  shortcut.
- **No RSpec during the layout phase.** Specs are a dedicated consolidation
  pass after the user signs off on visuals. Iteration agents write code only;
  spec writing is its own wave.
- **No write operations on channels.** /channels is a read-only YouTube mirror
  this phase. The single exception is channel removal (revoke), which already
  exists via `Channels::BulkRevokesController`. No description editing, no
  banner upload, no metadata mutation surface of any kind.

---

## 2. /channels scope — IN / OUT

### IN — channel basics (lifetime)

| Field          | Source                                                                   | Notes                                       |
| -------------- | ------------------------------------------------------------------------ | ------------------------------------------- |
| name           | `channels.title`                                                         |                                             |
| handle         | `channels.handle`                                                        |                                             |
| channel URL    | `channels.channel_url`                                                   |                                             |
| Studio URL     | derived helper: `"https://studio.youtube.com/channel/#{youtube_channel_id}"` | no new column                            |
| avatar         | `channels.avatar_url`                                                    | same asset family as thumbnail              |
| banner         | `channels.banner_url`                                                    | readonly mirror                             |
| subscribers    | `channels.subscriber_count`                                              |                                             |
| views lifetime | `channels.view_count`                                                    |                                             |
| watch time hrs | Analytics API `estimatedMinutesWatched`                                  | renderer divides by 60                      |
| videos count   | `channels.video_count`                                                   | YouTube count, NOT pito-imported count      |
| joining date   | `channels.published_at`                                                  | render as date + days-since                 |

### IN — analytics (Wave A and B)

- Top Content — filtered to `creatorContentType==VIDEO_ON_DEMAND` (no Shorts,
  no Lives; user only ships Videos)
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
  schema-ADD section below). Display TBD at design time (arrows / text / both
  — open question for the spec).

### OUT — explicitly dropped this phase

- `star` concept entirely (drop column + scope + controller + route + callback
  + sort + filter + view + all references)
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

- `description`
- `country`
- `default_language`
- `handle_changed_at`
- `title_changed_at`
- `hidden_subscriber_count`
- `watermark_url`, `watermark_timing`, `watermark_offset_ms`
- `links` (jsonb array)
- `keywords` (text)
- `star` (boolean — and every reference site: scope, controller, route,
  callback, sort, filter, view, navbar pin, keybinding)
- `last_synced_at` (replaced by the split pair — see ADD section)

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
audit lives inline below rather than in a side playbook this phase; if it
grows, the architect breaks it out into
`docs/orchestration/playbooks/youtube-api-mapping-channels-phase-2026-05-19.md`
as a side deliverable when the Wave B spec is written.

### Summary table (in-scope items → API surfaces)

| Surface                              | API                                          | Notes                                      |
| ------------------------------------ | -------------------------------------------- | ------------------------------------------ |
| name, handle, avatar, video_count    | Data API `channels.list?part=snippet,statistics,brandingSettings` |                  |
| banner                               | `brandingSettings.image.bannerExternalUrl`   | readonly                                   |
| subscribers, views                   | `statistics.subscriberCount`, `viewCount`    |                                            |
| watch time hours lifetime            | Analytics API `estimatedMinutesWatched`      | MINUTES — divide by 60 at render           |
| Top Content                          | Analytics API top-videos report, filter `creatorContentType==VIDEO_ON_DEMAND` | **[VERIFY GA]**          |
| traffic-source breakdown             | Analytics API dim `insightTrafficSourceType` |                                            |
| YT search terms                      | `insightTrafficSourceDetail` filtered to `YT_SEARCH` | top-N capped                       |
| audience geography                   | dim `country`                                |                                            |
| watch time from subs                 | dim `subscribedStatus`                       |                                            |
| formats                              | dim `creatorContentType`                     |                                            |
| gender / age                         | dim `gender,ageGroup`                        |                                            |
| device type                          | dim `deviceType`                             |                                            |
| viewer time heatmap                  | dim `day,hour`                               | day x hour                                 |
| impressions + CTR                    | impressions report (Wave D cross-report)     | ADR 0011 — currently NULL on summaries     |

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

This is the path the long-term "unified dashboard across my channels" goal
flows through — the picker UX should make adding ALL channels as easy as one
click.

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
2026-05-19) ships ALONGSIDE the /channels work in this phase. Four
sub-features:

1. **Client-side relative-time ticker** — every `~Xs ago` / `~Xm ago` label
   ticks itself. Stimulus controller, cadence-aware downshift (per-second
   under 1m → per-minute under 1h → per-hour beyond).
2. **Sessions table push** — out of /channels scope but in this phase since
   Live Updates is being built once. Via ActionCable on `Session`
   `after_create_commit` / `after_update_commit` / `after_destroy_commit`.
3. **Stack tables push** — `/settings` Postgres / Meilisearch / Voyage AI /
   assets / notes panes. Out of /channels scope but in this phase.
4. **NEW: /channels detail page push** — when `ChannelDataSync` or
   `ChannelAnalyticsSync` completes, broadcast updated sections via Turbo
   Stream:
   - Data sync done → re-render basics card (name, avatar, banner, subs,
     views, video count) + `data_synced_at` label
   - Analytics sync done → re-render analytics sections + `analytics_synced_at`
     label
   - Either failure → re-render the appropriate `*_sync_error` panel

**[VERIFY before implementing]** Is `StackStatsChannel` currently push or poll?
Confirm before wiring stack push. If poll, convert to push as part of this
work.

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
- Drop unused schema columns (`description`, `country`, etc.) via migration
- Drop `star` cascade (all reference sites)
- Add multi-channel picker UI replacing auto-add

### Wave C — Channel-rollup analytics tables (fill `NotImplementedError` stubs)

- `channel_daily_by_country` table + `Youtube::AnalyticsClient#channel_geography`
  wiring
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
- Add new specs for `ChannelDataSync`, `ChannelAnalyticsSync`,
  `Channel#sync!`, the picker UI, Live Updates broadcasts
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
  `For advanced audience insights see YouTube Studio (mobile or web). Pito
  surfaces the metrics the public API exposes.`
- **`[VERIFY]` items from the YouTube API audit** (creatorContentType GA, etc.)
  — the architect verifies live before specing the affected wave.
- **Multi-channel unified dashboard** — user's stated long-term goal of "combine
  my multiple channels into a unified dashboard". Out of scope this phase but
  key context for design decisions (e.g., the picker UX should make adding ALL
  channels as easy as one click).
- **StackStatsChannel push/poll verification** (Live Updates dependency).

---

## 10. Next-session entry points

1. Read this HANDOFF doc end-to-end.
2. Read `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` for the
   deferred spec debt that Wave F engages.
3. Read `docs/realignment-2026-05-09.md` Unit 3 for the foundational context.
4. Architect spec: open `docs/plans/beta/<next-phase-NN>-channels-revamp/` and
   write the Wave A spec first (mocked layout — fastest path to user
   feedback).
5. Run `bin/test all 2>&1 | tee /tmp/test-mega.log` to confirm starting-state
   green (after running `bin/parallel_setup` post-migration).

---

## Test verification (2026-05-19 closeout)

Full `bin/test all` run completed cleanly before this handoff:

- **9361 examples, 0 failures, 2 pendings**
- Wall time: 23:07
- All 8 parallel workers green (1330 + 1174 + 1287 + 1049 + 1140 + 1228 + 1064 + 1089)

The 2 pendings are TODO-skipped in `spec/system/games_index_spec.rb:25, 65`
(genre nested-shelf headings — SF3 agent's static read said the assertions
should pass but didn't want to guess-rewrite). Documented in:

- `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md` (Cluster 4 — /games revamp drift)
- `feedback_dont_touch_games` memory entry (re-engagement deferred until /games surface stabilizes)

Re-engage these 2 TODO-skips during Wave F of the /channels phase (when the
spec consolidation pass naturally touches the system-spec layer anyway), OR
sooner if you spot the actual genre-rendering issue during /channels work.

### Known deprecation noise

9 `ostruct.rb` warnings from the Ruby 3.4.9 standard library — not actionable today (Ruby 4.0 stdlib drop advance warning). Worth adding `ostruct` to the Gemfile when Ruby 4.0 lands, but no action needed for the /channels phase.

---

## Footer

- Date: 2026-05-19
- Author: Master agent + user planning session
- Pair docs:
  - `docs/orchestration/follow-ups.md` (Live Updates entry + /channels
    next-phase scope entry)
  - `docs/orchestration/playbooks/system-spec-debt-2026-05-19.md`
  - `docs/realignment-2026-05-09.md`
