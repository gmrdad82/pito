# Phase 13.3 — Analytics Dashboard

> **Status:** dispatched 2026-05-10. Single-lane: **rails**. Third of three
> specs in Phase 13. Builds on spec 01 (data model) + spec 02 (sync engine),
> both assumed landed.
>
> **Cross-references:**
>
> - `docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md` — every
>   chart enumerated below traces back to a Note 3 query (C1-C5, V1-V8) plus the
>   cross-video locals from §"Cross-video questions (computed locally)."
> - `docs/realignment-2026-05-09.md` — work unit 5.
> - `docs/plans/beta/13-analytics-sync-engine/specs/01-analytics-data-model.md`
>   — every analytics table read here is defined there.
> - `docs/plans/beta/13-analytics-sync-engine/specs/02-analytics-sync-engine.md`
>   — populates every table read here; spec 02's "refresh" entry-points wire the
>   on-demand button surfaces declared below.
> - `docs/design.md` — chart conventions: no animation, no red, crosshair on
>   line charts, bracketed colored legend labels, monospace 13px.
> - `app/components/bracketed_link_component.rb` — bracketed link convention.
> - `CLAUDE.md` — top-level rules (no JS confirm; bracketed link on every
>   clickable; cursor pointer; charts no-animation no-red).

## Goal

Render every analytics surface enumerated in Note 3 as a Hotwire-driven
dashboard. Channel-level summary, channel-level time-series, top-videos
leaderboards, per-video drilldown (time-series, retention curve, country /
device / OS / traffic-source / subscribed-status / demographics breakdowns), and
the four cross-video local rollups (when-to-publish, best-duration,
topics-that-work, thumbnail-decay).

Studio-faithful ratios (the four non-summable metrics) come from the
`*_window_summary` tables — never from `video_daily` SUMs. Dashboard surfaces
that show ratios always pull from window summaries.

The dashboard piggy-backs on existing pane workspaces (Channels / Videos pages)
where natural and gets a dedicated Analytics workspace where it needs more
screen real estate.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                                       |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Workspace placement.** A new top-level `/analytics` workspace renders the channel summary + cross-channel surfaces. The per-channel detail page (`/channels/:id`) gains an Analytics tab/section; ditto `/videos/:id`. The `/analytics` URL is the headline entry; the per-resource pages are the drill-in.                                                                                                  |
| Q2  | **Charts library.** Chartkick + Groupdate + Chart.js per CLAUDE.md tech stack. `gem "chartkick"` + `gem "groupdate"` already vendored.                                                                                                                                                                                                                                                                         |
| Q3  | **Studio-faithful ratios from window summaries.** Charts that show `averageViewPercentage`, `videoThumbnailImpressionsClickRate`, `cardClickRate`, `cardTeaserClickRate`, `cpm`, `playbackBasedCpm`, `viewerPercentage` read from `*_window_summary` tables. Never derived from `video_daily` SUMs.                                                                                                            |
| Q4  | **Date-range picker.** Four canonical buttons: `[ 7d ]`, `[ 28d ]`, `[ 90d ]`, `[ lifetime ]` matching the four window enum values from spec 01. Custom-range pickers deferred per Note 3 §"Windowing" guidance ("custom user-picked windows ... compute additives from `video_daily` and label with a hint").                                                                                                 |
| Q5  | **Empty-state shape.** Each chart renders an empty state when the underlying table has no rows for the chosen window. Empty-state copy uses the `.caption` style. Empty-state buttons (`[ refresh now ]`) trigger the on-demand sync (spec 02's `VideoAnalyticsSync.perform_async` etc.).                                                                                                                      |
| Q6  | **Loading-state shape.** When a sync is in flight, render the chart with the existing data (if any) overlaid with a loading indicator. The loading indicator uses the `.caption` style + a Stimulus polling controller that refreshes the chart every 5s while a sync is in flight.                                                                                                                            |
| Q7  | **Real-time refresh.** Turbo Streams broadcast from the sync jobs — when a sync job completes, broadcast a `replace` to the corresponding chart partial. Wire the broadcast in spec 02's job `ensure` block. (Spec 02's lane covers the `broadcast_replace_to` call; this spec covers the partial structure.)                                                                                                  |
| Q8  | **Permissions.** No per-user view restrictions. Every authenticated user sees every analytics surface. Per ADR 0003.                                                                                                                                                                                                                                                                                           |
| Q9  | **Pane-aware vs full-page.** The Analytics workspace is full-page (no panes). The per-channel and per-video Analytics tabs render inside their respective pane shells.                                                                                                                                                                                                                                         |
| Q10 | **Crosshair + legend conventions.** Per `docs/design.md` §charts: line charts use crosshair; legend labels use the bracketed colored convention; no animation; no red; `cursor: pointer` on legend toggles.                                                                                                                                                                                                    |
| Q11 | **Last-3-days revision hint.** Charts that show daily time-series render a faint band over the last 3 days with a `.caption` annotation `"data revises for ~48-72h after publish"`. Per Note 3 §"Data freshness UX."                                                                                                                                                                                           |
| Q12 | **Last-sync timestamp.** Each dashboard page shows a `data as of <human-readable timestamp in user's local TZ>` line at the top. Source: `MAX(youtube_api_calls.created_at WHERE outcome = 'ok' AND client_kind = 'analytics_v2')`. Per Note 3 §"Data freshness UX."                                                                                                                                           |
| Q13 | **Monetization columns.** Hidden when `MONETIZATION_ENABLED` (per spec 02 Q10) is false. Render an "monetization not connected" caption + a `[ enable monetization ]` link to a future settings surface (out of scope here — link goes to `#` placeholder + a `.caption` "configuration not yet available").                                                                                                   |
| Q14 | **Cross-video local rollups.** Computed at query time per spec 01 Q14. Four rollups: (a) when-to-publish (median first-7d views by `published_at` day-of-week + hour); (b) best-duration (median 28d views by duration buckets); (c) topics-that-work (median 28d views by `category_id`); (d) thumbnail-decay (per-video CTR over time from `video_window_summary` rolling). Each gets its own chart partial. |
| Q15 | **Channel geography (C4) / channel demographics (C5).** Per spec 02's open question — these have no dedicated tables in spec 01. The dashboard computes them by SUM-aggregating across the channel's videos' slice tables. Studio-faithfulness caveat is in the chart caption: `"summed from per-video data; may differ from Studio's channel report"`.                                                        |

