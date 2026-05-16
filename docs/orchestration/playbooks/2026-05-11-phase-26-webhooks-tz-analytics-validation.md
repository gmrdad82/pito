# Manual test playbook — Phase 26 (Webhooks + Timezone + Viewer-time analytics)

**Branch:** `main` **Phase plan:**
`docs/plans/beta/26-webhooks-timezone-viewer-analytics/plan.md` **Sub-specs
ticked:** 01a – 01h (all eight). **Reviewer run:** 2026-05-11 18:15 **Commit
range reviewed:** `e472d40` (01a foundations) → `2959a2f` (P26 docs close, plan
boxes ticked).

This phase ships three feature areas: User timezone foundation (01a),
Slack/Discord webhook panes + help modal (01b/01c/01d), the daily digest
scheduler + per-provider delivery (01e), the analytics architecture doc
sections + viewer-time heatmap surface (01f/01g), and scheduled-publish tz
wiring (01h).

## Pipeline summary

- Code review (manual, scoped to Phase 26 diff): **pass** with 8 non-blocking
  concerns — see below.
- Simplify (manual, scoped to Phase 26 diff): **5 tightening suggestions** — see
  below.
- Phase 26 targeted RSpec slice (27 spec files spanning models, services, jobs,
  components, helpers, requests, views, system): **489 examples, 0 failures, 0
  pending.**
- Full RSpec suite: **7961 examples, 13 failures, 1 pending.** Of the 13
  failures, **3 are Phase 26 reviewer findings** (see Blockers §1); the
  remaining 10 are pre-existing on `main` from in-flight Phase 25 / Phase 27
  surfaces and unrelated lint specs.
- Rubocop (touched Ruby files in Phase 26 diff, 19 files): **clean.**
- Brakeman (`bin/brakeman -q -w2`): **0 security warnings, 0 errors** (two
  obsolete-ignore entries pre-existed; unrelated to this phase).
- Bundler-audit (`bin/bundler-audit check --update`): advisory DB up to date;
  **no vulnerabilities found.**
- Per-stack gates: no diff under `extras/cli/` or `extras/website/` in scope for
  this phase. CLI parity tracked as a deferred follow-up (log §01a OQ 4, §01g
  cross-stack).

## Blockers (resolve before user validation)

1. **3 RSpec failures in the webhook-help routing layer (Phase 26 01d).**
   `spec/requests/settings/webhooks/help_spec.rb:112` (unknown provider), `:117`
   (empty provider segment), and `spec/system/settings_webhook_help_spec.rb:83`
   all expect `:not_found` from `/settings/webhooks/help/mars` and
   `/settings/webhooks/help/`. The router constraint correctly rejects the
   request (`No route matches`), but the test environment's
   `consider_all_requests_local = true` re-renders the rescue template, which
   itself exceeds the Document tree depth limit and surfaces as an
   `ActionView::Template::Error`. Production behaviour is fine (Rails converts
   the routing error to a 404 with the bare 404.html page); the test-env path is
   what's red. Two fixes are reasonable:
   - Wrap each spec with
     `expect { get ... }.to raise_error(ActionController::RoutingError)`, which
     expresses the routing-layer contract directly.
   - OR temporarily flip `config.action_dispatch.show_exceptions = :all` for
     these three specs and assert the resulting 404 body.

   Either approach is a Phase 26 01d follow-up (small fix, scoped to the three
   specs). Until then the suite reports `13 failures` instead of the
   `10 pre-existing`.

The remaining 10 full-suite failures (`spec/lint/numeric_formatting_spec.rb`,
`spec/lint/punctuation_spec.rb`, `spec/requests/calendar/month_spec.rb`,
`spec/requests/composites_spec.rb` x2,
`spec/requests/concerns/sessions/auth_concern_spec.rb`, `spec/seeds_spec.rb`,
`spec/system/calendar_edit_delete_spec.rb`,
`spec/system/settings/tokens_spec.rb`, `spec/system/video_import_flow_spec.rb`)
are pre-existing on `main` and surface in Phase 25 / Phase 27 in-flight work.
Not blocking for Phase 26 validation; tracked under their respective phase
follow-ups.

