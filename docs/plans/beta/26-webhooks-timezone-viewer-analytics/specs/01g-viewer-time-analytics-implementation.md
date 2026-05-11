# 01g — Viewer-time analytics implementation

> Heatmap ViewComponent + per-video and per-channel analytics tabs + data
> ingestion (sync job + daily rollup). **Depends on 01a (timezone foundation)
> and 01f (architecture docs).** Implementation agent: `pito-rails`.

## Goal

Ship the "best time to publish" analytics surface. Per-video and per-channel
viewer distribution rendered as a day-of-week × hour-of-day heatmap, with the
day and hour axes in the user's timezone. Raw data lives in
`video_viewer_time_buckets` (UTC-stored); the rollup happens at query time via
the user's tz offset. Refresh cadence: daily (per 01f). The heatmap is a
single-hue intensity gradient (no red, per design rules). Per-channel view
aggregates across all channel videos.

## Files touched

### New — Migration

- `db/migrate/YYYYMMDDHHMMSS_create_video_viewer_time_buckets.rb`:
  ```ruby
  create_table :video_viewer_time_buckets do |t|
    t.references :video, null: false, foreign_key: true, index: false
    t.integer :hour_of_day_utc, null: false # 0-23
    t.integer :day_of_week_utc, null: false # 0-6 (Postgres extract(dow) convention; Sunday=0)
    t.integer :view_count, null: false, default: 0
    t.bigint :watch_time_seconds, null: false, default: 0
    t.datetime :last_synced_at
    t.timestamps
  end
  add_index :video_viewer_time_buckets,
            %i[video_id day_of_week_utc hour_of_day_utc],
            unique: true,
            name: :index_viewer_time_buckets_uniq
  add_index :video_viewer_time_buckets, :last_synced_at
  ```
- Check constraints (raw SQL in the migration):
  `hour_of_day_utc >= 0 AND hour_of_day_utc <= 23`,
  `day_of_week_utc >= 0 AND day_of_week_utc <= 6`.

### New — Model

- `app/models/video_viewer_time_bucket.rb`:
  - `belongs_to :video`
  - Validations on the two integer fields (range), `view_count >= 0`,
    `watch_time_seconds >= 0`.
  - Scope: `.for_user_tz(tz)` — returns the rollup query rolled to the given tz
    (SQL pattern from 01f §"Query patterns").
  - Scope: `.for_channel(channel_id)` — joins through videos.

### New — Service: rollup

- `app/services/analytics/viewer_time_rollup.rb` — pure-Ruby wrapper around the
  rollup SQL. Public method:
  `#call(scope: :video | :channel, id:, tz: "Etc/UTC")` returns a
  `[[dow, hod, view_count, watch_time_seconds], ...]` array (or a
  Struct-of-Arrays) suitable for feeding the heatmap component.

### New — Job: per-video sync

- `app/jobs/video_viewer_time_sync_job.rb` — accepts a `video_id`, calls the
  YouTube Analytics API (via the existing `Youtube::Client` from Phase 7),
  upserts rows in `video_viewer_time_buckets`. Idempotent on re-run.
  Quota-aware: aborts cleanly if the daily quota is exhausted (Phase 7's
  `youtube_api_calls` audit catches this).

### New — Job: daily refresh

- `app/jobs/viewer_time_daily_refresh_job.rb` — cron entry. Enumerates all owned
  videos and enqueues `VideoViewerTimeSyncJob.perform_later` for each. Runs at
  03:00 server time. One job per video; Sidekiq parallelizes naturally.

### New — Cron registration

- `config/sidekiq.yml` (or `config/schedule.yml`) — add:
  ```yaml
  viewer_time_daily_refresh:
    cron: "0 3 * * *"
    class: ViewerTimeDailyRefreshJob
    queue: default
  ```

### New — ViewComponent

