# 01c — Post-Publish Workflow

> Parent: `docs/plans/beta/11-video-workflow-features/plan.md`.
> Parallel-dispatchable with `01d` and `01e` once `01a` lands.

---

## Goal

After a video flips `published_at` (either via `VideoPublish` scheduled publish
or via the import flow setting it on first sync), Phase 11 fires two follow-up
notifications on a configurable cadence:

- `video_comments_due` at `published_at + comments_window_hours` — prompts the
  user to reply to viewer comments. Default `comments_window_hours = 24`.
- `video_analytics_due` at `published_at + analytics_window_days` — prompts the
  user to review analytics. Default `analytics_window_days = 7`.

Cadence defaults live on `AppSetting`. Per-channel overrides live on
`channels.post_publish_comments_window_hours` and
`channels.post_publish_analytics_window_days` (nullable; nil means "use the
install default"). The scheduler reads channel override first, falls back to
install default.

Each notification ALSO derives a `CalendarEntry` via the Phase 15
`CalendarDerivable` concern on `Video`, so the calendar surface reflects the
pending reminders.

---

## Files touched

### Migrations

- `db/migrate/<TS>_add_post_publish_cadence_to_app_settings.rb` — adds
  `post_publish_comments_window_hours` (integer, default 24, NOT NULL) and
  `post_publish_analytics_window_days` (integer, default 7, NOT NULL).
- `db/migrate/<TS>_add_post_publish_cadence_overrides_to_channels.rb` — adds
  `post_publish_comments_window_hours` (integer, nullable) and
  `post_publish_analytics_window_days` (integer, nullable).

### Models

- `app/models/app_setting.rb` — expose the two new accessors; validate `>= 1`.
- `app/models/channel.rb` — expose the two new accessors; validate `>= 1` when
  present.
- `app/models/video.rb` — extend `CALENDAR_DERIVATION_FIELDS` and the
  `calendar_entry_type` / `calendar_entry_attributes` /
  `calendar_entry_source_ref` paths to handle the two new entry kinds
  (multi-derivation — see open question §1).
- `app/models/calendar_entry.rb` — add two enum values to the existing
  `entry_type` enum: `:video_comments_due`, `:video_analytics_due`.
- `app/models/notification.rb` (or whichever Phase 16 model holds the enum) —
  add two enum values to the existing `kind` enum: `:video_comments_due`,
  `:video_analytics_due`.

### Services

- `app/services/videos/post_publish_cadence_resolver.rb` (new) —
  `.new(video).comments_window_hours` and `.analytics_window_days`. Reads
  channel override → AppSetting default. Memoizes per instance.

### Jobs

- `app/jobs/videos/schedule_post_publish_job.rb` (new) — Sidekiq job enqueued by
  `VideoPublish` after a successful publish. Computes the two scheduled times
  via the resolver. Enqueues two `Notifications::FireNotificationJob` jobs
  (Phase 16 surface) at `published_at + window`. Idempotent: re-enqueue on a
  re-publish replaces prior pending jobs (track the Sidekiq `jid` on the
  Notification row; cancel prior `jid`s before enqueueing new ones).

### Controllers

- `app/controllers/channels_controller.rb` — extend `channel_params` to permit
  the two override fields.
- `app/controllers/settings/notifications_controller.rb` (or whichever Phase 16
  controller holds the notification settings) — extend `app_setting_params` to
  permit the two default fields.

### Views

- `app/views/channels/_form.html.erb` — add two new number inputs under a
  "post-publish cadence" sub-section. Empty input = "use install default" copy.
- `app/views/settings/notifications/edit.html.erb` (or wherever Phase 16
  surfaces it) — add the two default fields.
- `app/views/notifications/_video_comments_due.html.erb` (new) — render the
  notification body with action `[reply to comments]` linking to
  `https://studio.youtube.com/video/<youtube_video_id>/comments`.
- `app/views/notifications/_video_analytics_due.html.erb` (new) — render with
  action `[review analytics]` linking to the pito video analytics page
  (`/videos/:youtube_video_id/analytics` or whichever Phase 13 route exposes
  it).

### Routes

- `config/routes.rb` — no new routes.

### Specs

- `spec/models/app_setting_spec.rb` — extend with validation cases for the two
  new fields.
- `spec/models/channel_spec.rb` — extend with validation cases for the two
  override fields.
- `spec/models/video_spec.rb` — extend the `CalendarDerivable` examples to cover
  the two new entry types.
- `spec/services/videos/post_publish_cadence_resolver_spec.rb` (new) — happy
  (override set), happy (override nil, default used), edge (override `0` —
  invalid), flaw (channel nil).
- `spec/jobs/videos/schedule_post_publish_job_spec.rb` (new) — happy (enqueues
  two notifications), idempotent (re-enqueue on re-publish replaces prior
  `jid`s), edge (publish fails — no jobs enqueued), flaw (resolver returns nil —
  job no-ops with a logged warning).
- `spec/requests/channels_spec.rb` — extend to cover override field edit +
  persistence.
- `spec/requests/settings/notifications_spec.rb` — extend to cover default field
  edit.
- `spec/system/post_publish_workflow_spec.rb` (new) — system spec: publish a
  video with `Sidekiq::Testing.inline!`; observe the two calendar entries appear
  at the resolved offsets; override the channel cadence and republish; calendar
  entries update.

---

## Acceptance

- [ ] `AppSetting#post_publish_comments_window_hours` defaults to `24`,
      validated `>= 1`.
- [ ] `AppSetting#post_publish_analytics_window_days` defaults to `7`, validated
      `>= 1`.
- [ ] `Channel#post_publish_comments_window_hours` nullable, validated `>= 1`
      when present.
- [ ] `Channel#post_publish_analytics_window_days` nullable, validated `>= 1`
      when present.
- [ ] `Videos::PostPublishCadenceResolver.new(video).comments_window_hours`
      returns channel override when set; AppSetting default otherwise.
- [ ] Same shape for `analytics_window_days`.
- [ ] `Videos::SchedulePostPublishJob` enqueues two
      `Notifications::FireNotificationJob` jobs at `published_at +     window`,
      with the `Notification#kind` set correctly.
- [ ] Re-publish replaces prior pending notification jobs (cancel by `jid`
      before re-enqueue).
- [ ] `CalendarEntry` rows are derived for the two new kinds via the
      `CalendarDerivable` concern on `Video`.
- [ ] Cancellation: acknowledging via the notification action flips the
      `CalendarEntry.state` to `:occurred`.
- [ ] Per-channel override edit on `/channels/:id/edit` persists and takes
      effect immediately for new publishes.
- [ ] AppSetting defaults edit on the notifications settings page persists and
      takes effect immediately for new publishes.
- [ ] Yes/no boundary — no Boolean external inputs in v1; reserved guard
      documented inline.
- [ ] Friendly URLs preserved on every touched route.
- [ ] `bundle exec rspec` green on every new + extended spec file.

---

## Manual test recipe

1. `bin/rails db:migrate` (adds the four cadence columns).
2. `bin/rails console`:
   ```ruby
   AppSetting.instance.update!(
     post_publish_comments_window_hours: 24,
     post_publish_analytics_window_days: 7
   )
   ```
3. `bin/dev` → visit `/settings/notifications`; confirm the two defaults render
   and are editable.
4. Visit `/channels/<id>/edit`; confirm the two override fields render. Leave
   blank → the form copy reads "uses install default (24 hours / 7 days)".
5. `bin/rails console`:
   ```ruby
   video = Video.find_by!(youtube_video_id: '<yt_id>')
   video.update!(privacy_status: :public, published_at: Time.current)
   ```
6. Visit `/calendar` (or whichever Phase 15 surface renders entries); confirm
   two new entries appear: `video_comments_due` 24 h out, `video_analytics_due`
   7 d out.
7. Override the channel cadence to 1 / 1 (1 hour / 1 day). Reset the video:
   ```ruby
   video.update!(privacy_status: :private, published_at: nil)
   video.update!(privacy_status: :public, published_at: Time.current)
   ```
   Confirm the calendar entries update to 1 h / 1 d out.
8. Run `Sidekiq::Testing.inline!` mode in a spec session to confirm the
   notifications fire at the expected times (the system spec covers this; manual
   confirmation is the calendar surface).
9. Acknowledge the `video_comments_due` notification via `[reply to comments]`;
   confirm the calendar entry flips to `:occurred`.
10. `bundle exec rspec` — green.

---

## Cross-stack scope

| Surface            | Status                                      |
| ------------------ | ------------------------------------------- |
| Rails web          | IN SCOPE                                    |
| Rails MCP          | DEFERRED — captured in sub-spec `01f`       |
| `pito` CLI (Rust)  | DEFERRED — MCP/TUI pause; captured in `01f` |
| Cloudflare website | OUT OF SCOPE                                |

---

## Open questions

1. **Multi-derivation on `CalendarDerivable`.** The Phase 15 concern today
   assumes a host derives **one** entry per row (per `(entry_type, source_ref)`
   upsert). `Video` already derives one `:video_published` OR one
   `:video_scheduled` entry. Phase 11 adds two more entries that should coexist
   with the published / scheduled entry. The fix: `calendar_entry_attributes`
   returns an array of hashes (one per derived entry), each keyed by its own
   `calendar_entry_source_ref`. The concern's upsert path iterates. Locked
   decision — surface for user lock if the architect prefers a separate
   `MultiCalendarDerivable` concern instead.
2. **Notification action — pito analytics URL.** The analytics URL shape depends
   on Phase 13's surface. Architect proposes
   `/videos/:youtube_video_id/analytics`. Surface for user lock if a different
   shape is canonical.
3. **Acknowledge flow.** Clicking `[reply to comments]` opens YouTube Studio in
   a new tab. Does that count as "acknowledge"? Architect leans yes — the act of
   clicking the action link flips the calendar entry to `:occurred`. If the user
   wants explicit "mark as done" UX, surface as a follow-up.
4. **Re-publish replace strategy.** Idempotent re-enqueue requires tracking the
   prior `jid` on the Notification row. If the Phase 16 model doesn't carry a
   `sidekiq_jid` column, this sub-spec adds it (open question for the
   implementation agent to confirm against the live schema).