## Concerns (non-blocking — severity-tagged)

1. **[MED] Settings index does not surface Slack or Discord webhook panes.**
   `app/views/settings/index.html.erb:40-45` explicitly carves both panes out of
   the index per the 2026-05-10 user-locked restructure: "Slack + Discord panes
   are deliberately NOT on this page — their controllers / routes / partials
   remain so the partial-level view specs and the request specs for the webhook
   controllers keep passing, but they no longer surface on the settings index."
   This means the natural validation path (`/settings` → look for Slack pane →
   paste URL → click `[help]`) does not work today; the user must POST directly
   to `/settings/slack_webhook` / `/settings/discord_webhook` or visit
   `/settings/webhooks/help/slack` `/discord` by hand. Documented in `log.md`
   §01d (open follow-ups). Surface to user during validation: either re-mount
   the panes under a new `## webhooks` settings section, or route them as their
   own page under `/settings/integrations/<provider>` per the original spec
   language. The help modal scaffolding in the layout still works regardless.

2. **[MED] Daily-digest scheduler is install-level, not per-user, but delivers
   per-user.** `NotificationDeliveryChannel` is install-singleton per `kind`
   (one Slack row, one Discord row — no `user_id`, per ADR-0003). The scheduler
   picks up every user whose `last_digest_run_at` cooldown has elapsed and whose
   user-local 09:00 just passed, then fans out a `DailyDigestDeliverJob` per
   user. The job composes from `Digest::Composer.new(user)` but the Composer's
   queries are install-wide (no `where(user: user)` filter — see
   `app/services/digest/composer.rb:93..164`). On an install with N users + a
   Slack webhook configured, the same digest body lands in the same Slack
   channel N times per day. Note: the spec text
   (`01e-daily-digest-scheduler.md:48`) reads `WHERE c.user_id = users.id` which
   assumes per-user channels — but ADR-0003 single-install + multi-user makes
   per-user channels impossible without re-introducing tenancy. Three
   remediation paths:
   - Treat the install as having one digest "owner" — the user whose 09:00 fires
     it. Drop the per-user fan-out; pick the FIRST ripe user install-wide and
     short-circuit the rest until tomorrow.
   - Stamp `last_digest_run_at` only on the **first** user picked per tick, and
     gate subsequent users on that stamp.
   - Document the duplicate-delivery behavior in the Slack/Discord help md and
     the digest scheduler doc comment.

3. **[LOW] `pick_users` EXISTS subquery is uncorrelated.**
   `app/jobs/daily_digest_scheduler_job.rb:77-81` issues
   `EXISTS (SELECT 1 FROM notification_delivery_channels c WHERE c.daily_digest = true)`
   — a CONSTANT predicate (the subquery does not reference `users`). It
   evaluates true install-wide as soon as any channel has `daily_digest` ticked.
   This is logically correct given install-level channels (concern §2), but it
   reads as a bug at first glance and the comment above the query speaks of
   "Users with at least one digest-enabled notification delivery channel" as if
   the channel were per-user. Either rewrite the subquery to
   `WHERE EXISTS (...) FROM dual` style or update the comment to reflect the
   install-wide reality.

4. **[LOW] Race between rapid scheduler ticks still possible across users.** The
   atomic-claim `UPDATE` in `DailyDigestSchedulerJob#perform` (lines 57-60) is
   per-user and protects each user from double-pickup within the same tick.
   Good. But if user A and user B both ripen at the same UTC tick and the
   install has one Slack webhook with `daily_digest: true`, A enqueues a deliver
   job, B enqueues a deliver job — both fire to the same channel within ~1s of
   each other. Same root cause as concern §2; flag together when remediating.