- `app/components/viewer_time_heatmap_component.rb`:
  - Accepts `data:` (the rollup array), `tz:` (the user's tz for axis labels),
    `intensity_by:` (`:views | :watch_time`, default `:views`).
  - Renders a CSS-grid heatmap, 7 rows (days) × 24 columns (hours). Each cell
    carries a `title` tooltip with raw counts.
  - Color: single-hue intensity gradient. Suggestion: link-blue (`#0000cc`) with
    alpha from 0.0 (no data) to 1.0 (max). Min cell is `--color-pane-bg-a` to
    match the panes. **Palette confirmed by user before dispatch.**
  - Mobile collapses to a vertical stack of 7 daily strips (CSS media query at
    the same `88vw` breakpoint pane primitives use).
- `app/components/viewer_time_heatmap_component.html.erb` — markup.
- `app/components/viewer_time_heatmap_component.css` (or extend
  `app/assets/tailwind/application.css`) — the CSS-grid + gradient rules. No new
  CSS tokens unless approved by user.

### New — Analytics tabs

- `app/views/videos/_viewer_time_tab.html.erb` — partial rendered inside the
  existing video show page's analytics tab. Calls the rollup + heatmap
  component.
- `app/views/channels/_viewer_time_tab.html.erb` — same for channels.
- `app/controllers/videos_controller.rb` — extend `#show` to load the rollup
  data when the analytics tab is active. Or, if tabs lazy-load, add a dedicated
  `videos/:id/analytics/viewer_time` action returning a Turbo Frame.
  Implementation agent picks the pattern that matches the current analytics-tab
  convention.
- `app/controllers/channels_controller.rb` — same for channels.
- `config/routes.rb` — add the lazy-load Turbo Frame routes if needed. Friendly
  URLs preserved.

### New — Backfill rake task

- `lib/tasks/viewer_time_backfill.rake` — `pito:backfill_viewer_time_buckets`
  task. Accepts a `DAYS=90` env var. Walks every owned video and enqueues
  `VideoViewerTimeSyncJob` with a `since: DAYS.ago` argument. One-shot,
  rerunable.

### New — Specs (spec pyramid sweep)

- `spec/models/video_viewer_time_bucket_spec.rb` — validations, scopes,
  uniqueness, range constraints, `.for_user_tz` happy / sad / edge (DST,
  half-hour offset, UTC).
- `spec/services/analytics/viewer_time_rollup_spec.rb` — rollup SQL correctness:
  video-scope happy + empty + edge (single row spanning midnight in user-tz);
  channel-scope happy + empty + multi-video aggregation; tz coverage (Etc/UTC,
  Europe/Bucharest summer + winter, Asia/Kolkata, Pacific/Kiritimati).
- `spec/jobs/video_viewer_time_sync_job_spec.rb` — WebMock-stubbed YouTube
  Analytics API: happy 200 + upsert; sad 401 (token expired) + surface
  notification; sad 403 (quota) + abort + log; edge: re-run on the same video
  idempotent (no duplicate rows).
- `spec/jobs/viewer_time_daily_refresh_job_spec.rb` — fan-out: enumerates owned
  videos, enqueues one job per video, skips non-owned.
- `spec/components/viewer_time_heatmap_component_spec.rb` — rendering happy
  (full grid), sad (empty data), edge (single-row data, max- intensity
  normalization).
- `spec/requests/videos/analytics_spec.rb` — extend with the viewer-time tab
  request. Happy (200 with rendered heatmap), sad (no data — empty state),
  unauthenticated.
- `spec/requests/channels/analytics_spec.rb` — same for channels.
- `spec/system/viewer_time_heatmap_spec.rb` — critical journey: open a video's
  analytics tab, see the heatmap render with the user's tz applied. (Single
  system spec — keep it thin per the spec pyramid rule that system specs cover
  only critical journeys.)
- `spec/lib/tasks/viewer_time_backfill_spec.rb` — task happy + edge (zero
  videos, large DAYS value).

### Edited

- `app/views/videos/show.html.erb` — add the viewer-time tab to the existing
  analytics tabs panel.
- `app/views/channels/show.html.erb` — same for channels.
- `app/assets/tailwind/application.css` — heatmap CSS (if not isolated in the
  component CSS file).
- `config/locales/en.yml` — copy for the heatmap empty state, the axis labels
  (Mon/Tue/.../Sun, 00/01/.../23), the tooltip format.

### Read-only inputs

- `app/services/youtube/client.rb` (Phase 7) — Analytics API caller.
- `app/models/video.rb` (Phase 4 / Phase 8) — for the `owned?` predicate and
  channel join.
- `app/helpers/time_zone_helper.rb` (from 01a) — for axis labeling.
- `docs/architecture.md` (from 01f) — the contract this implementation fulfills.

## Acceptance

- [ ] Migration creates `video_viewer_time_buckets` with the schema in "Files
      touched." Composite unique index + range check constraints present.
- [ ] `VideoViewerTimeBucket` model validates ranges, has the `for_user_tz` +
      `for_channel` scopes, plays correctly with
      `Video.has_many :viewer_time_buckets`.
- [ ] `Analytics::ViewerTimeRollup` rolls UTC buckets up to user-tz at query
      time. Single SQL query (no N+1). Returns data shape suitable for the
      heatmap component.
- [ ] `VideoViewerTimeSyncJob` hits YouTube Analytics, upserts buckets,
      idempotent, quota-aware. Failures land in Phase 16 notifications.
- [ ] `ViewerTimeDailyRefreshJob` runs at 03:00 server time daily via
      sidekiq-cron, fans out one sync job per owned video.
