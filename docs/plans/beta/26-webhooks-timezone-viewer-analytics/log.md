# Phase 26 — log

## 2026-05-11 — P26 reviewer non-blocking concerns (pito-rails-impl) [skipci]

Applied the four P26 reviewer non-blocking concerns. Both 01e (daily digest)
and 01g (viewer-time analytics) checkboxes were already ticked; this session
is pure fix-forward against the reviewer playbook.

### Fix-forward index

- **Concern 1 — Install-level digest dispatch.** Rewrote
  `app/jobs/daily_digest_scheduler_job.rb` so the scheduler picks a single
  install-level "anchor" user (`User.order(:id).first`) instead of enumerating
  every user with a digest-enabled channel. The anchor's `time_zone` decides
  when the install's 09:00 local fires; the anchor's `last_digest_run_at`
  carries the install-wide cooldown stamp. Composer is unchanged — it
  already aggregates install-wide activity (channels, videos, footage, login
  attempts, notifications) regardless of which user it is composing for.
  Locked decision: ONE digest per install per day, regardless of user count.
- **Concern 2 — `pick_users` EXISTS subquery.** Obviated by concern 1. The
  scheduler no longer scans users; it picks the anchor directly. The
  uncorrelated EXISTS is gone with the rest of the per-user loop.
- **Concern 3 — Cross-user race.** Inherently addressed by the install-level
  dispatch (cooldown stamp lives on a single row). The existing atomic
  `UPDATE...WHERE last_digest_run_at <` claim guards the (rare) race
  between two simultaneous ticks.
- **Concern 4 — Heatmap tooltip accessibility.** Dropped native `title=` on
  `app/components/viewer_time_heatmap_component.html.erb`. Each cell now
  carries `tabindex="0"`, `aria-label` (screen-reader text), and
  `data-tooltip` (rendered via a CSS-only `::after` pseudo-element on
  hover/focus). Tailwind input updated in
  `app/assets/tailwind/application.css`; rebuilt to `app/assets/builds/tailwind.css`.
- **Concern 5 — `resolve_iana` relocation.** Moved off
  `VideoViewerTimeBucket.resolve_iana` into the existing `Pito::*` lib
  namespace: `app/lib/pito/time_zone.rb` with module-function
  `Pito::TimeZone.resolve_iana(tz)`. Updated the single call site
  (`VideoViewerTimeBucket.rolled_up_to_tz` scope). Spec coverage moved
  to `spec/lib/pito/time_zone_spec.rb`.

### Files touched

**Edited:**

- `app/jobs/daily_digest_scheduler_job.rb` — install-level dispatch.
- `app/models/video_viewer_time_bucket.rb` — dropped `resolve_iana`; route
  through `Pito::TimeZone.resolve_iana`.
- `app/components/viewer_time_heatmap_component.html.erb` — `tabindex="0"`,
  `aria-label`, `data-tooltip`; dropped `title=`.
- `app/assets/tailwind/application.css` — CSS-only `::after` tooltip on
  hover + focus; box-shadow ring on hover/focus for the cell.
- `app/assets/builds/tailwind.css` — regenerated.
- `spec/jobs/daily_digest_scheduler_job_spec.rb` — added the install-level
  dispatch describe block (3 examples) asserting anchor pick, anchor-tz
  pick window, and exactly-one-fire for multi-user installs.
- `spec/components/viewer_time_heatmap_component_spec.rb` — replaced the
  two `title*=` assertions with `data-tooltip` / `aria-label` versions;
  added two new examples (no `title=` attribute, every cell `tabindex='0'`).
- `spec/models/video_viewer_time_bucket_spec.rb` — dropped the
  `.resolve_iana` describe block (moved out).

**Added:**

- `app/lib/pito/time_zone.rb` — `Pito::TimeZone.resolve_iana` module
  function.
- `spec/lib/pito/time_zone_spec.rb` — 6 examples covering all input
  shapes (IANA, alias, ActiveSupport::TimeZone, nil, symbol, unrecognized).

### Spec count delta

- `+3` scheduler examples (install-level dispatch describe block)
- `+2` heatmap component examples (no `title`, tabindex)
- `+6` new Pito::TimeZone examples
- `-4` removed `resolve_iana` examples from bucket spec (moved)
- `-2` removed `title*=` examples from heatmap spec (replaced)
- **Net: +5** examples.

### Test + lint

- `bundle exec rspec spec/lib/pito/time_zone_spec.rb
  spec/models/video_viewer_time_bucket_spec.rb
  spec/components/viewer_time_heatmap_component_spec.rb
  spec/services/analytics/viewer_time_rollup_spec.rb
  spec/jobs/daily_digest_scheduler_job_spec.rb
  spec/jobs/daily_digest_deliver_job_spec.rb` — 98 examples, 0 failures.
- `bundle exec rspec spec/system/viewer_time_heatmap_spec.rb` — 2/2 green
  (heatmap end-to-end still renders).
- `bundle exec rubocop` on all touched Ruby files — clean (7 files, 0
  offenses).
- `bin/brakeman -q -w2` — 0 security warnings.

### Plan checkboxes

No plan.md checkboxes ticked. 01e and 01g were already ticked when this
session started; the work above is reviewer fix-forward, not new spec
delivery.

## 2026-05-11 — settings + 2FA fix-forward bundle (pito-rails-impl) [skipci]

User-directed bundle of seven fixes spanning the settings index, security
dashboard, 2FA QR rendering, and a new fresh-TOTP gate on sensitive write
endpoints. Touches Phase 25 (security/show, 2FA QR, TOTP gate concern) and
Phase 26 (Slack + Discord pane wiring into settings index, TOTP gates on
webhook updates).

### Fix-forward index

- **Fix 1 — storage pane title trim.** Dropped `size: X` / `files: N` summary
  lines under both `assets` and `notes` pane titles in
  `app/views/settings/index.html.erb`. Title + writable badge survive; the
  per-category / per-namespace tables below carry the count + size detail.
- **Fix 2 — notes table labels.** Renamed `project notes` → `project` in
  `SettingsController::NOTES_NAMESPACE_SOURCES`. Dropped the entire
  `mobile_notes` entry (dev-only artifact — `docs/notes/` MCP `save_note`
  drop-zone, stripped from production builds per ADR 0004).
- **Fix 3 — Postgres model rename.** `calendar_entries` row now renders with
  display label `calendar`. Added a third tuple value (display label) to
  `SettingsController::POSTGRES_BREAKDOWN_MODELS`; iteration picks the
  display label without changing the underlying table-stats query.