5. **[LOW] `DailyDigestDeliverJob#record_permanent_failure!` uses
   `Time.current.utc.iso8601` in the dedup key.**
   `app/jobs/daily_digest_deliver_job.rb:111` — the dedup key carries the
   wall-clock timestamp at failure time. Two near-simultaneous permanent
   failures one second apart land as two separate `Notification` rows. Probably
   fine for "the operator should see when each one happened" but means a
   flapping channel can clutter the notification list quickly. If noise becomes
   a concern, dedup at the day boundary (`Date.current.iso8601`) or by
   channel-id-only with a periodic reset.

6. **[LOW] `Notification.create!` in `record_permanent_failure!` uses
   `created_by_user: user` but the row is install-level.** Same
   `NotificationDeliveryChannel` install-scope ambiguity — the `created_by_user`
   linkage on a per-channel failure attributes the notification to whichever
   user triggered the failed delivery on this tick. With concern §2 in play, the
   operator sees one row per user per failure rather than one row per failure.
   Worth a comment if `created_by_user` is meant as "the user who tried to
   deliver" vs "the user who owns the channel".

7. **[LOW] `ViewerTimeHeatmapComponent` cell tooltip uses `title=` (browser
   default tooltip).**
   `app/components/viewer_time_heatmap_component.html.erb:28`. The native
   `title` attribute renders with the browser's slow-show delay (~700ms on most
   engines) and is inaccessible to keyboard users. Per `docs/design.md` design
   tokens the project ships a custom tooltip pattern; folding the heatmap onto
   that pattern is a follow-up. Locked as an Open Item in log §01g.

8. **[LOW] `ScheduledPublishHelper#parse_user_local_to_utc` uses
   `local.strftime("%Y-%m-%dT%H:%M:%S") != requested` as the spring-forward gap
   detector.** `app/helpers/scheduled_publish_helper.rb:87-93`. This works
   because `TZInfo` shifts the gap-time forward by an hour silently, and
   `strftime` round-trips through the user-tz which renders the shifted instant
   back as the post-jump wallclock. Two more direct tests exist in `TZInfo`
   itself (`tz.tzinfo.period_for_local(..., dst: false)` raises
   `PeriodNotFound`), but the round-trip approach is library-agnostic and pinned
   by 38 helper specs. Note for future maintainers: the gap detector relies on
   TZInfo's silent-forward-shift contract; a future TZInfo bump that changes the
   behavior would break the detector without breaking the specs.

## Simplification suggestions (non-blocking)

1. **`Digest::SlackRenderer#window_label` and
   `Digest::DiscordRenderer#window_label` are byte-for-byte identical.** Both at
   lines 105-111 of their respective files. Extract a
   `Digest::WindowLabel.call(result, tz)` PORO (or a module method on `Digest`)
   so the two renderers share the formatter. Strict line-count win is 12 lines.

2. **`videos/_viewer_time_tab.html.erb` and `channels/_viewer_time_tab.html.erb`
   are structurally identical, differ only in `scope:` + entity id.** Both
   compute the tz string the same way
   (`Current.user&.time_zone.presence || "Etc/UTC"`) and render the same
   component. A shared partial under
   `app/views/shared/_viewer_time_tab.html.erb` taking `scope:` + `entity:`
   locals would collapse the two. Caller sites each one-line.

3. **`render_publish_at_for_user` has a `case` with a fall-through default that
   duplicates the `:input` branch.** Lines 114-127 of
   `app/helpers/scheduled_publish_helper.rb` — the `else` returns the same
   `strftime("%Y-%m-%dT%H:%M")` as the `:input` branch. Drop the `else` and let
   the default `format:` value carry the intent. Tiny but the surface reads
   cleaner.

4. **`Digest::Composer::Result` and `Digest::Composer::Section` are independent
   struct definitions with overlap.** Both define `empty?` / `any_activity?`
   semantics. The Section.empty? pattern (`total.to_i.zero?`) could be lifted up
   so Result delegates. Marginal.