- [ ] `ViewerTimeHeatmapComponent` renders a 7×24 CSS grid (desktop) + 7-strip
      vertical stack (mobile, ≤88vw). Single-hue intensity gradient. Hover
      tooltip shows the raw counts. No red, per design.
- [ ] Per-video tab on `/videos/:id` renders the heatmap with that video's data,
      in the user's tz.
- [ ] Per-channel tab on `/channels/:id` renders the heatmap aggregating all the
      channel's videos.
- [ ] Empty state: when no buckets exist, render "No viewer-time data yet — sync
      runs daily at 03:00 server time." No JS / broken UI.
- [ ] Rake task `pito:backfill_viewer_time_buckets DAYS=90` runs from the
      command line, walks owned videos, enqueues sync jobs.
- [ ] Yes / no boundary: no Booleans cross the wire for this surface directly,
      but the `intensity_by` parameter (if user-selectable later) goes through a
      string enum (`"views"` / `"watch_time"`), not a Boolean. Document the
      future hook.
- [ ] Friendly URLs preserved everywhere (`/videos/:id/analytics/viewer_time`,
      `/channels/:id/analytics/viewer_time`).
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`. The heatmap
      is a static SVG / CSS-grid render with hover tooltips.
- [ ] Spec pyramid covers: model, service, jobs (sync + refresh), component,
      request (video + channel), system (one critical journey), lib (rake task).
- [ ] Brakeman + bundler-audit clean.

## Manual test recipe

1. `bin/setup` for the migration. `bin/dev` to start the stack.
2. Seed bucket data manually:
   ```ruby
   v = Video.where(owned: true).first
   (0..6).each do |dow|
     (0..23).each do |hod|
       v.viewer_time_buckets.create!(
         day_of_week_utc: dow,
         hour_of_day_utc: hod,
         view_count: rand(100),
         watch_time_seconds: rand(10_000),
         last_synced_at: Time.current
       )
     end
   end
   ```
3. Open `/videos/<id>` and navigate to the analytics tab. The viewer-time
   sub-tab renders the heatmap.
4. Change the user's `time_zone` to `Pacific/Kiritimati` via `/settings`. Reload
   the video page — the axis labels shift; cells in the heatmap re-align to the
   new tz.
5. Open `/channels/<id>` and navigate to the analytics tab. The viewer- time
   sub-tab renders the channel-aggregate heatmap (sum across all the channel's
   videos).
6. Run the rake task: `bin/rails pito:backfill_viewer_time_buckets DAYS=7`.
   Watch the Sidekiq dashboard — jobs enqueue + complete.
7. Run the daily refresh manually: `ViewerTimeDailyRefreshJob.perform_now`.
   Confirm fan-out behavior.
8. Resize the browser to mobile width (≤480px). The heatmap collapses to a
   7-strip vertical stack.
9. With WebMock stubs returning 200, run the spec suite. With WebMock stubs
   returning 401 + 403, confirm the failure paths log + create notifications.

## Cross-stack scope

| Surface | Status | Note                                                 |
| ------- | ------ | ---------------------------------------------------- |
| Web     | in     | Primary surface.                                     |
| MCP     | out    | A future `yt:analytics` tool would expose the rollup |
|         |        | data. Deferred to a later phase.                     |
| CLI     | out    | A future `pito videos <id> analytics` would render   |
|         |        | the heatmap as an ASCII grid. Deferred.              |
| Website | out    | No change.                                           |

## Open questions

1. **Heatmap palette.** Single-hue intensity gradient. Suggestion: link- blue
   (`#0000cc`) with alpha 0.0–1.0, or a muted teal / violet not used elsewhere
   in the app. **Confirm with user — design system call.**
2. **`intensity_by` parameter.** v1 hardcodes `:views`. A future toggle between
   views + watch_time + average view duration is a nice-to- have. **Confirm with
   user — ship the toggle in v1 or defer?**
3. **Refresh cadence.** v1 locks daily at 03:00 server time. **Confirm with user
   once Phase 7 quota tracking surfaces real numbers.**
4. **Backfill default DAYS.** v1: 90 days. **Confirm with user.**
5. **YouTube Analytics granularity.** The Mobile note says "verify exact
   granularity available." If only daily buckets are exposed, the
   `hour_of_day_utc` column becomes a distribution approximation rather than a
   true hourly count. **Confirm with user once the API contract is verified
   during dispatch.**
6. **Channel aggregation weighting.** v1 sums view_count + watch_time across all
   the channel's videos. Should we normalize by per-video age / view-count? v1
   leans no — raw sums are the simplest interpretive surface. **Confirm with
   user.**
7. **MCP + CLI surfaces.** Both deferred for v1. **Confirm with user that
   deferral is acceptable.**
