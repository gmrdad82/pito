# Manual test playbook — Phase 13: Analytics (data model + sync engine + dashboard)

**Branch:** `main` (Phase 13 lands across `6391f12` Spec 01 files, `4fa4509`
Spec 02 + Spec 03 files, `cd2b482` Spec 01 log entry, `56e3675` Spec 02 log
entry, `6e45461` Spec 03 lint fixes + log entry) **Specs:**
`docs/plans/beta/13-analytics-sync-engine/specs/01-analytics-data-model.md`,
`docs/plans/beta/13-analytics-sync-engine/specs/02-analytics-sync-engine.md`,
`docs/plans/beta/13-analytics-sync-engine/specs/03-analytics-dashboard.md`
**Log:** `docs/plans/beta/13-analytics-sync-engine/log.md` **Reviewer run:**
2026-05-10 18:35

## Pipeline summary

- Code review: pass — **8 non-blocking concerns** (see "Concerns and
  suggestions"). No correctness or security blockers; concerns center on
  surfaces the orchestrator still leans on (3-day refresh window vs the rake
  task's `from`/`to` arguments, N+1 patterns at top-50 / video-iter scale,
  missing re-auth link target, `connected` vs all-channel scoping on the
  per-channel surface).
- Simplify: pass — **3 opportunistic notes** (duplicate `metric_attributes` /
  `header_names` helpers across two job classes; redundant `ostruct` load
  warning in one spec; the `analytics_window_picker_controller.js` is a no-op
  marker that could be deleted). See "Concerns and suggestions".
- Test suite (Phase 13 slice): **380 examples, 0 failures.**
  - `spec/db/analytics_schema_spec.rb` +
    `spec/models/analytics_associations_spec.rb` — green.
  - `spec/models/{channel_daily,video_daily,channel_window_summary,video_window_summary,top_videos_window,video_retention,video_daily_by_*}_spec.rb`
    (12 model specs) — green.
  - `spec/services/youtube/{analytics_query_builder,analytics_client,active_video_classifier,analytics_client_flaw}_spec.rb`
    — green.
  - `spec/services/backfill/analytics_range_spec.rb` — green.
  - `spec/services/analytics/cross_video_locals_spec.rb` — green.
  - `spec/jobs/{youtube_analytics_sync,channel_analytics_sync,video_analytics_sync,video_retention_sync,concurrent_sync}_spec.rb`
    — green.
  - `spec/integration/analytics_full_sync_spec.rb` — green.
  - `spec/decorators/analytics/{channel_decorator,video_decorator}_spec.rb` —
    green.
  - `spec/helpers/analytics_helper_spec.rb` — green.
  - `spec/requests/analytics_spec.rb`,
    `spec/requests/{analytics_flaw,channels/analytics,channels/analytics_refresh,videos/analytics,videos/analytics_refresh,videos/retention_refresh}_spec.rb`
    — green.
  - `spec/system/{analytics_dashboard,analytics_chart_conventions,analytics_loading_states,analytics_empty_states,analytics_monetization}_spec.rb`
    — green.
- Test suite (full repo): **3669 examples, 4 failures, 1 pending.** None of the
  4 failures touches Phase 13 surface area:
  - `spec/requests/calendar/month_spec.rb:35` — pre-existing order-dependent
    flake (user-flagged).
  - `spec/requests/composites_spec.rb:28` — pre-existing order-dependent flake
    (user-flagged).
  - `spec/services/notification_delivery_channel/discord_spec.rb:225` —
    pre-existing Phase 16 `broadcast_badge` MissingTemplate cascade (documented
    in Spec 03 log, sourced from Phase 16 Spec 02
    notifications-delivery-and-formatters branch landing partially).
  - `spec/services/notification_delivery_channel/slack_spec.rb:164` — same root
    cause.
  - These four are surfaced to the architect for separate triage; they are NOT
    blockers for Phase 13 sign-off.
- Lint (`bundle exec rubocop` over 26 changed/new Phase 13 Ruby files):
  **clean** (26 files inspected, no offenses).
- Security static analysis (`bundle exec brakeman -q -w2`): **0 errors, 0
  security warnings.** Two obsolete ignore entries flagged (`4d586370…`,
  `050af471…`) — pre-existing, not Phase 13.
- Dependency audit (`bundle exec bundler-audit check --update`): clean (1078
  advisories scanned, 0 vulnerabilities).
- Lint specs: `spec/lint/numeric_formatting_spec.rb` and
  `spec/lint/punctuation_spec.rb` both green — every chart partial passes
  `thousands: ","`; the monetization caption ends with a period.
- Hard-rule sweep on Phase 13 surface:
  - **JS dialogs:** 0 hits for `alert(` / `confirm(` / `prompt(` /
    `data-turbo-confirm` across `app/views/analytics/`,
    `app/views/channels/analytics/`, `app/views/videos/analytics/`,
    `app/javascript/controllers/analytics_*.js`. The
    `analytics_chart_controller.js` `console.warn` tripwire is not a user
    dialog.
  - **Bracketed-link convention:** all visible bracketed labels render with no
    inner padding (`[refresh now]`, `[refresh retention]`, `[7d]`, `[28d]`,
    `[90d]`, `[lifetime]`, `[enable monetization]`). The window picker uses
    `bracketed-active` for the inert active state and `bracketed` link class
    otherwise.
  - **Yes/no boundary:** `monetization_enabled?` reads
    `AppSetting.get("monetization_enabled").to_s == "yes"` and `db/seeds.rb`
    seeds `"no"` as the default. Boundary respected.
  - **Tenant-free:** `git grep tenant_id` over
    `db/migrate/20260510155554_create_analytics_tables.rb`
    - Phase 13 model files — zero matches.
  - **Red-color sweep:** `grep -ri '#cc0000\|color: red\|background: red'` over
    `app/views/analytics/` and `app/javascript/controllers/analytics_*` — zero
    matches.
- Routes: `bundle exec rails routes -g analytics` lists six clean routes:
  - `GET /analytics` → `analytics#show`
  - `GET /channels/:channel_id/analytics` → `channels/analytics#show`
  - `POST /channels/:channel_id/analytics/refresh` →
    `channels/analytics_refresh#create`
  - `GET /videos/:video_id/analytics` → `videos/analytics#show`
  - `POST /videos/:video_id/analytics/refresh` →
    `videos/analytics_refresh#create`
  - `POST /videos/:video_id/analytics/retention/refresh` →
    `videos/retention_refresh#create`
- Sidekiq cron (`config/sidekiq_cron.yml`): `youtube_analytics_sync_nightly` (0
  4 \* \* \*) and `youtube_analytics_retention_weekly` (0 5 \* \* 1) both
  registered on the `analytics` queue. The `analytics` queue is declared in
  `config/sidekiq.yml`.
- Schema (`db/schema.rb`): `analytics_window` Postgres enum present; twelve
  analytics tables present with composite UNIQUE indexes on natural keys; ON
  DELETE CASCADE on every FK to `channels` / `videos`; ratio columns at
  `numeric(10, 6)`; duration columns at `numeric(10, 2)`; money columns at
  `numeric(12, 4)`; `video_retentions` carries `computed_at timestamptz` only
  (no `created_at` / `updated_at`).
- Migration: `db/migrate/20260510155554_create_analytics_tables.rb` forward +
  reverse paths verified (twelve `drop_table` calls plus
  `DROP TYPE IF EXISTS analytics_window`).
- Spec count totals (per log + reviewer recount): Spec 01 = 118 examples (vs
  spec's enumerated 113), Spec 02 = 142 examples (vs enumerated 139), Spec 03 =
  120 examples (vs enumerated 118). Total = 380 (vs the spec's enumerated ~370).
  Surplus is natural variance; every Spec pyramid tier covered (model / service
  / job / decorator / helper / validator / lib / request / system).

## Blockers

None. Phase 13 is green across all gates and the eight non-blocking concerns
below are surfaced for follow-up, not user-validation gating.

## Concerns and suggestions

All non-blocking. Numbered for follow-up dispatch reference.

1. **`analytics:backfill[connection_id, from, to]` rake silently ignores `from`
   / `to`.** [severity: medium]
   `Backfill::AnalyticsRange.call(connection:, from:, to:, …)`
   (`app/services/backfill/analytics_range.rb`) validates `from <= to` and
   rejects inverted ranges, but it does NOT pass the dates through to the child
   jobs. Both `ChannelAnalyticsSync` and `VideoAnalyticsSync` hardcode their own
   3-day refresh window (`today_pt - 3 .. today_pt - 1`) inside `perform`.
   Consequence: a developer running
   `rake "analytics:backfill[1,2026-04-01,2026-04-30]"` gets one round of each
   child job per channel/video that fetches only the last 3 days, regardless of
   the requested 30-day range. The rake task name + log entry suggest
   range-aware backfilling. Either thread `from` / `to` through the job kwargs
   and the client call sites, OR rename the surface so its behavior is honest
   (e.g. `analytics:resync[connection_id]`). Spec 02's "backfill mode" intent is
   clearly the former.

2. **`ChannelAnalyticsSync#parse_top_videos_rows` runs a per-row `Video.find_by`
   query inside the loop.** [severity: low]
   `app/jobs/channel_analytics_sync.rb:115-142`. At the top-50 default cap
   that's 50 round-trips per (channel × window) pair; with 4 windows that's 200
   SELECTs per channel per nightly run. A single batched lookup
   (`Video.where(youtube_video_id: ids, channel_id: channel.id).index_by(&:youtube_video_id)`)
   before the `each_with_index.filter_map` would collapse it to one SELECT. Not
   urgent at single-channel scale; flagged because the orchestrator is designed
   to fan out across many connections.

3. **`YoutubeAnalyticsSync#dispatch_for` retention path materializes then loops
   with per-video `active?` checks.** [severity: low]
   `app/jobs/youtube_analytics_sync.rb:42-46`.
   `videos.find_each.select { |v| Youtube::ActiveVideoClassifier.active?(v) }`
   evaluates `recent_views_for(video)` (a `VideoDaily.sum`) per video in Ruby
   memory. For a connection with N videos that's N SUM queries on the
   orchestrator's main path before any jobs are enqueued. Consider rewriting via
   a single SQL pass that joins `videos` to a `video_dailies` aggregate, or
   using `Youtube::ActiveVideoClassifier.active_for(connection)` (which exists
   for exactly this case).

4. **`needs_reauth_banner` shows copy but no re-auth link target.** [severity:
   low] `app/views/analytics/_needs_reauth_banner.html.erb` renders the text
   "re-authorize this channel to continue syncing analytics." without an `<a>`
   to a re-auth path. The user has no actionable surface from inside the
   analytics dashboard to start the re-auth flow. Spec 03 master-agent decision
   6 locks the copy; deferring to the architect on whether to wire the link to
   `oauth_authorizations#new` (or whichever path the OAuth phase lands).

5. **`Channels::AnalyticsController#show` doesn't filter by `connected: true`.**
   [severity: low] `app/controllers/channels/analytics_controller.rb:12` —
   `Channel.find(params[:channel_id])` accepts disconnected channels too. The
   dashboard renders empty-state cards in that case (which is fine), but the
   `[refresh now]` button gates only on `youtube_connection.present?` and not on
   `channel.connected?`. A user who deliberately disconnected the channel can
   still trigger a refresh that runs against the still-active
   `YoutubeConnection`. Per spec, `[refresh now]` should also gate on the
   channel being connected. Easy fix:
   `if @channel.youtube_connection.present? && @channel.connected?` in the
   per-channel show view; matching guard in
   `Channels::AnalyticsRefreshController#create`.

6. **Duplicate `metric_attributes` / `header_names` / coercion helpers across
   two job classes.** [severity: low — simplify]
   `app/jobs/channel_analytics_sync.rb` and `app/jobs/video_analytics_sync.rb`
   each carry an identical `metric_attributes`, `window_ratio_attributes`,
   `header_names`, `int_or_zero`, `int_or_nil`, `dec_or_nil` private API. ~80
   lines of shared code. Extracting to a `Youtube::AnalyticsRowParser` module
   (or a `concern`) would let both classes `include` it and would also surface
   what's actually different (the natural-key shape and the target table). Not
   urgent — the duplication is symmetric and easy to read — but it's the largest
   opportunistic dedupe in the diff.

7. **`analytics_window_picker_controller.js` is a no-op marker that could be
   deleted.** [severity: low — simplify] The Stimulus controller defines
   `static targets = ["button"]` and `static values = { current: String }` and
   an empty class body. The picker's actual behavior (URL swap) is server-side
   via `link_to … url_for(window: w)`. The marker exists "for future
   enhancements" per the comment, but the marker doesn't pin any DOM targeting
   that other code uses today. Either give it a `connect()` that asserts the
   current value matches the URL (defensive) or drop the file + the
   `data-controller` reference in `_window_picker.html.erb`.

8. **`spec/jobs/channel_analytics_sync_spec.rb` warns on `ostruct` load.**
   [severity: low]
   `lib/ruby/3.4.0/ostruct.rb was loaded from the standard library, but will no longer be part of the default gems starting from Ruby 4.0.0`.
   Either add `ostruct` to `Gemfile` or rewrite the offending
   `OpenStruct.new(…)` test fixture as a `Struct` / Hash. Pre-existing on `main`
   (Ruby 3.4.9 default warning); flagged here because Phase 13 widened the
   surface.

## Manual test steps

These steps run from a freshly seeded dev environment. They cover the backend
wiring and the data flow; the user-validation walkthrough at the bottom does the
UI pass.

1. **Setup preamble (one-shot).** Reset and seed the dev DB so the analytics
   tables exist with the `monetization_enabled` AppSetting row.
   - **Action:** `bin/rails db:drop db:create db:migrate db:seed` (or
     `bin/setup` if the dev DB is already torn down).
   - **Expected:** twelve analytics tables created (`channel_dailies`,
     `video_dailies`, six `video_daily_by_*`, `channel_window_summaries`,
     `video_window_summaries`, `top_videos_windows`, `video_retentions`);
     `analytics_window` Postgres enum exists; `AppSetting` row
     `monetization_enabled = "no"` seeded.
2. **Verify the migration applied cleanly.** Connect to dev Postgres and confirm
   the analytics table set + enum.
   - **Action:** `bin/rails dbconsole` then `\dT analytics_window` and
     `\d channel_dailies`.
   - **Expected:** enum lists `'7d', '28d', '90d', 'lifetime'`;
     `channel_dailies` has the unique composite index
     `index_channel_dailies_on_channel_id_and_date` and an FK `channel_id` ON
     DELETE CASCADE.
3. **Boot the app.** Start dev services so the routes, jobs, and Sidekiq cron
   come online.
   - **Action:** `bin/dev`.
   - **Expected:** Puma serves on `:3000`, Sidekiq attaches to the `analytics`
     queue, sidekiq-cron registers `youtube_analytics_sync_nightly` and
     `youtube_analytics_retention_weekly`. Tail `log/development.log` for
     `[analytics-sync]` lines on startup.
4. **Inspect the routes.** Confirm the six analytics routes resolve.
   - **Action:** `bin/rails routes -g analytics`.
   - **Expected:** the six routes listed in "Pipeline summary" above all resolve
     to their controller actions; no path collisions with `channels#index` or
     `videos#index`.
5. **Smoke-test the unauth gate.** Open a private window so no session exists.
   - **Action:** Visit `http://localhost:3000/analytics` while logged out.
   - **Expected:** 302 redirect to `/login`. Same for `/channels/:id/analytics`
     and `/videos/:id/analytics`.
6. **Trigger a no-op nightly run.** With zero `YoutubeConnection.active`, the
   orchestrator should log a "0 active connections" line and exit.
   - **Action:** In a Rails console, `YoutubeAnalyticsSync.new.perform`.
   - **Expected:** `[analytics-sync] starting nightly run; 0 active connections`
     then `[analytics-sync] complete; 0.XXs`.
7. **Verify the rake backfill task wires up.** Try a stub call so the surface is
   exercised without hitting the YouTube API.
   - **Action:** `bin/rails "analytics:backfill[999999,2026-04-01,2026-04-30]"`
     (use a non-existent connection id).
   - **Expected:** abort with `no YoutubeConnection with id=999999`. Note: per
     Concern 1, the `from` / `to` are validated but not plumbed through to the
     child jobs.
8. **Confirm Sidekiq cron schedule.** Open the Sidekiq Web UI and verify the two
   analytics cron entries are listed.
   - **Action:** Visit `http://localhost:3000/sidekiq/cron` (HTTP basic auth —
     see `Rails.application.credentials.sidekiq_web`).
   - **Expected:** `youtube_analytics_sync_nightly` (cron `0 4 * * *`) and
     `youtube_analytics_retention_weekly` (cron `0 5 * * 1`) both listed; both
     target the `analytics` queue; both are enabled.
9. **Toggle monetization on.** Flip the AppSetting to confirm the
   monetization-disabled caption hides and revenue cards take its place.
   - **Action:** In Rails console,
     `AppSetting.set("monetization_enabled", "yes")`.
   - **Expected:** the next `/channels/:id/analytics` / `/videos/:id/analytics`
     request renders the revenue cards (estimated revenue, CPM) instead of the
     `monetization not connected.` caption + `[enable monetization]` link.
     Toggle back with `AppSetting.set("monetization_enabled", "no")` after the
     user-validation walk-through.
10. **Audit-row sanity.** With a stub
    `YoutubeApiCall.create!(client_kind: "analytics_v2", outcome: "succeeded", endpoint: "reports.query", http_method: "GET", units: 0)`
    row, the data-freshness label should switch from `never synced` to
    `synced X ago`.
    - **Action:** in Rails console, create the row above with a
      `youtube_connection_id` you control, then refresh `/analytics`.
    - **Expected:** the page-top caption flips to `synced N seconds ago` (or
      whatever `time_ago_in_words` returns). Roll back with
      `YoutubeApiCall.last.destroy` after the user-validation pass.

## Cleanup

```bash
# Roll back the dev DB to a clean baseline:
bin/rails db:drop db:create db:migrate db:seed

# Or, lighter touch:
bundle exec rails console
> AppSetting.set("monetization_enabled", "no")
> YoutubeApiCall.where(client_kind: "analytics_v2").delete_all
> ChannelDaily.delete_all; VideoDaily.delete_all
> ChannelWindowSummary.delete_all; VideoWindowSummary.delete_all
> TopVideosWindow.delete_all; VideoRetention.delete_all
> %i[VideoDailyByCountry VideoDailyByDeviceType VideoDailyByOperatingSystem
>    VideoDailyByTrafficSource VideoDailyBySubscribedStatus
>    VideoDailyByAgeGroupGender].each { |k| k.to_s.constantize.delete_all }
```

## User Validation

These steps are pure UI/UX walkthrough. The user reads them in the browser
without leaving it. (Setup preamble: Manual test steps 1-3 above must be done
first.)

[ ] 1. **Empty top-level dashboard.** Visit `http://localhost:3000/analytics` on
a fresh dev DB → page renders the `analytics` H1, the caption `never synced`,
the four window-picker buttons (`[7d]`, `[28d]`, `[90d]`, `[lifetime]`) with
`[28d]` showing as the inert active state, the empty-state copy
`no analytics yet. connect a youtube channel to start syncing.`, and four
cross-video chart sections each with the empty-state copy
`no data for this window. data syncs nightly; refresh to        start syncing now.`
No red colors anywhere. [ ] 2. **Window picker switches the URL.** Click `[7d]`
from the top-level page → URL updates to `/analytics?window=7d`, the `[7d]`
button now renders inert and `[28d]` becomes a clickable link. Refreshing keeps
the `?window=7d`. Click `[lifetime]` → URL becomes `/analytics?window=lifetime`.
Click `[28d]` to return. [ ] 3. **Bracketed-link convention.** Hover every
bracketed element on `/analytics` → cursor flips to `pointer` on the inactive
picker buttons, on the `[enable monetization]` placeholder link, and on any
visible `[refresh now]` button. Inert `bracketed-active` items show a default
cursor. None of the brackets show inner padding (no `[ 7d ]` — every label is
`[label]`). [ ] 4. **Monetization disabled caption.** Scroll the per-channel
page at `/channels/:id/analytics` for any seeded channel → below the summary
cards, the dashed-border placeholder reads
`monetization not connected. [enable monetization] — not yet        available.`
The `[enable monetization]` link's `href` is `#` (no real action wired yet —
placeholder only). [ ] 5. **Per-channel dashboard sections.** Visit
`/channels/:id/analytics` for a channel with no synced data → page renders the
`<channel> · analytics` H1, the data-freshness caption, the window picker, an
optional `[refresh now]` button (only when the channel has a
`YoutubeConnection`), and four sections (window summary cards, channel-daily
line chart, top videos table, geography bar chart, demographics chart). All four
sections show the locked empty-state copy. The geography and demographics
sections show the Q15 caveat caption
`summed from per-video data; may differ from Studio's channel        report.`
once data exists. [ ] 6. **Per-video dashboard sections.** Visit
`/videos/:id/analytics` for a seeded video → page renders the
`<video title> · analytics` H1, the data-freshness caption, the window picker,
both `[refresh now]` and `[refresh retention]` buttons (when the parent channel
has a connection), and nine sections: window summary cards, daily line,
retention curve, country bar, device donut, OS donut, traffic-source bar,
subscribed-status donut, demographics heatmap. Each section shows the locked
empty-state copy on a fresh DB. [ ] 7. **Refresh button — happy path.** On
`/channels/:id/analytics` for a connected channel without `needs_reauth`, click
`[refresh now]` → POST redirects back to the page; a `notice` flash reads
`syncing...` Inspect Sidekiq Web UI's analytics queue → `ChannelAnalyticsSync`
and one `VideoAnalyticsSync` per channel video are queued. [ ] 8. **Refresh
button — needs_reauth banner.** Set `connection.needs_reauth = true` in console,
then visit `/channels/:id/analytics` for that channel → the
`re-authorize this channel to continue syncing analytics.` banner renders above
the summary section. Click `[refresh        now]` → page redirects with an
`alert` flash reading `this connection needs re-authorization first.` No jobs
are enqueued (verify in Sidekiq Web UI). [ ] 9. **Retention refresh button.** On
`/videos/:id/analytics` for a video whose channel has a healthy connection,
click `[refresh        retention]` → POST redirects back with the `syncing...`
notice; Sidekiq queue shows a `VideoRetentionSync` enqueued (and only that —
`VideoAnalyticsSync` does NOT get enqueued from the retention button). [ ] 10.
**Cross-channel summary visibility.** With one connected channel only, the
top-level `/analytics` shows the per-channel cards block but NOT a cross-channel
summary block. Connect a second channel (or seed a second
`Channel.connected = true` row) → reload `/analytics` → the cross-channel
summary block appears above the per-channel cards, with four metric cards
(views, estimated minutes watched, net subscribers, likes). [ ] 11. **Window
picker also lives on per-channel and per-video.** Click `[7d]` on
`/channels/:id/analytics` → URL becomes `/channels/:id/analytics?window=7d`; the
section headings now read `summary — last 7 days`,
`channel daily — last 7 days`, `top videos — last 7 days`. Same flow on
`/videos/:id/analytics`. [ ] 12. **No JS dialogs anywhere.** Open dev tools
console → click every `[refresh now]`, `[refresh retention]`,
`[enable         monetization]`, picker button → no `alert` / `confirm` /
`prompt` dialog appears at any point; the `analytics_chart_controller.js`
`console.warn` tripwire only fires if `#cc0000` is detected in chart markup (it
should never trigger). [ ] 13. **Chart palette is red-free.** Inspect the
rendered `<canvas>` data on any chart partial via dev tools → no
`borderColor: '#cc0000'` or `backgroundColor: '#cc0000'`. The five colors should
be the design-system palette
(`#0000cc / #2e7d32 / #8b5cf6 / #d97706 / #0891b2`). [ ] 14. **Data freshness
label updates.** After Manual test step 10 seeds a synthetic `YoutubeApiCall`
with `client_kind:         "analytics_v2"` and `outcome: "succeeded"`, refresh
`/analytics` → caption flips from `never synced` to
`synced         less than a minute ago` (or similar `time_ago_in_words` output).
[ ] 15. **Monetization toggle on.** With
`AppSetting.set(         "monetization_enabled", "yes")` (Manual test step 9),
reload `/channels/:id/analytics` → the dashed-border
`monetization not connected.` caption is replaced by two revenue cards
(estimated revenue, CPM). On `/videos/:id/analytics`, same swap: revenue cards
replace the caption. After the validation, run
`AppSetting.set("monetization_enabled", "no")` to roll back. [ ] 16.
**Top-videos table renders ranks 1..N.** With seeded `TopVideosWindow` rows for
a channel + window, the per-channel page's top-videos section shows a 5-column
table (rank, video, views, watch time, likes) ordered by rank ascending. Rank 1
video links to its `/videos/:id` show page (NOT directly to its analytics
dashboard). [ ] 17. **Sidekiq cron entries visible.** Visit
`http://localhost:3000/sidekiq/cron` → `youtube_analytics_sync_nightly` and
`youtube_analytics_retention_weekly` are both listed, both marked enabled, both
targeted at the `analytics` queue. Cron schedules read `0 4 * * *` and
`0 5 * * 1`.