5. **`VideoViewerTimeBucket.resolve_iana` is class-level utility that doesn't
   belong on the AR model.** It's pure Ruby with no AR dependencies; could live
   as `Analytics::TzResolver.iana(tz)` so the model surface stays domain-only.
   Currently the model also owns the single SQL query for `rolled_up_to_tz` —
   extracting both (`resolve_iana` + the rollup SQL) to
   `Analytics::ViewerTimeRollup` keeps the AR model lean. Minor.

## Manual test steps

### Preconditions

1. **Docker services running.**

   ```sh
   docker ps | grep -E "(postgres|redis)"
   ```

   Both must show `Up` and `(healthy)`. If not, `bin/dev` will start the compose
   stack automatically.

2. **Dev stack running.**

   ```sh
   bin/dev
   ```

   Wait until Puma logs `Listening on http://0.0.0.0:3027`, Sidekiq logs
   `Booting Sidekiq`, and Tailwind watcher logs `Built in <Nms>`.

3. **Database migrations applied.**

   ```sh
   bin/rails db:migrate:status | grep -E "(time_zone|last_digest_run_at|viewer_time_buckets|notification_delivery_channels)"
   ```

   Expect all four to read `up`.

4. **Owner login confirmed.**

   ```sh
   bin/rails runner 'puts User.first.email'
   ```

   Note the email. The seed creates a single owner per `docs/setup.md`.

5. **`Webhook URL` to use (Slack, get from your Slack workspace):**
   `https://hooks.slack.com/services/Txxxxxxxx/Bxxxxxxxx/xxxxxxxxxxxxxxxxxxxxxxxx`
   Discord: `https://discord.com/api/webhooks/<id>/<token>` from any test
   server.

### Backend smoke tests (run from terminal)

6. **Backfill rake task happy path.**

   ```sh
   bin/rails pito:backfill_viewer_time_buckets DAYS=7
   ```

   Expect output `enqueued 0 viewer-time sync jobs (DAYS=7).` if no videos are
   owned yet. With at least one owned video, expect the count to match
   `Video.joins(channel: :youtube_connection).where(youtube_connections: { needs_reauth: false }).count`.

7. **Backfill rake task validates DAYS.**

   ```sh
   bin/rails pito:backfill_viewer_time_buckets DAYS=0
   ```

   Expect abort with `DAYS must be a positive integer (got "0").`

8. **Daily-digest cron registered.**

   ```sh
   bin/rails runner 'puts Sidekiq::Cron::Job.all.find { |j| j.name == "daily_digest_scheduler" }&.cron'
   ```

   Expect `0 * * * *`.

9. **Viewer-time refresh cron registered.**

   ```sh
   bin/rails runner 'puts Sidekiq::Cron::Job.all.find { |j| j.name == "viewer_time_daily_refresh" }&.cron'
   ```

   Expect `0 3 * * *`.

10. **Force the digest scheduler to consider the owner now.**

    ```sh
    bin/rails runner '
      u = User.first
      u.update_column(:last_digest_run_at, 25.hours.ago)
      u.update!(time_zone: ActiveSupport::TimeZone[Time.now.hour - 9].name || "Etc/UTC")
      puts "User#" + u.id.to_s + " ready: tz=" + u.time_zone + " stamp=" + u.last_digest_run_at.iso8601
    '
    ```

    Adjust `time_zone` so the user's local clock is at 09:xx UTC now. Easiest:
    set tz to `"Etc/UTC"` and run the test at 09:00 UTC, OR set
    `last_digest_run_at` back 24h and pick a tz where local 09:00 was within the
    last hour.

11. **Run the scheduler inline.**
    ```sh
    bin/rails runner 'DailyDigestSchedulerJob.new.perform'
    ```
    Tail the Sidekiq log (`bin/jobs` console output) — expect one
    `DailyDigestDeliverJob` enqueue per ripe user. Wait ~5s for it to process.
    With no `daily_digest=true` channel configured, the deliver job no-ops
    (returns early at line 50).