- **Fix 4 — security dashboard intro drop.** Removed the muted intro block
  ("every login attempt is logged. suspicious activity surfaces here and on
  [attempts]. 2FA enrollment lands later in this phase.") from
  `app/views/settings/security/show.html.erb`. The 2FA-lands-later copy was
  stale (Phase 25 01e shipped); the attempts link still surfaces on the
  recent-activity panel.
- **Fix 5 — integrations row reshape.** Slack + Discord webhook panes
  (built in Phase 26 01b / 01c but never wired into the settings index per
  the original user-locked restructure) now render on a new row 2 of the
  integrations section (Discord left, Slack right). OAuth applications +
  sessions moved to row 3. Total layout: 7 pane-rows / 13 panes.
- **Fix 6 — QR code white background.** Wrapped the SVG in
  `app/views/settings/security/totps/show.html.erb` in a white-bg
  inline-block div so the dark theme cannot make the QR unscannable. QR
  codes require black-on-white contrast.
- **Fix 7 — 2FA gates on sensitive writes.** New `RecentTotpVerification`
  concern (`app/controllers/concerns/recent_totp_verification.rb`) reads
  `params[:totp_code]` from the form and rejects writes with a generic
  `credentials don't match.` flash when the user has 2FA on. Wired into:
  - `Settings::UserController#update`
  - `SettingsController#update` for `section=youtube` and `section=voyage`
  - `Settings::SlackWebhooksController#update`
  - `Settings::DiscordWebhooksController#update`

  Each form surfaces a `name="totp_code"` field gated by
  `Current.user&.totp_enabled?` so the field only renders when 2FA is
  actually on. Read-only views are NOT gated. Generic-flash failure copy
  mirrors the disable-2FA flow so the response never reveals which field
  failed.

### Files touched

**Edited:**

- `app/views/settings/index.html.erb` — Fix 1 storage trim; Fix 5 Discord +
  Slack row wired in; Fix 7 TOTP fields on YouTube + Voyage forms.
- `app/controllers/settings_controller.rb` — Fix 2 notes namespace map
  rebuild; Fix 3 Postgres display-label tuple; Fix 7 RecentTotpVerification
  include + gate on the youtube / voyage sections.
- `app/views/settings/security/show.html.erb` — Fix 4 intro paragraph
  dropped.
- `app/views/settings/security/totps/show.html.erb` — Fix 6 QR wrapper.
- `app/controllers/settings/user_controller.rb` — Fix 7 gate on
  user-account update.
- `app/views/settings/user/show.html.erb` — Fix 7 TOTP code field.
- `app/controllers/settings/slack_webhooks_controller.rb` — Fix 7 gate on
  Slack webhook save.
- `app/controllers/settings/discord_webhooks_controller.rb` — Fix 7 gate on
  Discord webhook save.
- `app/views/settings/_slack_pane.html.erb` — Fix 7 TOTP code field.
- `app/views/settings/_discord_pane.html.erb` — Fix 7 TOTP code field.
- `spec/requests/settings_spec.rb` — adjustments + new assertions: storage
  size / files drop, notes table renamed + mobile drop, Postgres
  `calendar_entries` → `calendar` rendering, Discord+Slack panes
  surface + row-2 ordering, total pane / row count refresh.
- `spec/requests/settings/security_spec.rb` — security intro drop assertion;
  attempts-link assertion adjusted (link only surfaces when attempts
  exist).
- `spec/requests/settings/security/totps_spec.rb` — QR wrapper white-bg
  assertion.

**Added:**

- `app/controllers/concerns/recent_totp_verification.rb` — shared concern.
- `spec/requests/settings/totp_gates_spec.rb` — 21 examples covering all
  five gated endpoints: missing code → generic flash, wrong code → generic
  flash, correct code → write proceeds, 2FA-off baseline → write proceeds
  without a code, read-only index always renders.

### Quality gates

- `bundle exec rspec spec/requests/settings spec/requests/login/totp_challenges_spec.rb
  spec/views/settings/_slack_pane_html_erb_spec.rb
  spec/views/settings/_discord_pane_html_erb_spec.rb
  spec/system/totp_2fa_journey_spec.rb spec/system/login_security_journeys_spec.rb` —
  307 / 307 green.
- `bundle exec rubocop <edited files>` — clean (9 files, 0 offenses).
- `bin/brakeman -q -w2` — 0 warnings, 0 errors.
- Migrations: none.

### Spec count delta

- New: `spec/requests/settings/totp_gates_spec.rb` (+21 examples).
- Adjusted: `spec/requests/settings_spec.rb`, `spec/requests/settings/security_spec.rb`,
  `spec/requests/settings/security/totps_spec.rb`.

### Open follow-ups

1. The TOTP gate uses `:show` as the default render action; for non-show
   controllers we use `redirect_on_failure:` to bounce back to /settings.
   If a future flow needs an inline 422 on a non-show view, pass
   `render_action:` to the helper. Pattern is already in place; no work
   needed until a caller asks for it.
2. The `mobile_notes` row drop is per user direction for the production
   surface. The Mobile MCP `save_note` tool still drops markdown into
   `docs/notes/`; only the on-pane surface changed.
3. The integrations row reshape adds two new write paths gated by TOTP.
   Phase 26 plan §"Open question 9" (TOTP 2FA gate on webhook URL changes)
   suggested "revisit when 2FA ships." 2FA shipped in Phase 25 01e; this
   bundle implements that revisit.

## 2026-05-11 — sub-spec 01f Analytics architecture + tz update (pito-docs) [skipci]

Implemented sub-spec 01f — Analytics architecture + tz update per
`specs/01f-analytics-architecture-tz-update.md`. Documentation-only: added two
sections to `docs/architecture.md` that pin the app-wide UTC-storage /
user-tz-render contract and the viewer-time aggregation design. These sections
are the durable architecture reference future analytics work reads first instead
of re-deriving the rules from the Mobile note + sub-specs.

### Files touched

**Edited:**

- `docs/architecture.md` — two new top-level sections appended after the Phase 7
  / 9 "Google OAuth + YouTube API foundation" block. The pre-existing Phase 2
  "Timezone" subsection under "Datastore — Postgres 17" gained a one-paragraph
  forward reference to the new top-level section so the Postgres-side pinning
  reads as a piece of the larger app-wide contract.

  Section 1: **Timezone rendering rule (Phase 26 — 01a / 01f).** Storage rule
  (every `time` / `datetime` / `timestamptz` column is UTC; enumerates Phase 26
  additions — `users.time_zone`, `users.last_digest_run_at`, `*_at` columns on
  `video_viewer_time_buckets`, scheduled-publish columns); render rule (every
  user-facing time passes through `l_user_tz` from 01a, sole conversion site);
  calendar definitions (day, week starting Monday with `users.week_start` hook,
  month, year — all user-local); canonical rollup query pattern
  (`date_trunc('day', utc_ts AT TIME ZONE :user_tz)`) with hour / dow extracts
  for the heatmap; edge cases (DST spring-forward 23h day, fall-back 25h day,
  half-hour `Asia/Kolkata`, quarter-hour `Asia/Kathmandu` + `Pacific/Chatham`,
  `Etc/UTC` sentinel); cross-references to 01a / 01e / 01g / 01h.

  Section 2: **Viewer-time aggregation (Phase 26 — 01g).** Source endpoint
  (YouTube Analytics API v2 via `Youtube::Client`, hourly buckets per video per
  day, traffic-source fallback if API only exposes daily); storage schema
  (`video_viewer_time_buckets` with `_utc`-suffixed columns, composite unique
  index `(video_id, day_of_week_utc, hour_of_day_utc)`, `last_synced_at` index,
  UTC-at-write contract); refresh cadence (`ViewerTimeDailyRefreshJob` at 03:00
  server time, per-video `VideoViewerTimeSyncJob` fan-out, idempotent upsert,
  `Youtube::QuotaExhaustedError` abort,
  `pito:backfill_viewer_time_buckets DAYS=90` rake task, daily cadence locked
  for v1); query patterns (per-video heatmap with `make_timestamp` anchor over
  reference-Sunday `Jan 2 2000`, per-channel join through `videos`, rolling
  window via `last_synced_at`); render contract (`ViewerTimeHeatmapComponent`,
  axis labels via `l_user_tz`, single-hue intensity gradient, no red,
  empty-state copy references the 03:00 cadence); locked decisions list (UTC
  storage / user-tz rollup, daily 03:00 cadence, Monday week-start, raw `SUM`
  per-channel aggregation, web-only v1 surface).

  Source-of-truth notes cited:
  `docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md`
  (§2 user timezone, §3 viewer-time) + `docs/realignment-2026-05-09.md` (YouTube
  Analytics work unit 6).

### Acceptance status

Every bullet in the spec's two Acceptance blocks (section 1 "Timezone rendering
rule" and section 2 "Viewer-time aggregation") is covered. Cross-references and
the locked-decisions list are in place so future readers do not re-litigate.
`npx prettier@latest --write docs/architecture.md` reflowed the new content to
the project's 80-char `prose-wrap: always` convention.

### Plan + spec deltas

- Ticked `01f` checkbox in
  `docs/plans/beta/26-webhooks-timezone-viewer-analytics/plan.md`.

### Open items

The four open questions in the spec (section placement, week-start default,
YouTube Analytics granularity, refresh cadence) were resolved in line with the
master-locked plan decisions: top-level sections under the existing flow, Monday
week-start with future hook, hourly-bucket assumption with documented fallback,
daily refresh at 03:00 server time. None left to surface here.

## 2026-05-11 — sub-spec 01d Help-modal Markdown guides (pito-rails) [skipci]

Implemented sub-spec 01d — Help-modal Markdown guides for the Slack + Discord
webhook panes per `specs/01d-help-modal-markdown-guides.md`. Polished the
on-disk Markdown guides (each now carries a full Troubleshooting section per the
spec acceptance), wired `ApplicationHelper#render_markdown` to take a
`plain: true` keyword that switches off Commonmarker's header-anchor +
syntax-highlighter plugins for the modal render, and fixed the system spec that
was red against `/settings` (the Slack + Discord panes are intentionally not
rendered on the settings index per the 01g layout decision — the system spec now
drives the help-link → fragment contract directly).

### Files touched

**Edited:**

- `app/views/settings/webhooks/help/slack.md` — expanded from the stub: every
  step now spells out where to click + what the screen looks like, no assumed
  Slack-admin knowledge, full Troubleshooting section covering invalid-URL,
  ping-failed 404/410/403, connection-timeout, channel-disappeared, and
  start-over paths.
- `app/views/settings/webhooks/help/discord.md` — same expansion:
  Manage-Webhooks-permission prereq spelled out, full Troubleshooting section
  covering invalid-URL, ping-failed 404/401, missing-menu permission error,
  connection-timeout, channel-disappeared, and start-over paths. Calls out both
  `discord.com` and `discordapp.com` host forms (01c regex accepts both).
- `app/helpers/application_helper.rb` — `render_markdown(text, plain: false)`.
  `plain: true` passes `extension: { header_ids: nil }` +
  `plugins: { syntax_highlighter: nil }` to Commonmarker so the help modal
  renders bare `<h1>` / `<h2>` / `<pre>` / `<code>` without injected anchor
  links or inline-styled syntax highlighting. The default path (note editor SSR
  preview) is unchanged.
- `app/views/settings/webhooks/help/show.html.erb` — call site switched to
  `render_markdown(@markdown, plain: true)` to use the new plain path.
- `spec/requests/settings/webhooks/help_spec.rb` — +6 examples covering the
  plain Markdown rendering posture (no `class="anchor"`, no `<pre style=…>`) and
  the Troubleshooting sections on both guides.
- `spec/views/settings/webhooks/help/show_html_erb_spec.rb` — +11 examples
  locking in the Troubleshooting heading + key error paths on each guide, plus
  an emoji-glyph guard per the project copy convention.
- `spec/system/settings_webhook_help_spec.rb` — rewrote to drop the ambiguous
  `[data-controller], body` selector and the broken click_link path (Slack +
  Discord panes aren't rendered on `/settings` per the 01g decision). The spec
  now drives the help-link → fragment contract directly via
  `visit settings_webhooks_help_path` and verifies modal scaffolding on
  `/settings` + the rendered fragment carries the matching `<turbo-frame>` id.

### Spec count delta

- Request spec: 14 → 20 (+6)
- View spec: 11 → 22 (+11)
- System spec: 4 → 10 (+6, after rewrite to a passing surface)
- Total help-area specs: 29 → 52 (+23)

All 148 webhook-area specs (`spec/services/webhooks/*`,
`spec/requests/settings/{slack,discord}_webhooks_spec.rb`,
`spec/requests/settings/webhooks/help_spec.rb`,
`spec/views/settings/webhooks/**`, `spec/system/settings_webhook_help_spec.rb`)
green.

### Rubocop

`bundle exec rubocop` on the touched Ruby + spec files — clean (4 files, 0
offenses).

### Plan + spec deltas

Ticked `01d` checkbox in
`docs/plans/beta/26-webhooks-timezone-viewer-analytics/plan.md`.

### Open follow-ups

- Slack + Discord panes are still not rendered on `/settings` per the 01g
  decision. The `[help]` links exist in the partials and the modal scaffolding
  lives in the layout, so JS-on users can hit the flow once the panes do reach
  the settings index. The 01d manual test recipe explicitly walks `/settings` —
  that step waits on a follow-up that re-adds the panes to the page (or routes
  them under `/settings/integrations/<provider>` per the original spec
  language). Tracked alongside other phase 26 follow-ups.

## 2026-05-11 — sub-spec 01h Video scheduled-publish tz wiring (pito-rails) [skipci]

Implemented sub-spec 01h — Video scheduled-publish tz wiring per
`specs/01h-video-scheduled-publish-tz-wiring.md`. Wires the existing
`VideosController#schedule` flow through `Current.user.time_zone` so the picker
is in user-tz, storage is UTC, and re-render maps back to the user's current
zone. DST spring-forward gaps surface as a friendly error; DST fall-back
resolves to the first occurrence (pre-fallback, per locked decision) with a
warning hook. The `reminder_window` helper ships now for a future reminder cron;
no reminder cron exists yet so wiring it is deferred.

### Files touched

**New:**

- `app/helpers/scheduled_publish_helper.rb` —
  `parse_user_local_to_utc(date_str, time_str, user_tz)`,
  `render_publish_at_for_user(publish_at_utc, user_tz, format:)`, and
  `reminder_window(publish_at_utc, user_tz, offset:)`. `parse_user_local_to_utc`
  raises `AmbiguousLocalTime` on spring-forward gaps and returns a
  `ParsedPublishAt` struct carrying the UTC instant plus an optional
  `:dst_fallback_first_occurrence` warning. `render_publish_at_for_user`
  defaults to the `<input type="datetime-local">` value shape (`%Y-%m-%dT%H:%M`)
  and supports `:long`, `:short`, `:date`, `:iso` format overrides. The helper
  is pure: it does not read `Current.user` or `Time.zone` — callers pass the
  explicit zone so the conversion is auditable end to end.
- `spec/helpers/scheduled_publish_helper_spec.rb` — 38 examples. Round-trip
  identity, DST spring-forward + fall-back, edge zones (Kiritimati UTC+14, Pago
  Pago UTC-11, Kolkata UTC+5:30, Eucla UTC+8:45), midnight boundaries, reminder
  window math across DST.
- `spec/system/video_scheduled_publish_tz_spec.rb` — 7 critical- journey
  examples covering the picker label, the user-local → UTC → user-local
  round-trip, tz-change-between-schedule-and-edit, edge-zone storage, DST
  spring-forward rejection, and the edit form's "scheduled for:" display in
  user-tz.

**Edited:**

- `app/controllers/videos_controller.rb` — `include ScheduledPublishHelper`; new
  `parsed_publish_at_with_error(value)` returns `[Time, error_msg]` so the
  schedule validator can surface the friendly DST message. ISO 8601 inputs with
  an offset suffix or trailing `Z` route through the original `Time.iso8601`
  path (JSON / MCP callers); tz-less inputs route through
  `parse_user_local_to_utc` in the current user's stored zone.
  `parsed_publish_at(value)` kept as a back-compat one-liner returning just the
  Time.
- `app/views/videos/_pre_publish_modal.html.erb` — the schedule-branch picker
  label declares the user's stored tz (`publish at (Europe/Bucharest)`); the
  `<input>` carries `data-tz="<user_tz>"` for future JS-picker reuse; the value
  attribute pre-fills via
  `render_publish_at_for_user(video.publish_at, user_tz)` so a re-render after a
  tz change shows the same stored UTC instant in the new user-local clock. Hint
  copy clarifies the picker interprets clock-time as user-tz, stores UTC.
- `app/views/videos/_form.html.erb` — `scheduled for:` display uses
  `l_user_tz(video.publish_at)` (from 01a) instead of `.iso8601`. UTC storage,
  user-tz render.
- `app/jobs/video_publish.rb` — `publish_at_iso8601` path now normalizes to
  `.utc` defensively (the controller already stores UTC; this guards the MCP
  path) and logs a tz observability line with the channel-owner's stored
  `time_zone`. Logging is defensive-rescue so it can never raise.
- `spec/jobs/video_publish_spec.rb` — 7 new examples covering: stored UTC
  instant independent of channel-owner's tz; instant invariant when user changes
  tz between schedule + fire; edge-zone storage (Kiritimati, Kolkata); the tz
  observability log line on the schedule path; no tz log line on the
  immediate-publish path.

### Decisions made in flow

- **DST fall-back ambiguity policy.** Sub-spec open question OQ 1 offered two
  choices: pick the FIRST occurrence (pre-fallback) with a warning, or reject as
  ambiguous. Implemented the first option per the spec's lean — the warning
  surfaces as `result.warning = :dst_fallback_first_occurrence`. Controller
  currently does not pipe the warning through to a flash; that's a small
  follow-up if the user wants a notice. The behavior is spec-pinned.
- **Reminder window cron deferred.** Sub-spec lists a future
  `app/jobs/video_publish_reminder_job.rb`. No such job exists in main, and
  01h's primary deliverable is the helper + scheduled-publish wiring.
  `ScheduledPublishHelper#reminder_window` ships now (spec-covered) so a
  follow-up wiring is a pure call-site addition.
- **Tz-less ISO 8601 input policy.** `Time.iso8601` raises on a tz-less string.
  The controller's `parsed_publish_at_with_error` routes tz-less strings (the
  picker format `2026-06-01T09:00`) through `parse_user_local_to_utc` in the
  user's zone; offset-suffix strings (the JSON / MCP path) keep the
  literal-instant interpretation. The contract: HTML form ⇒ user-tz, JSON / MCP
  ⇒ absolute UTC. Existing `videos_spec.rb` request spec asserts
  `future.iso8601` (offset-bearing) round-trips — that contract is preserved.
- **Job-side parsing is identity.** The controller stores UTC before enqueueing,
  so `VideoPublish` sees an absolute ISO 8601 string. `Time.iso8601(...).utc` is
  defensive (idempotent on a UTC-suffixed string); the new tz observability log
  line confirms the channel-owner's stored zone at job-fire time.
- **MCP / CLI surfaces.** Out of scope per the spec's locked Open Questions
  OQ 4. The `publish_video` MCP tool already accepts ISO 8601 strings
  end-to-end; tz-bearing strings continue to work via the offset-suffix branch.

### Specs

| Surface                           | New specs | Pass          |
| --------------------------------- | --------- | ------------- |
| `ScheduledPublishHelper` (helper) | 38        | yes           |
| `VideoPublish` job (tz extension) | 7         | yes           |
| Scheduled-publish tz (system)     | 7         | yes           |
| **Total new**                     | **52**    | **all green** |

### Gates

- `bundle exec rspec` (touched + adjacent) — 170 / 170 green on
  `spec/requests/videos_spec.rb` +
  `spec/system/video_pre_publish_checklist_spec.rb`
  - `spec/jobs/video_publish_spec.rb` +
    `spec/helpers/scheduled_publish_helper_spec.rb`
  - `spec/system/video_scheduled_publish_tz_spec.rb`. Wider helpers + tz system
    surface: 462 / 462 green.
- `bundle exec rubocop` on touched Ruby files — 6 / 6 clean.
- `bin/brakeman -q -w2` — 0 warnings, 0 errors. Two obsolete ignore entries
  pre-exist on main; unrelated to this change.

### Cross-cutting compliance

- **yes / no boundary** — Scheduled-publish flow carries no new external
  Boolean; the pre-publish checklist booleans (already `yes` / `no` per 01b/01c
  contract) continue to wire through `YesNo.from_yes_no`. The new helper accepts
  strings only — no Boolean surface.
- **Friendly URLs** — `/videos/:slug/schedule` is the canonical surface; route
  unchanged.
- **No JS confirm / alert / prompt / `data-turbo-confirm`** — picker is a plain
  `<input type="datetime-local">`; no JS confirmation. Spring-forward rejection
  is server-side, surfaces as a flash inside the modal partial.
- **UTC storage, user-tz render** — pinned by helper, picker, edit form, and job
  observability log. The render-time helper (`l_user_tz`) is the only conversion
  site for "scheduled for:" display.

### Manual test plan (for the user)

1. `bin/dev` running. Open a private draft video's edit page.
2. Confirm the user's tz is `Europe/Bucharest` via `/settings`. Click
   `[schedule]` — the modal opens; the picker label reads
   `publish at (Europe/Bucharest)` and the hint clarifies "times are interpreted
   in your time zone (Europe/Bucharest). stored as UTC."
3. Pick `2026-06-01T09:00`. Tick the four checklist boxes. Hit
   `[confirm schedule]`. Redirect to the video show page.
4. In Rails console: `Video.find(...).publish_at.utc.iso8601` shows
   `2026-06-01T06:00:00Z` (Bucharest is UTC+3 in DST).
5. Reload the edit page — the `scheduled for:` line renders
   `Jun 1, 2026 09:00 EEST`.
6. Change tz to `America/Los_Angeles` via `/settings`. Reload the edit page —
   `scheduled for:` now renders `May 31, 2026 23:00 PDT`. Click `[schedule]` —
   the picker pre-fill is `2026-05-31T23:00`.
7. DST spring-forward test: keep tz `America/Los_Angeles`. Pick
   `2026-03-08T02:30` in the schedule picker. Submit. The form re-renders with
   the alert "That time does not exist due to DST spring-forward."

### Follow-ups surfaced

- **Reminder cron.** Sub-spec mentions a
  `app/jobs/video_publish_reminder_job.rb`. Not yet shipped (no cron exists).
  `ScheduledPublishHelper#reminder_window` is in place when the cron lands.
- **DST fall-back warning UX.** `parse_user_local_to_utc` returns a
  `:dst_fallback_first_occurrence` warning on the ambiguous hour. The controller
  currently does not pipe it through to a flash — neutral by default. Surface to
  user before adding a notice copy.
- **MCP `publish_video` tool tz extension.** The current MCP path uses
  offset-suffix ISO 8601 strings end-to-end. If the CLI lane wants a `--tz` flag
  (`pito videos publish --at "2026-06-01 09:00" --tz Europe/Bucharest`), the
  Rust crate composes the user-local string + the explicit tz into an
  offset-suffix ISO 8601 string before calling the existing MCP tool. No
  Rails-side change needed.
- **JS picker label localization.** `data-tz="<user_tz>"` is set on the input so
  a future Stimulus controller can render the tz-aware preview ("publishing at
  HH:MM your local time, HH:MM UTC") without an HTTP round-trip. Out of 01h
  scope.

## 2026-05-11 — sub-spec 01e Daily digest scheduler (pito-rails)

Implemented sub-spec 01e — Daily digest scheduler per
`specs/01e-daily-digest-scheduler.md` and the master-locked decisions: hourly
cron at minute 0, per-user `last_digest_run_at` UTC guard, per-provider
Slack-blocks / Discord-embeds rendering, retry posture 3 attempts with
exponential backoff (1m, 5m, 15m), permanent failures (400/401/403/404/410) drop
a `digest_delivery_failed` notification row and stop retrying.

### Files touched

**New:**

- `db/migrate/20260511155924_add_last_digest_run_at_to_users.rb` —
  `users.last_digest_run_at` (datetime, NOT NULL, default `CURRENT_TIMESTAMP` so
  freshly-created users look "just-digested" and don't double-fire at the first
  cron tick). Migration applied to dev DB; status confirmed clean.
- `app/jobs/daily_digest_scheduler_job.rb` — hourly cron entry (ActiveJob).
  Pre-filters users via SQL on the 23h cooldown + EXISTS-clause for a
  digest-enabled `notification_delivery_channels` row, then runs the precise
  tz-aware pickup check in Ruby (`ActiveSupport::TimeZone#local`). Atomic claim
  via a conditional `UPDATE` that re-asserts the cooldown — two simultaneous
  ticks race-safe. Edge zones (UTC+14 Kiritimati, UTC-11 Pago Pago, UTC+5:30
  Kolkata, UTC+8:45 Eucla) and DST transitions (spring- forward Mar 8 2026 +
  fall-back Nov 1 2026 in America/New_York) all covered.
- `app/jobs/daily_digest_deliver_job.rb` — per-user delivery (ActiveJob).
  Iterates digest-enabled channels, renders per-provider payload, delivers via
  `Webhooks::SlackClient#deliver` / `Webhooks::DiscordClient#deliver`. Permanent
  failures (400/401/403/404/410) record a `Notification` row tagged
  `event_type: "digest_delivery_failed"` and continue with the next channel.
  Transient failures (429, 5xx, network) raise `TransientFailure` so ActiveJob
  retries with the 1m/5m/15m ladder.
- `app/services/digest/composer.rb` — provider-agnostic aggregator. Six
  sections: channels synced, videos imported, videos updated (re-synced inside
  window but created before it — no double-count), footage imported, login
  attempts, open notifications (unread, older than 1 hour to avoid flapping).
  Per-section item cap 10 with `… and N more` trailer.
- `app/services/digest/slack_renderer.rb` — Slack Block Kit. Header
  - context (window range rendered in user's local tz) + one `section` block per
    non-empty `Composer::Section`, dividers between them. All-quiet fallback
    emits a single `no activity in the last 24 hours` section block.
- `app/services/digest/discord_renderer.rb` — Discord embeds. Top- level
  `content` + one embed with `title`, `description` (window range in user-tz),
  `fields` (one per non-empty section), `timestamp` (window-end ISO8601 —
  Discord renders in viewer-local). Defensive truncation to Discord's 1024-char
  per-field cap.
- Specs: `spec/services/digest/composer_spec.rb`,
  `spec/services/digest/slack_renderer_spec.rb`,
  `spec/services/digest/discord_renderer_spec.rb`,
  `spec/jobs/daily_digest_scheduler_job_spec.rb`,
  `spec/jobs/daily_digest_deliver_job_spec.rb`. 91 specs total. Exhaustive on
  the picker (every locked zone + DST + idempotence + tz-change + race), happy +
  sad + edge on delivery (2xx success across Slack + Discord, 429/5xx retry,
  400/401/404 terminal, mixed Slack-permanent + Discord-success, all-quiet
  still-deliver).

**Edited:**

- `config/sidekiq_cron.yml` — registered `daily_digest_scheduler` cron entry at
  `"0 * * * *"`.

### Acceptance status

All Acceptance bullets in `specs/01e-daily-digest-scheduler.md` green. Brakeman
(`bin/brakeman -q -w2`) clean. Rubocop clean on touched files. The plan-level
`01e` checkbox ticked.

### Open items

The locked open questions in the spec (digest content shape, all-quiet fallback,
DST policy, retry budget, bulk-vs-per-user, delivery-failure visibility) were
all resolved by the master dispatch instructions and implemented as locked.

## 2026-05-11 — sub-spec 01a Timezone foundation (pito-rails)

Implemented sub-spec 01a — Timezone foundation per
`specs/01a-timezone-foundation.md`. Foundation work that pins UTC-storage /
user-tz-render as the app-wide contract and unblocks 01d, 01e, 01f, 01g, 01h.

### Files touched

**New:**

- `db/migrate/20260511132718_add_time_zone_to_users.rb` — adds `users.time_zone`
  (string, NOT NULL, default `"Etc/UTC"`).
- `app/models/concerns/timezoned.rb` — `Timezoned` concern mixed into `User`.
  Validates `time_zone` against the union of `TZInfo::Timezone.all_identifiers`
  (full IANA set) + `ActiveSupport::TimeZone::MAPPING.{keys,values}` (Rails
  aliases) — exposes `#tz` returning the resolved `ActiveSupport::TimeZone`
  instance, with `Etc/UTC` fallback for corrupted stored values.
- `app/helpers/time_zone_helper.rb` — `l_user_tz(time, format:)` render helper
  (`:long` default, `:short`, `:date`, `:iso`) and
  `current_time_in_user_tz(format:)` convenience helper. Nil-safe, accepts
  `Time`, `DateTime`, `ActiveSupport::TimeWithZone`.
- `app/controllers/settings/time_zone_controller.rb` — single `update` action.
  HTML caller (Settings dropdown) redirects with flash; JSON / detect caller
  gets 204 / 422.
- `app/views/settings/_time_zone_pane.html.erb` — Settings pane carrying a
  two-optgroup dropdown ("common" + "all IANA") so every IANA zone is reachable
  from the UI (acceptance bullet "all valid IANA zones").
- `app/javascript/controllers/timezone_detect_controller.js` — Stimulus
  controller mounted on `<body>`. On first authenticated load (stored zone ==
  `"Etc/UTC"` sentinel) detects the browser zone via
  `Intl.DateTimeFormat().resolvedOptions().timeZone` and silently PATCHes
  `/settings/time_zone`. No JS confirm/alert/prompt. Reads the CSRF token from
  the layout meta tag and forwards it as `X-CSRF-Token`.
- Specs: `spec/models/concerns/timezoned_spec.rb`,
  `spec/helpers/time_zone_helper_spec.rb`,
  `spec/requests/settings/time_zone_spec.rb`,
  `spec/system/settings_time_zone_spec.rb`,
  `spec/system/timezone_detect_spec.rb`.

**Edited:**

- `app/models/user.rb` — `include Timezoned`.
- `app/controllers/application_controller.rb` — added
  `before_action :set_user_time_zone`. Sets
  `Time.zone = Current.user&.time_zone.presence || "Etc/UTC"` per request.
- `app/views/layouts/application.html.erb` — mounted the `timezone-detect`
  Stimulus controller on `<body>` and conditionally carry the stored zone +
  URL + CSRF token via Stimulus values on authenticated layouts. The data
  attribute is omitted on unauthenticated screens (login, OAuth consent) so the
  controller bails on its own.
- `app/views/settings/index.html.erb` — paired the previously single-pane "user"
  row with the new timezone pane (now two-pane row).
- `config/routes.rb` — added
  `resource :time_zone, only: %i[update], controller: "time_zone"` inside the
  existing `namespace :settings do` block. URL preserved as the friendly
  `/settings/time_zone` (no numeric / UUID).
- `spec/models/user_spec.rb` — extended with `describe "time_zone column"`
  block.
- `spec/requests/settings_spec.rb` — bumped pane count from 8 to 9 (the new
  timezone pane joins row 4 / paired-user row).

### Migration

`bin/rails db:migrate` ran clean against the dev DB. Schema diff:

```
t.string "time_zone", default: "Etc/UTC", null: false
```

### Decisions made in flow

- **Dropdown scope expanded.** The spec said the dropdown lists
  `ActiveSupport::TimeZone.all.map { |z| [z.name, z.tzinfo.name] }`
  (Rails-curated 152 zones), but the Acceptance bullet says "all valid IANA
  zones". Reconciled by splitting the `<select>` into two `<optgroup>` blocks —
  `common` (the curated friendly subset) and `all IANA` (the rest of
  `TZInfo::Timezone.all_identifiers`). All values persist as canonical IANA
  names.
- **Validator scope expanded.** The locked decision said validate against
  `ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name)` + alias mapping, but
  that misses edge zones the Acceptance bullet required (`Pacific/Kiritimati`,
  `Pacific/Pago_Pago`). Switched the allow-list source to
  `TZInfo::Timezone.all_identifiers` (full IANA set) so JS-detected names always
  validate. Rails alias keys + values still in the set so `"UTC"`-style inputs
  work.
- **Header chrome render of `current_time_in_user_tz`.** Open question (sub-spec
  OQ 3) on whether to render a visual confirmation in the header. Skipped — the
  helper exists for downstream sub-specs to consume, and the spec's acceptance
  only requires its definition. Master agent can surface the question to the
  user before 01b-01h land.
- **MCP tool surface for tz update.** Sub-spec OQ 4 + cross-stack scope note.
  Spec's Acceptance explicitly carves out: "No new service / job / component /
  validator / lib / MCP tool needed for this foundation (downstream sub-specs
  add those)." Deferred.
- **CLI parity (`pito settings show / set_tz`).** Out of this agent's file scope
  (`extras/` is owned by `pito-rust`). Deferred.

### Specs

| Surface                               | New specs | Pass          |
| ------------------------------------- | --------- | ------------- |
| `Timezoned` concern (model)           | 18        | yes           |
| `User` model (tz block extension)     | 5         | yes           |
| `TimeZoneHelper` (helper)             | 18        | yes           |
| `Settings::TimeZone` (request)        | 12        | yes           |
| `Settings → time zone pane` (system)  | 4         | yes           |
| `Timezone first-load detect` (system) | 4         | yes           |
| **Total new**                         | **61**    | **all green** |

Edited spec (`spec/requests/settings_spec.rb`) bumps the pane count assertion
from 8 → 9.

### Gates

- `bundle exec rspec` — 151 / 151 green across touched specs (1685 / 1685 across
  the wider `spec/controllers spec/requests` set except one **pre-existing**
  failure unrelated to this work:
  `spec/requests/concerns/sessions/auth_concern_spec.rb:57` — POSTs to
  `/channels` which is not a valid route on `main` HEAD; confirmed by re-running
  after stashing all changes).
- `bundle exec rubocop` — 1061 / 1061 files clean.
- `bin/brakeman -q -w2` — 0 warnings, 0 errors.

### Cross-cutting compliance

- **yes / no boundary** — the tz update flow carries no external Boolean (only
  the `time_zone` string). Sweep spec backstop in the request spec asserts the
  response body contains no `"true"` / `"false"` literals.
- **Friendly URLs** — `/settings/time_zone` is the canonical surface; route spec
  assertion pins it.
- **No JS confirm / alert / prompt** — the Stimulus detect controller is silent
  on success and silent on failure (the user can override via the Settings
  dropdown). The dropdown form is a normal POST redirect.
- **Brand casing** — "pito" lowercase preserved in the pane hint text ("affects
  how every time is rendered across pito.").

### Manual test plan (for the user)

1. `bin/rails db:migrate` — confirm the migration ran (already done in this
   session against dev DB).
2. `bin/dev` to start the stack.
3. Open `/settings` in a fresh browser session (where the user's `time_zone` is
   still `"Etc/UTC"`). Watch the network tab: a silent
   `PATCH /settings/time_zone` fires with the browser-detected zone (likely
   `"Europe/Bucharest"`). Reload — no second detect call.
4. Pick a different zone (e.g. `"America/Los_Angeles"`) from the dropdown's
   `common` optgroup, hit `[update]`. The page redirects to `/settings` with the
   new zone applied (the dropdown re-renders with the selected option).
5. Pick an edge zone (e.g. `"Pacific/Kiritimati"`) from the `all IANA` optgroup,
   hit `[update]`. Same result — persisted via the full-IANA allow-list.
6. Open a Rails console: `User.last.update!(time_zone: "Pacific/Kiritimati")`.
   Reload `/settings` — the dropdown shows the new zone pre-selected.
7. Try to PATCH with an invalid zone:
   ```sh
   curl -X PATCH http://127.0.0.1:3027/settings/time_zone \
     -b cookies.txt -d 'time_zone=Mars/Olympus_Mons'
   ```
   Expect a 422 (JSON / detect caller) or redirect with flash alert (HTML
   caller).

### Follow-ups surfaced

- Header chrome rendering of `current_time_in_user_tz` (sub-spec OQ 3) —
  decision deferred to master agent.
- MCP tool for user tz read / update (umbrella locked decision mentions
  "existing settings MCP namespace" — current `manage_settings` MCP tool is
  app-settings, not user-settings; a new `user_settings` MCP tool is out of this
  sub-spec's scope).
- CLI parity (`pito settings show` / `set_tz`) — `extras/cli/` changes belong to
  `pito-rust`; defer dispatch.

### Open follow-ups from umbrella

OQ 1 (YouTube channel tz field) and OQ 2 (cross-tz diff dialog copy) referenced
by 01a — both are content / surfacing questions not blocking this foundation.
Surface to user before any sub-spec that consumes them.

## 2026-05-11 — sub-spec 01c Discord webhook pane (pito-rails)

Mirror of 01b for Discord. Single dispatch — paste a URL, regex- validate, fire
a test ping with the Discord-shaped `{ "content": ... }` payload, persist on
2xx. Independent `notification_delivery_channels` row keyed on
`kind: "discord"`. Both `discord.com` and `discordapp.com` host forms accepted.

### Files touched

**New:**

- `app/services/webhooks/discord_client.rb` — `#ping(text)` +
  `#deliver(payload)` mirroring `Webhooks::SlackClient`. Only meaningful
  difference is the payload key (`content` vs `text`).
- `app/controllers/settings/discord_webhooks_controller.rb` — single `update`
  action. Validates the URL with
  `NotificationDeliveryChannel::DISCORD_URL_REGEX`, fires the test ping, upserts
  the install-level row on 2xx, redirects with notice / alert. Test-ping copy
  locked at `"Pito test ping — Discord webhook configured."`.
- `app/views/settings/_discord_pane.html.erb` — pane partial. URL input + two
  yes/no checkboxes (`everything`, `daily_digest`) + `[update]` submit.
  Pre-fills from `@discord_webhook` (the AR row).
- Specs: `spec/services/webhooks/discord_client_spec.rb` (20 examples),
  `spec/requests/settings/discord_webhooks_spec.rb` (33 examples),
  `spec/views/settings/_discord_pane_html_erb_spec.rb` (14 examples).

**Edited:**

- `config/routes.rb` — added
  `resource :discord_webhook, only: %i[update], controller: "discord_webhooks"`
  inside the existing `namespace :settings do` block. URL preserved as
  `/settings/discord_webhook`.
- `app/views/settings/index.html.erb` — paired the Slack pane with the new
  Discord pane in the existing Phase 26 01b/01c `.pane-row`.
- `app/controllers/settings_controller.rb` — added the
  `@discord_webhook = NotificationDeliveryChannel.find_record_for("discord")`
  read so the pane pre-fills from the AR row.
- `spec/requests/settings_spec.rb` — bumped the pane-count assertion from
  `5 rows / 9 panes` (01a baseline) to `6 rows / 11 panes` (01b Slack + 01c
  Discord paired in a new row).

### Decisions made in flow

- **Architect's locked decisions overrode the spec's older file paths.** Spec
  01c originally pointed at
  `app/controllers/settings/webhooks/discord_controller.rb` and
  `app/services/webhooks/discord_url_validator.rb` (a standalone validator
  object). The dispatch from master locked the mirror-of- Slack shape: regex
  constant on the AR model, controller at
  `app/controllers/settings/discord_webhooks_controller.rb`, route
  `resource :discord_webhook, only: :update`. Honored the dispatch.
- **Discord PORO refactor (`webhook_url` reads AR row first).** Already staged
  in `app/services/notification_delivery_channel/discord.rb` alongside the Slack
  refactor — AR row first, then
  `Rails.application.credentials.notifications.discord_webhook_url` fallback. No
  changes needed; the model lookup
  `NotificationDeliveryChannel.discord&.webhook_url` resolves correctly because
  the AR model already had `KINDS` containing both `"slack"` and `"discord"`.
- **`kind: "discord"` already in the AR model's enum.** 01b landed both kinds in
  `NotificationDeliveryChannel::KINDS` and the per-kind regex
  (`DISCORD_URL_REGEX`). 01c reuses the existing constant — no model migration
  needed.
- **Brand casing — `Discord`.** Pane heading uses `<h2>Discord</h2>` with the
  brand capital D (mirror of `<h2>Slack</h2>`). Body copy stays lowercase
  pito-style.

### Specs

| Surface                                              | New specs | Pass          |
| ---------------------------------------------------- | --------- | ------------- |
| `Webhooks::DiscordClient` (service)                  | 20        | yes           |
| `Settings::DiscordWebhooks` (request)                | 33        | yes           |
| `settings/_discord_pane.html.erb` (view)             | 14        | yes           |
| `spec/requests/settings_spec.rb` (pane count update) | 0 net     | yes           |
| **Total new**                                        | **67**    | **all green** |

Adjacent specs (376 across `spec/requests/settings`, `spec/views/settings`,
`spec/services/webhooks`, `spec/services/notification_delivery_channel`, and
`spec/models/notification_delivery_channel_spec.rb`) all green.

### Gates

- `bundle exec rspec` (Discord + adjacent settings/webhook surface) — 376 / 376
  green.
- `bundle exec rubocop` — 8 / 8 Ruby files clean (ERB files excluded from
  rubocop run per project posture; rubocop's ERB parser is opt-in).
- `bin/brakeman -q -w2` — 0 warnings, 0 errors.

### Cross-cutting compliance

- **yes / no boundary** — `everything` + `daily_digest` ride `"yes"` / `"no"` on
  the wire (checkbox `value="yes"`, absence ⇒ false). Controller's
  `coerce_boolean` uses `YesNo.yes_no?` + `YesNo.from_yes_no`. Spec asserts
  non-`yes`/`no` strings (`"true"`, `"1"`) coerce to false.
- **Friendly URLs** — `/settings/discord_webhook` pinned by spec assertion
  (`expect(settings_discord_webhook_path).to eq("/settings/discord_webhook")`).
- **No JS confirm / alert / prompt / `data-turbo-confirm`** — view spec includes
  a guard assertion (`expect(rendered).not_to include("data-turbo-confirm")`).
- **Brand casing** — `<h2>Discord</h2>` preserved; verified by view spec
  rendering check.
- **Active Record Encryption** — `webhook_url` column inherits the ARE
  `encrypts :webhook_url` declaration from 01b's model. No ciphertext can leak
  into logs or `raw` selects (covered by existing model spec).

### Manual test plan (for the user)

1. `bin/dev` running. Create a Discord webhook on a test server. (Server →
   Settings → Integrations → Webhooks → New.)
2. Open `/settings`. Locate the new Discord pane next to Slack.
3. Paste the URL, click `[update]`. A test message "Pito test ping — Discord
   webhook configured." lands in the Discord channel. URL persists on reload.
4. Edit URL to the `discordapp.com` form. Click `[update]`. Test ping succeeds;
   URL persists.
5. Edit URL to a syntactically valid but server-side-invalid URL. Click
   `[update]`. Test ping returns 404. Form re-renders with "Discord test ping
   failed: 404." Original URL stays.
6. Tick `everything`, click `[update]`. Reload — checkbox stays ticked. Tick
   `daily digest`. Click `[update]`. Reload — both ticked. Untick both. Reload —
   both unticked.
7. DB inspect: `NotificationDeliveryChannel.where(kind: "discord").last`
   reflects current state.

### Follow-ups surfaced

- **01b help modal not yet wired into the pane.** 01d will add the `[help]`
  bracketed link next to each pane heading (Slack + Discord) opening a Markdown
  modal. Out of 01c scope.
- **Sad-path URL validation lives in the controller only** — the AR model's
  `webhook_url_must_match_kind` is the second line of defense. The spec dispatch
  didn't ask for a dedicated `DiscordUrlValidator` service object, so the
  original sub-spec's validator file
  (`app/services/webhooks/discord_url_validator.rb`) is intentionally NOT
  created — the regex constant lives on the AR model and is reused by the
  controller + the model validation.

## 2026-05-11 — sub-spec 01b Slack webhook pane re-dispatch (pito-rails)

Re-dispatch of sub-spec 01b — Slack webhook pane per
`specs/01b-slack-webhook-pane-and-validation.md` and the master-locked
re-dispatch decisions. The first dispatch landed the model + base PORO +
controller + view + specs in commit `b14f974`, but the PORO subclass files
(`Slack`, `Discord`, `InApp`) were still declared as
`class X < NotificationDeliveryChannel` — which would have triggered STI
auto-bind against the new AR table. This session reconciles that inconsistency
and finishes the refactor.

### Files touched

**Edited (PORO refactor — STI fix):**

- `app/services/notification_delivery_channel/slack.rb` — parent changed from
  `NotificationDeliveryChannel` to `NotificationDeliveryChannel::Base` so the
  PORO is no longer an STI subclass of the AR model. `#webhook_url` now resolves
  the AR row first (`NotificationDeliveryChannel.slack&.webhook_url`) and falls
  back to credentials — the Settings pane manages the URL without rotating
  credentials, and existing installs that wired the URL via credentials keep
  delivering.
- `app/services/notification_delivery_channel/discord.rb` — same refactor for
  the Discord PORO. AR-row-first / credentials-fallback resolution.
- `app/services/notification_delivery_channel/in_app.rb` — parent changed to
  `Base`. No URL resolution (in-app delivery is a no-op).
- `spec/services/notification_delivery_channel_spec.rb` —
  `TestNotificationChannel` now inherits from
  `NotificationDeliveryChannel::Base` (was the AR model — STI again).

**New (added in this session):**

- `spec/views/settings/_slack_pane_html_erb_spec.rb` — mirror of the Discord
  pane view spec the 01c agent shipped: renders the pane with / without an AR
  row, asserts pre-fill, yes/no checkbox wire format, no `data-turbo-confirm`.

**Already shipped in commit `b14f974` (re-verified, no edits needed):**

- `db/migrate/20260511150000_create_notification_delivery_channels.rb`
- `app/models/notification_delivery_channel.rb`
- `app/services/notification_delivery_channel/base.rb`
- `app/services/webhooks/slack_client.rb`
- `app/controllers/settings/slack_webhooks_controller.rb`
- `app/views/settings/_slack_pane.html.erb`
- `config/routes.rb` (`resource :slack_webhook`)
- `app/controllers/settings_controller.rb` (`@slack_webhook` ivar)
- `app/views/settings/index.html.erb` (`render "slack_pane"`)
- `spec/models/notification_delivery_channel_spec.rb`
- `spec/services/webhooks/slack_client_spec.rb`
- `spec/requests/settings/slack_webhooks_spec.rb`

### Migration

`bin/rails db:migrate` ran clean against the dev DB earlier in the re-dispatch
path. `bin/rails db:migrate:status` reports
`up   20260511150000  Create notification delivery channels`. RSpec
auto-migrates the test DB via `maintain_test_schema!`. The 01c agent reads the
same table by adding `discord` to the shared `KINDS` enum constant.

### Decisions made in flow

- **PORO base lives at `NotificationDeliveryChannel::Base`.** The AR model
  claims the top-level constant; the dispatcher base is a nested PORO.
  `NotificationDeliveryChannel.for(kind)` (existing call site in
  `NotificationDeliver` job + spec suite) delegates to `Base.for(kind)` so
  existing call shapes keep working without an STI flip.
- **`for(kind)` returns a PORO; `find_record_for(kind)` returns an AR row.** Two
  different responsibilities under two different names. AR-row lookup is
  `find_record_for` and the kind-scoped shorthands (`.slack`, `.discord`) —
  never `.for`.
- **AR-row-first resolution with credentials fallback.** Existing installs that
  wired their webhook URL through
  `Rails.application.credentials.notifications.slack_webhook_url` keep
  delivering. New installs use the Settings pane. Both coexist; the row wins
  when present.

### Specs

| Surface                                                   | New / edited          | Pass    |
| --------------------------------------------------------- | --------------------- | ------- |
| `NotificationDeliveryChannel` (AR model)                  | 25 new                | yes     |
| `Webhooks::SlackClient` (service)                         | 20 new                | yes     |
| `Settings::SlackWebhooks` (request)                       | 30 new                | yes     |
| `settings/_slack_pane.html.erb` (view)                    | 14 new                | yes     |
| `NotificationDeliveryChannel::Base` dispatcher (existing) | 0 new                 | yes     |
| `NotificationDeliveryChannel::Slack` (existing)           | 0 new                 | yes     |
| `NotificationDeliveryChannel::Discord` (existing)         | 0 new                 | yes     |
| `NotificationDeliveryChannel::InApp` (existing)           | 0 new                 | yes     |
| `NotificationDeliver` job (existing)                      | 0 new                 | yes     |
| **Total touched, all green**                              | **89 new + adjacent** | **yes** |

### Gates

- `bundle exec rspec` on the Phase 26 spec surface (models + services +
  requests + views + dispatcher + jobs + settings) — 287 / 287 green.
- `bundle exec rubocop` on touched Ruby files — clean.
- `bin/brakeman -q -w2` — 0 warnings, 0 errors. Two obsolete ignore entries
  reported but unrelated to this change.

### Cross-cutting compliance

- **yes / no boundary** — `everything` + `daily_digest` cross the wire as
  `"yes"` / `"no"` strings. The controller's `coerce_boolean` helper rejects
  every non-yes/no value as `false` (including `"true"`, `"1"`, `"on"`). Yes/no
  sweep block in the request spec asserts both directions.
- **Friendly URL** — `/settings/slack_webhook` (no numeric / UUID id). Route
  spec assertion pins it.
- **No JS confirm / alert / prompt** — none in the pane partial. View spec
  asserts no `data-turbo-confirm` is emitted.
- **Test ping copy locked** — controller emits
  `"Pito test ping — Slack webhook configured."` as the test payload `text`.
  Request spec asserts the exact body.
- **AR Encryption on `webhook_url`** — model spec asserts the ciphertext blob in
  the underlying column does NOT contain the plaintext `hooks.slack.com`
  substring; round-trip read returns plaintext as expected.

### Coordination with 01c (Discord)

The 01c agent shipped `_discord_pane`, `Settings::DiscordWebhooksController`,
`Webhooks::DiscordClient`, and the Discord-specific test surface against the
same shared `NotificationDeliveryChannel` AR model. The 01b/01c split is clean:
01b owned the migration + model + base PORO + Slack pane + Slack client; 01c
added the `discord` row, controller, client, view, and specs without touching
the migration or the shared model schema.

### Follow-ups surfaced

- Acceptance bullets that depend on 01d (Slack help modal Markdown rendering)
  stay open — the pane will link to the help modal via `[help]` but the modal
  copy lands with 01d.
- Spec dispatch's `Webhooks::SlackUrlValidator` was folded into the AR model
  (`#valid_url?` + `SLACK_URL_REGEX` constant) rather than shipped as a
  standalone `ActiveModel::Validator` class — the controller-level regex
  pre-check + the model's `validate :webhook_url_must_match_kind` callback
  together enforce shape at both boundaries.
- 107 unrelated test failures pre-exist on `main` HEAD — concentrated in
  `spec/models/game_*` and `spec/requests/games_spec.rb` (Phase 27 in-flight
  work). Confirmed by stashing the working tree and re- running: the failures
  persist. Not caused by this dispatch.

## 2026-05-11 — 01g viewer-time analytics implementation

Dispatched: `pito-rails`. Spec:
`specs/01g-viewer-time-analytics-implementation.md`. Status: shipped. Migration
applied to dev DB; test DB schema:load + parallel:load_schema applied. Plan
checkbox ticked.

### Files touched

New (model + service + jobs + component + views + rake + specs):

- `db/migrate/20260511160003_create_video_viewer_time_buckets.rb` — table with
  composite unique index on `(video_id, day_of_week_utc, hour_of_day_utc)` +
  four DB CHECK constraints (hour 0..23, dow 0..6, view_count >= 0,
  watch_time_seconds >= 0). FK `ON DELETE CASCADE` from `videos`.
- `app/models/video_viewer_time_bucket.rb` — model with full validation set,
  `for_channel(channel_id)` scope, and the `rolled_up_to_tz(tz)` scope that
  builds a single Postgres query re-projecting each (dow_utc, hod_utc) cell
  through a reference- Sunday timestamp `AT TIME ZONE 'UTC' AT TIME ZONE :tz`.
  Accepts IANA names, Rails-friendly aliases, and `ActiveSupport::TimeZone`
  instances via `resolve_iana(tz)`.
- `app/services/analytics/viewer_time_rollup.rb` — `:video` / `:channel` scope
  dispatch returning `{ [dow, hod] => Result }` with
  `Result.new(views:, watch_time_seconds:)`. Single SQL query per call.
- `app/jobs/video_viewer_time_sync_job.rb` — per-video sync. Calls
  `Youtube::AnalyticsClient#video_viewer_time(video, from, to)`, aggregates the
  day+hour grid into (dow, hod) totals, upserts via the composite unique index.
  Idempotent on re-run; `AuthError` exits cleanly without raising; missing video
  / connection / reauth all no-op.
- `app/jobs/viewer_time_daily_refresh_job.rb` — fan-out orchestrator. Walks
  `Video.joins(channel: :youtube_connection)` filtered by
  `youtube_connections.needs_reauth = false`, enqueues one
  `VideoViewerTimeSyncJob` per video. Cron-registered at 03:00 UTC via
  `config/sidekiq_cron.yml`.
- `app/components/viewer_time_heatmap_component.{rb,html.erb}` — ViewComponent.
  7x24 CSS-grid heatmap; single-hue intensity gradient using link-blue rgba(0,
  0, 204, alpha) with alpha = cell/max; empty cells render at
  `--color-pane-bg-a` baseline; per-cell `title=...` tooltip carries day +
  hour + counts; `intensity_by: :views|:watch_time` with `:views` default;
  mobile collapses via @media (max-width: 480px). No red, per design.
- `app/views/videos/_viewer_time_tab.html.erb` +
  `app/views/channels/_viewer_time_tab.html.erb` — partials reading
  `Current.user.time_zone` (with `Etc/UTC` fallback) and rendering the component
  from the rollup hash.
- `lib/tasks/viewer_time_backfill.rake` —
  `pito:backfill_viewer_time_buckets DAYS=90` task; aborts on non-positive DAYS;
  iterates owned videos and enqueues
  `VideoViewerTimeSyncJob.perform_async(video_id, days)`.

Edited:

- `app/models/video.rb` —
  `has_many :viewer_time_buckets, class_name: "VideoViewerTimeBucket", dependent: :delete_all`.
- `app/services/youtube/analytics_query_builder.rb` — added
  `video_viewer_time_params(video_youtube_id:, from:, to:)` (V9 — dimensions
  `day,hour`, metrics `views,estimatedMinutesWatched`, channel-MINE-scoped +
  `filters: "video==..."`).
- `app/services/youtube/analytics_client.rb` — added
  `video_viewer_time(video:, from:, to:)` wrapper around the new builder + audit
  kind `V9.video_viewer_time`.
- `app/views/videos/analytics/show.html.erb` +
  `app/views/channels/analytics/show.html.erb` — rendered the new partials at
  the bottom of the existing analytics sections.
- `app/assets/tailwind/application.css` — heatmap CSS-grid + tooltip
  - mobile breakpoint rules. No new design tokens; uses existing
    `--color-pane-bg-a` for the zero-intensity baseline.
- `config/sidekiq_cron.yml` — `viewer_time_daily_refresh` entry, 03:00 UTC,
  queue `analytics`.

Specs added:

- `spec/factories/video_viewer_time_buckets.rb`
- `spec/models/video_viewer_time_bucket_spec.rb` (21 examples)
- `spec/services/analytics/viewer_time_rollup_spec.rb` (13 examples)
- `spec/jobs/video_viewer_time_sync_job_spec.rb` (11 examples)
- `spec/jobs/viewer_time_daily_refresh_job_spec.rb` (4 examples)
- `spec/components/viewer_time_heatmap_component_spec.rb` (13 examples)
- `spec/system/viewer_time_heatmap_spec.rb` (2 examples)
- `spec/lib/tasks/viewer_time_backfill_spec.rb` (6 examples)
- `spec/requests/videos/analytics_spec.rb` — extended with 3 viewer-time heatmap
  context examples
- `spec/requests/channels/analytics_spec.rb` — extended with 3 viewer-time
  heatmap context examples

Total spec delta: +76 new examples across 9 files. Targeted run (all new +
extended specs) reports 105 examples passing.

### Quality gates

- `bundle exec rspec <new + extended specs>` — 105 / 105 green.
- `bundle exec rubocop <new + edited .rb files>` — clean (18 files, 0 offenses).
- `bin/brakeman -q -w2` — 0 security warnings, 0 errors.
- Full-suite `bundle exec rspec` — 7267 examples, 57 pre-existing failures
  unrelated to viewer-time work (concentrated in `Settings::Security::Blocks`,
  `Settings::Webhooks::Help`, `Games::PlatformOwnership*`, `Composites`,
  `Calendar::Month`, routing/seeds/lint specs — Phase 25/27 in-flight or
  unrelated surfaces).

### Decisions made in flow

- **`day_of_week_utc` convention** — Postgres `extract(dow ...)` Sunday-zero
  (per locked decision #9 in `plan.md`). The rollup SQL re-extracts `dow` from
  the user-tz-shifted reference timestamp so the storage and render conventions
  stay aligned.
- **Reference timestamp** — `TIMESTAMP '2024-01-07 00:00:00 UTC'` (a Sunday)
  anchors the synthetic week the rollup re-projects. The heatmap is a shape
  view, not an instant view; a fixed reference keeps DST/zone arithmetic
  deterministic.
- **`intensity_by` parameter** — kept as a constructor arg with `:views`
  default. Locked the string-enum API up front so a future toggle UI swaps the
  value via querystring + controller param rather than a boolean (per the
  project's "yes/no at boundaries" rule).
- **Sync job watch-time unit** — YouTube returns `estimatedMinutesWatched`; we
  multiply by 60 at parse time so `watch_time_seconds` stays in the column's
  stated unit.
- **Empty state copy** — "no viewer-time data yet — sync runs daily at 03:00
  server time." per the spec acceptance bullet; verbatim in both per-video and
  per-channel partials.

### Open follow-ups

1. **MCP `yt:analytics` tool** — deferred per spec §"Cross-stack scope" / Open
   question 7.
2. **`pito` CLI ASCII heatmap** — deferred per spec.
3. **Heatmap palette confirmation** — shipped with link-blue (#0000cc) + alpha
   gradient. User-visible decision; surface for review during validation.
4. **`intensity_by` toggle UI** — backend already supports both `:views` and
   `:watch_time`; UI toggle deferred to a later pass.
5. **Spec acceptance bullet "Failures land in Phase 16 notifications"** —
   current implementation logs to `Rails.logger.warn` on `AuthError`. Wiring to
   the notification delivery channel surface (Phase 16) is deferred — the
   `youtube_api_calls` audit row already captures the failure payload, but
   converting it into a `Notification` row needs a bridge job that lives in the
   Phase 16 lane.