## Migration posture (LOCKED)

**View-layer-only.** No migrations. No model schema changes (the read-side
scopes that spec 01 already declared cover this dispatch's needs). If spec 01's
scopes are missing an angle the dashboard wants, the implementation agent
surfaces — does NOT silently add scopes.

## Files touched

### Routes

- `config/routes.rb`:
  - `resource :analytics, only: :show, controller: "analytics"` → `/analytics`
    (singular) renders the top-level channel-level dashboard.
  - Nested under `resources :channels`:
    `resource :analytics, only: :show, controller: "channels/analytics", as: :channel_analytics`
    → `/channels/:channel_id/analytics`.
  - Nested under `resources :videos`:
    `resource :analytics, only: :show, controller: "videos/analytics", as: :video_analytics`
    → `/videos/:video_id/analytics`.
  - On-demand refresh routes (POST endpoints):
    - `POST /channels/:channel_id/analytics/refresh` →
      `Channels::AnalyticsRefreshController#create`.
    - `POST /videos/:video_id/analytics/refresh` →
      `Videos::AnalyticsRefreshController#create`.
    - `POST /videos/:video_id/analytics/retention/refresh` →
      `Videos::RetentionRefreshController#create`.
  - Each refresh route enqueues the corresponding job per spec 02 and redirects
    back to the analytics page with a `notice`.

### Controllers (new)

- `app/controllers/analytics_controller.rb` — top-level dashboard.
- `app/controllers/channels/analytics_controller.rb` — per-channel.
- `app/controllers/videos/analytics_controller.rb` — per-video.
- `app/controllers/channels/analytics_refresh_controller.rb` — POST → enqueue
  `ChannelAnalyticsSync` + the relevant per-video jobs; redirect.
- `app/controllers/videos/analytics_refresh_controller.rb` — POST → enqueue
  `VideoAnalyticsSync`; redirect.
- `app/controllers/videos/retention_refresh_controller.rb` — POST → enqueue
  `VideoRetentionSync`; redirect.

Each controller honors the existing `Sessions::AuthConcern` pattern (auth
required) and uses standard Rails helpers (`@channel = Channel.find(...)`).

### Views (new)

#### Top-level

- `app/views/analytics/show.html.erb` — full-page dashboard.
  - Header: page title + last-sync timestamp + window picker
    (`[ 7d ] [ 28d ] [ 90d ] [ lifetime ]`).
  - Sections (in order, top-to-bottom):
    1. Cross-channel summary cards (sum of metrics across all connected channels
       for the chosen window).
    2. Channel cards — one per `Channel` with a
       `youtube_connection_id IS NOT NULL`.
    3. Cross-video local rollups (the four from Q14): when-to-publish,
       best-duration, topics-that-work, thumbnail-decay.
  - Each section embeds chart partials (below).

#### Per-channel

- `app/views/channels/analytics/show.html.erb`:
  - Header: channel name + last-sync timestamp + window picker +
    `[ refresh now ]` button.
  - Sections:
    1. Window summary cards — one card per metric (`views`,
       `estimated_minutes_watched`, `subscribers_gained - subscribers_lost`,
       etc.) showing the windowed value from `channel_window_summary`.
    2. Channel daily time-series (line chart) — C1.
    3. Top videos leaderboard (table) — C3 by window.
    4. Channel geography (chart caveat per Q15) — derived from
       `video_daily_by_country` summed.
    5. Channel demographics (chart caveat per Q15) — derived from
       `video_daily_by_age_group_gender` summed.

#### Per-video

- `app/views/videos/analytics/show.html.erb`:
  - Header: video title + last-sync timestamp + window picker +
    `[ refresh now ]` + `[ refresh retention ]` buttons.
  - Sections:
    1. Window summary cards (windowed metrics from `video_window_summary`).
    2. Video daily time-series (line chart) — V1.
    3. Retention curve (line chart) — V7. Empty state with
       `[ refresh retention now ]` if `video_retentions.empty?`.
    4. By country (bar chart) — V3.
    5. By device type (donut/bar chart) — V4-device.
    6. By operating system (donut/bar chart) — V4-os.
    7. By traffic source (bar chart) — V5.
    8. By subscribed status (donut chart) — V6.
    9. Demographics (heatmap or stacked bar) — V8.

### Chart partials (new)

Each chart partial is a self-contained ERB partial that renders a single
Chartkick chart with the design-system styling applied. Total partials:

- `app/views/analytics/_window_picker.html.erb` — the four-button picker.
- `app/views/analytics/_summary_card.html.erb` — single metric card.
- `app/views/analytics/_data_freshness.html.erb` — last-sync timestamp.
- `app/views/analytics/_revision_band_caption.html.erb` — the 3-day
  revision-band caption.
- `app/views/analytics/charts/_channel_daily_line.html.erb` — C1 line.
- `app/views/analytics/charts/_video_daily_line.html.erb` — V1 line.
- `app/views/analytics/charts/_top_videos_table.html.erb` — C3 table.
- `app/views/analytics/charts/_video_retention_line.html.erb` — V7 curve.
- `app/views/analytics/charts/_country_bar.html.erb` — country breakdown.
- `app/views/analytics/charts/_device_donut.html.erb` — device.
- `app/views/analytics/charts/_os_donut.html.erb` — OS.
- `app/views/analytics/charts/_traffic_source_bar.html.erb` — V5.
- `app/views/analytics/charts/_subscribed_status_donut.html.erb` — V6.
- `app/views/analytics/charts/_demographics_heatmap.html.erb` — V8.
- `app/views/analytics/charts/_when_to_publish.html.erb` — local rollup.
- `app/views/analytics/charts/_best_duration.html.erb` — local rollup.
- `app/views/analytics/charts/_topics_that_work.html.erb` — local rollup.
- `app/views/analytics/charts/_thumbnail_decay.html.erb` — local rollup.

Each partial accepts a single local: the source data (an
`ActiveRecord::Relation` or pre-aggregated array). The partial computes the
chart's data inline (ERB scope) and renders the appropriate Chartkick helper
(`line_chart`, `bar_chart`, `pie_chart`, `column_chart`).

### Helpers / decorators (new)

- `app/helpers/analytics_helper.rb`:
  - `format_metric(value, type:)` — renders a number with the right formatting
    (counts → integer, durations → `m:ss`, ratios → `x.xx%`, money → `$x.xx`).
  - `bracketed_legend_color(label, color)` — per design.md.
  - `analytics_window_label(window)` — `'7d'` → `"last 7 days"`, etc.
  - `data_freshness_label(connection_or_global)` — last sync time in user's TZ.
- `app/decorators/analytics/channel_decorator.rb` (Draper, per CLAUDE.md Draper
  plan note in user memory):
  - Wraps a `Channel` with analytics-aware methods (`#window_summary(window)`,
    `#daily_for_window(window)`, etc.) returning the right `*_window_summary` /
    `channel_daily` rows.
- `app/decorators/analytics/video_decorator.rb` — same shape for `Video`.

### CSS / Tailwind

- No new CSS files. Existing design tokens cover everything (charts, cards,
  cells). The Chartkick options are configured via JS overrides — see
  `app/javascript/controllers/analytics_chart_controller.js` (new) — a Stimulus
  controller that applies the no-animation + no-red + crosshair conventions to
  every `data-controller="analytics-chart"` element.

### Stimulus controllers (new)

- `app/javascript/controllers/analytics_chart_controller.js` — applies Chartkick
  options (no animation, crosshair, color palette without red).
- `app/javascript/controllers/analytics_window_picker_controller.js` — drives
  the four-button window picker; updates the URL query string (`?window=7d`);
  triggers a Turbo frame fetch.
- `app/javascript/controllers/analytics_refresh_polling_controller.js` — while a
  sync is in flight (signaled by the controller via a Turbo Stream attribute),
  polls every 5s for the updated chart partial.

### Documentation (post-implementation; dispatched separately to docs-keeper)

- `docs/architecture.md` — append an "Analytics dashboard" section.
- `docs/design.md` — confirm chart conventions remain accurate; add any new
  convention this spec introduces (e.g., the revision-band caption pattern).

These edits are NOT part of the rails-impl dispatch's file scope.

## Color palette (charts)

Per `docs/design.md` § "Charts" (no red ever, monospace 13px). The palette for
chart series (cycled in this order):

1. `#0066cc` (link blue)
2. `#005c00` (forest green)
3. `#7a3e00` (burnt orange)
4. `#3a008a` (deep purple)
5. `#005573` (teal)
6. `#404040` (charcoal)

Avoid red (`#cc0000`) per the hard rule. Empty / loading states use `#cccccc`
(light gray) for skeletons.

The implementation agent confirms the palette against `docs/design.md`'s
existing tokens and proposes additions if needed.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies:

### Routes

- [ ] `GET /analytics` renders the top-level dashboard.
- [ ] `GET /channels/:id/analytics` renders the per-channel dashboard.
- [ ] `GET /videos/:id/analytics` renders the per-video dashboard.
- [ ] `POST /channels/:channel_id/analytics/refresh` enqueues
      `ChannelAnalyticsSync` for the channel + `VideoAnalyticsSync` for its
      active videos; redirects back with notice.
- [ ] `POST /videos/:video_id/analytics/refresh` enqueues `VideoAnalyticsSync`;
      redirects back.
- [ ] `POST /videos/:video_id/analytics/retention/refresh` enqueues
      `VideoRetentionSync`; redirects back.
- [ ] All routes require authentication; logged-out requests redirect to
      `/login`.

### Top-level dashboard

- [ ] Page title `analytics`.
- [ ] Last-sync timestamp renders if any `youtube_api_calls` row exists with
      `client_kind = 'analytics_v2'` and `outcome = 'ok'`.
- [ ] Window picker shows four buttons; clicking switches the URL query string
      (`?window=7d`); the chart partials re-render with the window's data.
- [ ] Cross-channel summary cards render — one per metric (`views`,
      `estimated_minutes_watched`, `net_subscribers`, etc.) — values sum across
      all connected channels for the chosen window.
- [ ] Channel cards render — one per
      `Channel.where.not(youtube_connection_id:     nil)` — each card shows
      headline metrics for the window.
- [ ] Four cross-video local rollups render: when-to-publish, best-duration,
      topics-that-work, thumbnail-decay.

### Per-channel dashboard

- [ ] Page title is the channel name (or fallback to youtube_channel_id until
      Phase 11 lands).
- [ ] Window summary cards render from `channel_window_summary` for the chosen
      window.
- [ ] Channel daily line chart renders from `channel_daily` filtered to the
      window.
- [ ] Top videos leaderboard table renders from `top_videos_window` filtered to
      the channel + window.
- [ ] Channel geography chart renders with the Q15 caveat caption.
- [ ] Channel demographics chart renders with the Q15 caveat caption.
- [ ] `[ refresh now ]` button enqueues the right jobs.

### Per-video dashboard

- [ ] Window summary cards render from `video_window_summary`.
- [ ] Daily line chart renders from `video_daily`.
- [ ] Retention curve renders from `video_retention`. Empty state if no rows.
- [ ] Country bar chart renders from `video_daily_by_country` summed across the
      window.
- [ ] Device donut renders from `video_daily_by_device_type`.
- [ ] OS donut renders from `video_daily_by_operating_system`.
- [ ] Traffic source bar renders from `video_daily_by_traffic_source`.
- [ ] Subscribed status donut renders from `video_daily_by_subscribed_status`.
- [ ] Demographics heatmap renders from `video_daily_by_age_group_gender`.
- [ ] `[ refresh now ]` enqueues V1-V8 for that video.
- [ ] `[ refresh retention ]` enqueues V7 for that video.

### Chart conventions

- [ ] Every chart has `animation: false` (verify via JS console or rendered
      HTML).
- [ ] No chart series uses red (`#cc0000` or any equivalent).
- [ ] Line charts have crosshair enabled.
- [ ] Legend labels use the bracketed colored convention.
- [ ] Every clickable element (buttons, legend toggles, links) has
      `cursor: pointer`.
- [ ] No JS `alert` / `confirm` / `prompt` / `data-turbo-confirm` anywhere in
      the new code.

### Studio-faithfulness

- [ ] Charts that display ratios (`average_view_percentage`, CTR rates, CPM)
      read from `*_window_summary` tables. Verified via grep of view files for
      the column names — they should appear only in partials that source
      `*_window_summary`.
- [ ] No view file SUMs `video_daily.average_view_percentage` (or any ratio)
      across days.

### Empty / loading states

- [ ] When a chart's source table is empty, the partial renders an empty-state
      message + `[ refresh now ]` button.
- [ ] When a sync is in flight, the chart partial renders the existing data with
      a loading caption overlay.

### Monetization

- [ ] When `MONETIZATION_ENABLED` is false (default), revenue cards / sections
      are hidden; an "monetization not connected" caption + a
      `[ enable monetization ]` placeholder link renders in their place.
- [ ] When `MONETIZATION_ENABLED` is true, revenue cards render with values from
      the corresponding columns.

### Tests

- [ ] `bundle exec rspec` passes.
- [ ] Every new test case enumerated below passes.
- [ ] No system spec triggers a real network call.

## Test sweep

Exhaustive coverage. Total enumerated test cases counted at the end.

### Specs to add

#### `spec/requests/analytics_spec.rb`

- **Auth:**
  - `it "redirects to /login when unauthenticated"`.
  - `it "renders 200 when authenticated"`.
- **Window picker:**
  - `it "defaults to ?window=28d when no query string"`.
  - `it "renders 7d / 28d / 90d / lifetime data when the query string matches"`
    — four cases.
  - `it "rejects an unknown window value"` — `?window=14d` → renders the default
    with a flash alert (or 422 — agent picks).
- **Cross-channel summary:**
  - `it "renders cross-channel summary cards summing across connected channels"`.
  - `it "renders zero values when no analytics rows exist"`.
- **Channel cards:**
  - `it "renders one card per connected channel"`.
  - `it "skips channels with youtube_connection_id IS NULL"`.
- **Cross-video local rollups:**
  - `it "renders when-to-publish chart"`.
  - `it "renders best-duration chart"`.
  - `it "renders topics-that-work chart"`.
  - `it "renders thumbnail-decay chart"`.
- **Data freshness:**
  - `it "renders 'data as of <timestamp>' when audit rows exist"`.
  - `it "renders 'never synced' when no audit rows exist"`.

Total: **15** test cases.

#### `spec/requests/channels/analytics_spec.rb`

- **Auth + 404:**
  - `it "redirects to /login when unauthenticated"`.
  - `it "404s on unknown channel id"`.
- **Window summary cards:**
  - `it "renders cards from channel_window_summary for the chosen window"`.
  - `it "renders zero values when channel_window_summary has no rows"`.
- **Channel daily line:**
  - `it "renders the line chart"`.
  - `it "renders the 3-day revision-band caption"`.
  - `it "filters to the chosen window's date range"`.
- **Top videos leaderboard:**
  - `it "renders the table from top_videos_window for the window"`.
  - `it "respects rank ordering"`.
- **Channel geography (caveat):**
  - `it "renders the geography chart with the Q15 caveat caption"`.
  - `it "sums views from video_daily_by_country across the channel's videos"`.
- **Channel demographics (caveat):**
  - `it "renders the demographics chart with the Q15 caveat caption"`.
- **Refresh button:**
  - `it "renders [ refresh now ] button"`.
- **Empty state:**
  - `it "renders empty-state when no channel_window_summary rows exist"`.

Total: **14** test cases.

#### `spec/requests/videos/analytics_spec.rb`

- **Auth + 404:** 2 cases.
- **Window summary cards:** 2 cases (renders / empty).
- **Daily line chart:** 1 case + 1 case for revision band.
- **Retention curve:** 2 cases (renders when rows exist / empty state when no
  rows + `[ refresh retention ]` button).
- **By-country bar:** 1 case.
- **By-device donut:** 1 case.
- **By-OS donut:** 1 case.
- **By-traffic-source bar:** 1 case.
- **By-subscribed-status donut:** 1 case.
- **Demographics heatmap:** 1 case.
- **Refresh buttons:** 2 cases (refresh / retention refresh visible).

Total: **15** test cases.

#### `spec/requests/channels/analytics_refresh_spec.rb`

- `it "redirects to channel analytics with notice on POST"`.
- `it "enqueues ChannelAnalyticsSync"`.
- `it "enqueues VideoAnalyticsSync for each active video"`.
- `it "404s on unknown channel"`.
- `it "redirects to /login when unauthenticated"`.

Total: **5** test cases.

#### `spec/requests/videos/analytics_refresh_spec.rb`

- `it "redirects to video analytics with notice on POST"`.
- `it "enqueues VideoAnalyticsSync"`.
- `it "404s on unknown video"`.
- `it "redirects to /login when unauthenticated"`.

Total: **4** test cases.

#### `spec/requests/videos/retention_refresh_spec.rb`

- `it "enqueues VideoRetentionSync on POST"`.
- `it "redirects with notice"`.
- `it "404s on unknown video"`.

Total: **3** test cases.

#### `spec/system/analytics_dashboard_spec.rb`

System-level (Capybara) for the visual conventions.

- `it "renders the four-button window picker with bracketed labels"`.
- `it "switches data when a different window button is clicked"`.
- `it "renders the data-freshness line at the top"`.
- `it "respects no-animation chart convention"` — assert the `<canvas>`
  element's data attributes / Chartkick options.
- `it "uses crosshair on line charts"`.
- `it "uses no red in the chart palette"` — scrape the legend swatches / dataset
  colors and assert none match `#cc0000` (or the design token for red).
- `it "renders bracketed colored legend labels"`.
- `it "renders the 3-day revision band on time-series charts"`.
- `it "renders empty-state messages with a [ refresh now ] button"`.
- `it "shows the loading caption while a sync is in flight"`.
- `it "broadcasts an updated chart via Turbo Streams when the sync completes"` —
  uses `ActionCable::TestCase` or Turbo Streams test helpers.

Total: **11** test cases.

#### `spec/helpers/analytics_helper_spec.rb`

- `it "format_metric integer for counts"`.
- `it "format_metric m:ss for durations"`.
- `it "format_metric percentage for ratios"`.
- `it "format_metric currency for money"`.
- `it "analytics_window_label maps each enum value to a human label"` — four
  cases bundled.
- `it "data_freshness_label renders 'never synced' when no rows"`.
- `it "data_freshness_label renders the timestamp in the user's TZ"`.

Total: **7** test cases.

#### `spec/decorators/analytics/channel_decorator_spec.rb`

- `it "#window_summary returns the matching ChannelWindowSummary row"`.
- `it "#window_summary returns nil for an unsynced window"`.
- `it "#daily_for_window returns ChannelDaily rows in the window's date range"`.
- `it "#top_videos returns the channel's top_videos_window rows for the given window"`.
- `it "#geography_summed returns aggregated VideoDailyByCountry"` — per Q15.
- `it "#demographics_summed returns aggregated VideoDailyByAgeGroupGender"` —
  per Q15.

Total: **6** test cases.

#### `spec/decorators/analytics/video_decorator_spec.rb`

- `it "#window_summary returns the matching VideoWindowSummary"`.
- `it "#daily_for_window"`.
- `it "#retention returns VideoRetention rows ordered by elapsed_ratio_bucket"`.
- `it "#country_breakdown_for_window"`.
- `it "#device_breakdown_for_window"`.
- `it "#os_breakdown_for_window"`.
- `it "#traffic_source_breakdown_for_window"`.
- `it "#subscribed_status_breakdown_for_window"`.
- `it "#demographics_for_window"`.

Total: **9** test cases.

#### `spec/services/analytics/cross_video_locals_spec.rb`

The four cross-video local rollups deserve dedicated query-builder testing.

- **When-to-publish:**
  - `it "buckets videos by published_at day-of-week + hour"`.
  - `it "computes median first-7-days views per bucket"`.
  - `it "uses median, not mean, to resist outliers"`.
- **Best-duration:**
  - `it "buckets videos by duration ranges (0-60s, 1-5min, 5-15min, 15min+)"`.
  - `it "computes median estimated_minutes_watched per bucket from video_window_summary 28d"`.
- **Topics-that-work:**
  - `it "groups by category_id"`.
  - `it "computes median first-28-days views per category"`.
- **Thumbnail-decay:**
  - `it "computes per-video CTR over time from video_window_summary"`.
  - `it "flags videos with declining CTR"` — agent picks the threshold; spec
    encodes it.

Total: **9** test cases.

#### `spec/system/analytics_monetization_spec.rb`

- `it "hides revenue cards when MONETIZATION_ENABLED is false"`.
- `it "renders 'monetization not connected' caption when disabled"`.
- `it "renders revenue cards when MONETIZATION_ENABLED is true"` — flip the
  AppSetting (or the credentials value), reload, assert.

Total: **3** test cases.

#### `spec/system/analytics_empty_states_spec.rb`

- `it "renders empty-state on the top-level analytics page when no syncs have run"`.
- `it "renders empty-state on the per-channel analytics page"`.
- `it "renders empty-state on the per-video analytics page"`.
- `it "the empty-state's [ refresh now ] button enqueues the right job"`.
- `it "the retention-curve empty-state shows the dedicated [ refresh retention now ] button"`.

Total: **5** test cases.

#### `spec/system/analytics_loading_states_spec.rb`

- `it "renders the loading caption when a sync job is in flight"`.
- `it "the polling Stimulus controller polls every 5s while loading"`.
- `it "the loading state clears when the Turbo Stream broadcast lands"`.

Total: **3** test cases.

#### `spec/system/analytics_chart_conventions_spec.rb`

- `it "every line chart sets animation: false"`.
- `it "every chart's color palette excludes red"`.
- `it "every line chart enables crosshair"`.
- `it "every legend label uses the bracketed colored convention"`.
- `it "every clickable has cursor: pointer"`.

Total: **5** test cases.

### Flaw / smuggle tests

#### `spec/requests/analytics_flaw_spec.rb`

- `it "ignores a smuggled connection_id parameter"` — query param has no effect
  on what the dashboard renders.
- `it "ignores a smuggled tenant_id parameter"` — defense in depth even though
  tenants are gone.
- `it "rejects a smuggled video_id that does not match the route's video"` —
  `POST /videos/123/analytics/refresh` with a body containing `video_id=456`
  does NOT enqueue a job for video 456.
- `it "rejects a smuggled channel_id that targets a different channel"`.

Total: **4** test cases.

### Test count summary

| Spec file                                             | New cases |
| ----------------------------------------------------- | --------- |
| `spec/requests/analytics_spec.rb`                     | 15        |
| `spec/requests/channels/analytics_spec.rb`            | 14        |
| `spec/requests/videos/analytics_spec.rb`              | 15        |
| `spec/requests/channels/analytics_refresh_spec.rb`    | 5         |
| `spec/requests/videos/analytics_refresh_spec.rb`      | 4         |
| `spec/requests/videos/retention_refresh_spec.rb`      | 3         |
| `spec/system/analytics_dashboard_spec.rb`             | 11        |
| `spec/helpers/analytics_helper_spec.rb`               | 7         |
| `spec/decorators/analytics/channel_decorator_spec.rb` | 6         |
| `spec/decorators/analytics/video_decorator_spec.rb`   | 9         |
| `spec/services/analytics/cross_video_locals_spec.rb`  | 9         |
| `spec/system/analytics_monetization_spec.rb`          | 3         |
| `spec/system/analytics_empty_states_spec.rb`          | 5         |
| `spec/system/analytics_loading_states_spec.rb`        | 3         |
| `spec/system/analytics_chart_conventions_spec.rb`     | 5         |
| `spec/requests/analytics_flaw_spec.rb`                | 4         |
| **Total NEW test cases**                              | **118**   |

## Manual playbook (post-implementation)

Architect outlines; reviewer fills in remaining steps after spec lands.

1. **Confirm specs 01 + 02 are landed.** Tables exist; sync engine writes to
   them.
2. **Migrate + reseed.**
   ```bash
   bin/rails db:drop db:create db:migrate db:seed
   ```
3. **Visit `/channels`.** Confirm the list renders normally (no analytics
   columns broken by the additive schema).
4. **Trigger a manual analytics sync.**
   ```bash
   bin/rails runner 'YoutubeAnalyticsSync.new.perform'
   ```
   Wait for completion (watch the Sidekiq log).
5. **Confirm tables populate.** Per spec 02 §5 manual step.
6. **Visit `/analytics`.** Confirm:
   - Page title `analytics`.
   - Last-sync line at top with a timestamp.
   - Window picker with four bracketed buttons (`[ 7d ]`, `[ 28d ]`, `[ 90d ]`,
     `[ lifetime ]`).
   - Cross-channel summary cards.
   - Channel cards.
   - Four cross-video rollup charts.
7. **Click `[ 7d ]` then `[ 90d ]`.** Confirm the URL query changes
   (`?window=7d` → `?window=90d`) and the data updates.
8. **Visit `/channels/:id/analytics`** for a connected channel. Confirm:
   - Window summary cards.
   - Daily line chart (with revision band over the last 3 days).
   - Top videos leaderboard table.
   - Geography chart (with Q15 caveat caption).
   - Demographics chart (with Q15 caveat caption).
9. **Click `[ refresh now ]` on the channel page.** Confirm:
   - Redirect back to `/channels/:id/analytics` with a notice.
   - Sidekiq enqueues `ChannelAnalyticsSync` + per-video jobs.
   - The page shows the "loading" caption while jobs run; the chart partials
     refresh via Turbo Stream when each job completes.
10. **Visit `/videos/:id/analytics`** for a video with analytics data. Confirm
    every section renders.
11. **Click `[ refresh retention ]`.** Confirm `VideoRetentionSync` enqueues;
    retention curve refreshes once it completes.
12. **Edge cases:**
    - **Empty channel** (no analytics rows): visit `/channels/<id>/analytics`;
      confirm empty-state copy + `[ refresh now ]` button.
    - **Channel with one video**: every chart renders with one video's data.
    - **Channel with token-revoked connection**: visit; confirm a banner /
      caption indicates `needs_reauth`; the existing data still renders.
    - **Video with no retention rows**: confirm empty-state caption +
      `[ refresh retention now ]` button.
13. **Visual conventions check:**
    - No animation on any chart (charts appear instantly, no easing).
    - No red anywhere in the charts.
    - Crosshair cursor on hover over line charts.
    - Bracketed colored legend labels.
    - `cursor: pointer` on every clickable.
14. **No JS dialogs.** Click `[ refresh now ]`; confirm the page transitions via
    Turbo Drive — no `confirm()` dialog.
15. **Run RSpec.**
    ```bash
    bundle exec rspec
    ```
    Confirm green.
16. **Run rubocop.** Clean.
17. **Run brakeman.** No new findings.

## Cross-stack scope

| Surface           | Status                                                                                             |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane. Routes, controllers, views, helpers, decorators, Stimulus controllers. |
| MCP rack app      | **Skipped.** Per-domain MCP coverage matrix says analytics MCP tools are a future spec.            |
| Doorkeeper        | **N/A.**                                                                                           |
| `pito` CLI (Rust) | **Skipped.** CLI parity for analytics dashboards (TUI-rendered charts) is a deferred follow-up.    |
| Astro / website   | **N/A.**                                                                                           |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **Page titles.**
   - Top-level: `analytics`.
   - Per-channel: `<channel name> · analytics` or just `analytics`?
   - Per-video: `<video title> · analytics` or just `analytics`? User picks.
2. **Window picker labels.** Bracketed: `[ 7d ]`, `[ 28d ]`, `[ 90d ]`,
   `[ lifetime ]`. Or longer: `[ last 7 days ]`, etc. Recommendation: short form
   (matches spec 01's enum values verbatim). User picks.
3. **Refresh button label.**
   - `[ refresh now ]` (concise) vs `[ refresh analytics ]` (explicit).
   - For retention: `[ refresh retention ]` vs `[ refresh retention curve ]`.
     User picks.
4. **Empty-state copy.**
   - Top-level: `no analytics yet. connect a youtube channel to start syncing.`
     (assumes no connection) vs `no analytics yet. <a>refresh now</a> to sync.`
     (assumes connection but no rows).
   - Per-channel:
     `no data for this window. data syncs nightly; refresh to start syncing now.`
   - Per-video: same.
   - Retention curve:
     `retention data is refreshed weekly. <a>refresh   retention now</a> to compute it now.`
     User picks.
5. **Loading-state copy.**
   - `syncing...` (terse) vs
     `analytics sync in progress; chart   refreshes when complete.` (explicit).
     User picks.
6. **Token-expired (`needs_reauth`) banner copy on the dashboards.**
   - `this connection's authorization expired. <a>re-authorize</a> to resume nightly analytics syncing.`
   - Or: `re-authorize this channel to continue syncing analytics.` User picks.
7. **Sync-failure error messages.** When a refresh button is clicked but the
   connection's `needs_reauth: true`, the redirect's flash should not be a
   generic notice — it should say "this connection needs re-authorization
   first." User picks the wording.
8. **Data-freshness label.**
   - `data as of <timestamp>` vs `last synced <timestamp>` vs
     `synced <human-relative-time> ago`.
   - User picks.
9. **Aggregation labels.** When the window picker shows the chosen window, do
   labels say `last 7 days` / `last 28 days` (Note 3's nomenclature) or `7d` /
   `28d` (matches the enum values)? Recommendation: short form on the picker
   buttons; long form in chart headings (`channel daily — last 28 days`). User
   picks.
10. **Cross-video local rollup chart titles.**
    - When-to-publish: `when to publish` vs `best publish time` vs
      `publish-time analytics`.
    - Best-duration: `best video length` vs `duration vs watch time`.
    - Topics-that-work: `topics that work` vs `category performance`.
    - Thumbnail-decay: `thumbnail decay` vs `thumbnail CTR over time`. User
      picks.
11. **Studio-faithfulness caveat caption (Q15).**
    `summed from per-video data; may differ from Studio's channel report` vs
    `aggregated locally; Studio's channel-level report may differ slightly`.
    User picks.
12. **3-day revision band caption (Q11).**
    `data revises for ~48-72h after publish` vs
    `recent data may shift as YouTube finalizes counts` vs
    `data lag: last 3 days revise`. User picks.
13. **Monetization-disabled caption (Q13).** `monetization not connected.`
    (terse) + `[ enable monetization ]` link. Or:
    `revenue tracking is disabled. enable in settings.` User picks.
14. **`[ enable monetization ]` link target.** No settings surface exists yet.
    Options: (a) `href="#"` placeholder + caption "not yet available"; (b) link
    to `/settings` with a flash; (c) link to a placeholder route returning a
    "coming soon" page. Recommendation: (a). User confirms.

## Open questions (architect cannot decide; master agent surfaces to

user)

1. **Pane integration for per-channel / per-video analytics.** The
   `/channels/:id` page is a multi-pane workspace per CLAUDE.md ("Channels and
   Videos pages are multi-pane workspaces"). Does `/channels/:id/analytics` open
   as a separate pane within that workspace, or as a full-page drill-out?
   Recommendation: full-page drill-out (`/channels/:id/analytics` is its own
   page; the link from the pane is `[ analytics → ]`). Pane-rendering of charts
   is a follow-up; charts inside narrow panes don't show their value well. User
   confirms.
2. **`/analytics` route singular vs plural.** Singular (`resource`) matches the
   headline "the analytics dashboard." Plural (`resources :analytics`) suggests
   a collection. Recommendation: singular. User confirms.
3. **Decorator placement.** Draper decorators under `app/decorators/` per the
   user-memory note. Recommendation: `app/decorators/analytics/` (sub-namespace)
   so `Analytics::ChannelDecorator` and `Analytics::VideoDecorator` don't
   collide with future top-level decorators on `Channel` / `Video`. User
   confirms.
4. **Stimulus controller placement.** `app/javascript/controllers/` per project
   convention. The three new controllers (`analytics_chart`,
   `analytics_window_picker`, `analytics_refresh_polling`) live there. User
   confirms.
5. **Chartkick rendering — server-rendered SVG vs client-rendered Chart.js?**
   Chartkick's default is client-rendered Chart.js. SVG is an option for reduced
   JS, but loses the crosshair + interactive legend. Recommendation: Chart.js
   (the default). User confirms.
6. **Real-time refresh — Turbo Streams vs polling-only?** Q7 + Q6 together
   specify Turbo Streams broadcast from the sync jobs + polling fallback. Cost:
   spec 02's `ensure` block needs the `broadcast_replace_to` call; the polling
   Stimulus controller is a defense in depth. Recommendation: ship both. User
   confirms.
7. **Cross-channel summary at the top-level dashboard — show even when only one
   channel is connected?** With a single connected channel the "cross-channel
   summary" duplicates the channel-card metrics. Recommendation: show only when
   ≥ 2 connected channels; with 1 channel, render only the channel card. User
   confirms.
8. **Top-videos leaderboard — show the leaderboard of all 50, or paginate to 25
   with a "show more" link?** Recommendation: show all 50; the leaderboard is a
   single table and Note 3 caps at 50 anyway. User confirms.
9. **Should the per-channel analytics page render the channel's own geography +
   demographics in addition to the channel-level rollup?** Different surface:
   per-channel page already shows the rollup. The "own" geography / demographics
   are derived from the same data. Recommendation: render once on the channel
   page (the rollup); skip the parallel "individual" version. User confirms.
10. **Tab structure on the per-video page — vertical sections vs horizontal
    tabs?** All breakdowns visible at once is information-rich but
    long-scrolling. Tabs hide the long surfaces. Recommendation: vertical
    sections (matches the rest of pito's full-page layouts; avoids JS-tab
    state). User confirms.
11. **Chart sizing.** Tailwind utilities or inline `style="height: ...;"`? Per
    project convention (Tailwind preferred). Recommendation: Tailwind utility
    classes like `h-64` / `h-96`. User confirms.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. **Page titles.**
   - Top-level: `analytics`
   - Per-channel: `<channel name> · analytics`
   - Per-video: `<video title> · analytics`
2. **Window picker labels.** Short form: `[ 7d ]`, `[ 28d ]`, `[ 90d ]`,
   `[ lifetime ]`.
3. **Refresh button labels.** `[ refresh now ]` for analytics;
   `[ refresh retention ]` for the retention surface.
4. **Empty-state copy.**
   - Top-level: `no analytics yet. connect a youtube channel to start syncing.`
   - Per-channel:
     `no data for this window. data syncs nightly; refresh to start syncing now.`
   - Per-video: same as per-channel.
   - Retention curve:
     `retention data is refreshed weekly. <a>refresh retention now</a> to compute it now.`
5. **Loading-state copy.** `syncing...` (terse).
6. **`needs_reauth` banner.**
   `re-authorize this channel to continue syncing analytics.`
7. **Sync-failure flash on locked connection.**
   `this connection needs re-authorization first.`
8. **Data-freshness label.** `synced <human-relative-time> ago`.
9. **Aggregation labels.** Short on picker buttons (`[ 7d ]`); long form in
   chart headings (e.g., `channel daily — last 28 days`).
10. **Cross-video local rollup chart titles.**
    - When-to-publish: `when to publish`
    - Best-duration: `best video length`
    - Topics-that-work: `topics that work`
    - Thumbnail-decay: `thumbnail decay`
11. **Studio-faithfulness caveat caption.**
    `summed from per-video data; may differ from Studio's channel report`.
12. **3-day revision band caption.** `data revises for ~48-72h after publish`.
13. **Monetization-disabled caption.** `monetization not connected.` plus a
    `[ enable monetization ]` link.
14. **`[ enable monetization ]` link target.** Option (a): `href="#"`
    placeholder with caption "not yet available".

### Open-question decisions

1. **Pane integration for `/channels/:id/analytics` and
   `/videos/:id/analytics`.** Full-page drill-out. The link from the pane reads
   `[ analytics → ]`. Pane-rendering of charts is a follow-up.
2. **`/analytics` route.** Singular (`resource`).
3. **Decorator placement.** `app/decorators/analytics/` sub-namespace —
   `Analytics::ChannelDecorator`, `Analytics::VideoDecorator`.
4. **Stimulus controller placement.** `app/javascript/controllers/` per project
   convention.
5. **Chartkick rendering.** Chart.js (default).
6. **Real-time refresh.** Both — Turbo Streams broadcast from sync jobs PLUS a
   polling Stimulus controller as defense-in-depth.
7. **Cross-channel summary visibility.** Show only when ≥ 2 connected channels.
   With one channel, render only the channel card.
8. **Top-videos leaderboard.** Show all 50 (the spec's cap; no pagination).
9. **Per-channel "own" geography + demographics.** Skip the parallel
   "individual" version. Render once on the channel page (rollup only).
10. **Tab structure on per-video page.** Vertical sections. No JS-tab state.
11. **Chart sizing.** Tailwind utility classes (e.g., `h-64`, `h-96`).

## Non-goals (explicit)

- **Data model.** Spec 01.
- **Sync engine.** Spec 02.
- **MCP tools for analytics.** Future spec; per the per-domain MCP coverage
  matrix.
- **CLI parity.** Future follow-up; ratatui chart rendering is a separate R&D.
- **Dedicated channel-level slice tables (C4 / C5).** Per spec 02 open question;
  computed at query time here.
- **Custom user-picked windows beyond 7d / 28d / 90d / lifetime.** Per spec 02
  non-goals.
- **Game analytics attribution charts.** Future spec; depends on
  `video_game_link` join not yet introduced.
- **Calendar / notifications surfaces for sync events.** Calendar /
  notifications phase.
- **"Compare two channels" / "compare two videos" UX.** Future follow-up; not
  enumerated in Note 3.
- **Annotations on charts (Studio-style milestones).** Future follow-up.
- **Export to CSV / PDF.** Future follow-up.
- **Settings surface for `MONETIZATION_ENABLED`.** Future spec; the dashboard
  renders `[ enable monetization ]` as a placeholder link per Q13.

## Implementation lane assignment

Single lane: **rails-impl**. Touches:

- `config/routes.rb`
- `app/controllers/`
- `app/views/`
- `app/components/` (if helpers grow into components — agent's call)
- `app/decorators/analytics/`
- `app/helpers/`
- `app/javascript/controllers/`
- `spec/requests/`, `spec/system/`, `spec/helpers/`, `spec/decorators/`,
  `spec/services/analytics/`

No `extras/cli/`, no `extras/website/`, no `db/migrate/`, no `app/jobs/`, no
`app/services/youtube/`, no `app/services/backfill/`, no `app/models/` schema
changes, no `docs/`.

## Reviewer checkpoints (post-implementation)

1. `git grep 'cc0000\|color: red' app/views/analytics/ app/javascript/controllers/analytics_*`
   → zero matches (charts no red).
2. `git grep 'animation:\|animation =' app/javascript/controllers/analytics_*` →
   every match shows `animation: false`.
3. `git grep 'confirm\|alert\|prompt\|data-turbo-confirm' app/views/analytics/ app/views/channels/analytics/ app/views/videos/analytics/`
   → zero matches.
4. `git grep 'video_daily.*average_view_percentage\|video_daily.*click_rate' app/views/ app/decorators/`
   → zero matches (Studio-faithful ratios come from window summaries).
5. `bundle exec rspec spec/requests/analytics_spec.rb spec/requests/channels/analytics_spec.rb spec/requests/videos/analytics_spec.rb spec/system/analytics_*_spec.rb`
   → green.
6. `bundle exec rspec` → full suite green.
7. `bundle exec rubocop` → clean.
8. `bundle exec brakeman -q` → clean.
9. Manual playbook §1-§17.
10. Spec count delta logged in
    `docs/plans/beta/13-analytics-sync-engine/log.md`.