### UI walkthrough

(continued in `## User Validation` at the bottom)

## Cleanup

If you want to retry from scratch:

```sh
# Reset the user's tz + digest stamp.
bin/rails runner '
  u = User.first
  u.update!(time_zone: "Etc/UTC", last_digest_run_at: Time.current)
  puts "reset user" + u.id.to_s
'

# Drop all webhook channels.
bin/rails runner 'NotificationDeliveryChannel.delete_all'

# Drop all viewer-time buckets.
bin/rails runner 'VideoViewerTimeBucket.delete_all'

# Drop any digest_delivery_failed notifications.
bin/rails runner 'Notification.where(event_type: "digest_delivery_failed").delete_all'
```

To re-pull the development DB to a clean state:

```sh
bin/rails db:rollback STEP=2
bin/rails db:migrate
```

(rolls back `add_last_digest_run_at_to_users` +
`create_video_viewer_time_buckets` then replays them — destructive on the two
columns/table only.)

## User Validation

The Phase 26 surfaces split across three browser areas: `/settings` (timezone
pane, webhook panes — see Blocker §1 / Concern §1 for the carve-out), the
webhook help modal at `/settings/webhooks/help/<provider>`, the video edit page
(scheduled-publish picker), and the per-video / per-channel analytics pages
(viewer-time heatmap).

Each step below is observable from the browser alone. Steps that depend on prior
backend smoke setup (preconditions 1–5) assume those are done.

[ ] 1. **Set your timezone via Settings.** Open `/settings` in a fresh browser
session (Cmd-Shift-N for a new private window forces a clean Stimulus mount).
Scroll to `## customize` → row 2 → `your time zone` pane. The dropdown should
pre-fill to `Etc/UTC` (or whatever your browser's first-load detection wrote —
open DevTools → Network and look for a `PATCH /settings/time_zone` firing
silently on first load). Pick `Europe/Bucharest` from the `common` optgroup.
Click `[update]`. The page redirects and the dropdown re-renders with
`Europe/Bucharest` selected. The flash reads "your timezone is now
Europe/Bucharest" (or similar copy — verify it's not red and does not include
the word "error").

[ ] 2. **Verify the timezone applies app-wide.** Open `/videos` (any video). The
card timestamps (`created_at`, `last_synced_at`) should render in
`Europe/Bucharest` wallclock, not UTC. If a video has no timestamps yet,
navigate to `/notifications` instead — the `fired        at` column should
render in `EEST` / `EET` depending on the season.

[ ] 3. **Open the scheduled-publish picker on a draft video.** Navigate to
`/videos` → pick any video whose `privacy_status` is `private`. On the edit
page, find the `[schedule]` bracketed link (typically near the privacy badge).
Click it. A modal opens with `publish at        (Europe/Bucharest)` as the input
label. The hint text reads "times are interpreted in your time zone
(Europe/Bucharest). stored as UTC." Pick `2026-06-01T09:00`. Tick all four
checklist boxes. Click `[confirm schedule]`. The page redirects back to the
video show page; a `scheduled` badge appears.

[ ] 4. **DST gap rejection (US zone).** Go back to `/settings` and change your
timezone to `America/Los_Angeles`. On the video edit page, click `[schedule]`
again. Pick `2026-03-08T02:30` (a spring-forward day in the US — 02:00 jumps to
03:00, so 02:30 does not exist). Tick all four checklist boxes. Submit. The form
re-renders with an inline error reading "That time does not exist due to DST
spring-forward." (or similar copy — verify it contains "DST" and is not green).

[ ] 5. **Verify the timezone round-trip preserves the stored UTC.** Set your tz
back to `Europe/Bucharest`. Reload the video edit page. The `scheduled for:`
line should render `Jun 1, 2026 09:00 EEST` (the original picker value). Change
tz to `America/Los_Angeles`. Reload. Same line now reads
`May 31, 2026 23:00 PDT` (same UTC instant, different local clock).

[ ] 6. **Open the Slack webhook help modal directly.** Visit
`/settings/webhooks/help/slack` in your address bar. The page renders the
Markdown-rendered Slack setup guide — verify it contains the headings "Slack",
"step 1", "step 2", and a "Troubleshooting" section near the bottom with the
sub-paths "Invalid URL", "Ping failed: 404 / 410 / 403", and "Connection
timeout". The body uses monospace prose with NO `class="anchor"` links next to
headings and NO inline-styled syntax highlighting (the `plain: true` Markdown
render).

[ ] 7. **Open the Discord webhook help modal directly.** Visit
`/settings/webhooks/help/discord`. Same shape as step 6 but tuned for Discord —
verify it spells out the "Manage Webhooks" permission prerequisite and lists
both `discord.com` and `discordapp.com` host forms as accepted.

[ ] 8. **Confirm the unknown-provider 404 path.** Visit
`/settings/webhooks/help/mars`. Expect a Rails 404 page (in dev, you'll see the
dev exception page reading "No route matches" — this is the test-env flavour
from Blocker §1; in production it would be the bare 404.html). The
`slack|discord` route constraint is doing its job either way.

[ ] 9. **Slack webhook configuration via direct POST (concern §1 workaround).**
Open DevTools → Network. Submit a Slack URL via the direct route (or curl with
cookie-jar from terminal):
`sh        curl -X PATCH http://127.0.0.1:3027/settings/slack_webhook \          -b cookies.txt \          -d 'slack_webhook[webhook_url]=https://hooks.slack.com/services/T00000000/B00000000/000000000000000000000000' \          -d 'slack_webhook[everything]=no' \          -d 'slack_webhook[daily_digest]=yes'        `
Expect HTTP 422 if the URL fails the test-ping (404 from Slack since the URL is
fake) — the response body re-renders the pane partial with the test-ping error.
Replace with a real Slack webhook URL; expect a 302 redirect to `/settings` and
the row appears in `bin/rails runner 'pp NotificationDeliveryChannel.slack'`.
The test message "Pito test ping — Slack webhook configured." lands in the Slack
channel.

[ ] 10. **Discord webhook configuration via direct POST.** Mirror step 9 with
`/settings/discord_webhook`:
`sh         curl -X PATCH http://127.0.0.1:3027/settings/discord_webhook \           -b cookies.txt \           -d 'discord_webhook[webhook_url]=https://discord.com/api/webhooks/<id>/<token>' \           -d 'discord_webhook[everything]=no' \           -d 'discord_webhook[daily_digest]=yes'         `
Same shape — 422 on bad URL, 302 + test ping landing on success.

[ ] 11. **Daily digest delivery dry-run.** With both webhook rows in place and
`daily_digest: true`, run preconditions §10 to back-stamp `last_digest_run_at`.
Run preconditions §11 to fire the scheduler. Tail Sidekiq output (the `bin/dev`
console pane); expect: - `DailyDigestSchedulerJob` completes, logs no errors. -
`DailyDigestDeliverJob` enqueues and processes within ~5s. - The Slack channel
receives the digest (header "pito daily digest", a context block with the window
range, one section per non-empty category, divider blocks between). - The
Discord channel receives the digest (top-line "pito daily digest" content, one
embed with title / description / fields).

[ ] 12. **Permanent-failure path produces a Notification row.** Update the Slack
webhook to a syntactically-valid but server-side-410 URL (use a real format
string but a known-bad token). Run the scheduler inline again (precondition
§11). Expect: - The deliver job posts to Slack and receives a 410 (or 404). -
`bin/rails runner 'pp Notification.where(event_type: "digest_delivery_failed").last'`
returns a row with `kind: "sync_error"`, `severity: "warn"`,
`title: "digest delivery failed (slack)"`, `body` containing the channel id and
the upstream error. - The row appears in `/notifications` UI.

[ ] 13. **Viewer-time heatmap on the per-video analytics page (empty state).**
Navigate to `/videos/<slug>/analytics` for any owned video. Scroll to the bottom
— there is a `<h2>viewer-time         heatmap</h2>` section. With no buckets
seeded yet, the empty-state paragraph reads "no viewer-time data yet — sync runs
daily at 03:00 server time."

[ ] 14. **Seed buckets and reload.** Run:
`sh         bin/rails runner '           v = Video.joins(channel: :youtube_connection).first           168.times do |i|             VideoViewerTimeBucket.upsert_all([{               video_id: v.id,               day_of_week_utc: i / 24,               hour_of_day_utc: i % 24,               view_count: rand(0..50),               watch_time_seconds: rand(0..3600),               last_synced_at: Time.current,               created_at: Time.current,               updated_at: Time.current             }], unique_by: %i[video_id day_of_week_utc hour_of_day_utc])           end           puts "seeded 168 buckets for video " + v.id.to_s         '         `
Reload the analytics page. The heatmap grid renders 7 rows × 24 columns. Each
cell has a single-hue blue tint (alpha ~`cell/max`). Empty cells render with the
pane-background baseline (no fill). Verify there is NO red anywhere in the grid.

[ ] 15. **Heatmap tooltip and intensity legend.** Hover any non-zero cell — the
browser native tooltip shows `<day> <HH>:00 — N views,         Ms watched`. The
`<header>` of the section displays `tz:         Europe/Bucharest` (or whatever
your current zone is) and `intensity: views`.

[ ] 16. **Heatmap respects timezone — shift to Tokyo.** Open `/settings` and
change tz to `Asia/Tokyo`. Reload `/videos/<slug>/analytics`. The heatmap cells
re-bucket — the peak hours visibly shift by ~9 hours horizontally compared to
the Bucharest render (since Tokyo is UTC+9 vs Bucharest UTC+2/3). Header now
reads `tz: Asia/Tokyo`.

[ ] 17. **Per-channel viewer-time heatmap.** Navigate to
`/channels/<slug>/analytics`. Scroll to the bottom — same viewer-time heatmap
section, aggregated across every video on the channel. Single-hue blue, no red.

[ ] 18. **Architecture doc sections exist.** Open `/docs/architecture.md` (or
`cat docs/architecture.md | grep -n         "Phase 26"` from terminal). Verify
two new top-level sections are present:
`## Timezone rendering rule (Phase 26 — 01a /         01f)` near line 457 and
`## Viewer-time aggregation (Phase 26 —         01g)` near line 557. Both render
in the docs MCP tool (`read_doc` with `path: "architecture.md"`) without errors.

[ ] 19. **Help-modal markdown content lockdown.** Inside the rendered
`/settings/webhooks/help/slack` guide, verify every numbered step spells out
where to click and what the screen looks like — no assumed Slack-admin
knowledge. The "Troubleshooting" section at the bottom covers: Invalid-URL,
Ping-failed 404/410/403, Connection-timeout, Channel-disappeared, Start-over
paths. Repeat for `/discord` — covers Invalid-URL, Ping-failed 404/401,
Missing-menu permission error, Connection-timeout, Channel-disappeared,
Start-over.

[ ] 20. **Sidekiq Web shows the registered cron entries.** Visit `/sidekiq`
(HTTP basic auth required — credentials in `config/credentials.yml.enc` →
`:sidekiq` block). Go to the Cron tab. Verify `daily_digest_scheduler` (cron
`0 * * * *`) and `viewer_time_daily_refresh` (cron `0 3 * * *`) are both listed
and enabled.

[ ] 21. **Sign-off.** All 20 steps green, blockers triaged, concerns noted for
follow-up.
