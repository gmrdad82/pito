# 01h — Video scheduled-publish tz wiring

> Wire the existing scheduled-publish picker through `Current.user.time_zone`.
> Pre-publish checklist + reminder windows render in user-tz; the job that
> triggers the publish converts to UTC at storage and fires at the correct UTC
> instant. **Depends on 01a (timezone foundation).** Implementation agent:
> `pito-rails`.

## Goal

Today, the scheduled-publish picker (introduced via the realignment's "Channel

- Video sync + edit surface" work unit, when it lands) accepts a date + time
  input but does not specify the tz the user sees vs the tz stored. This sub-
  spec pins the contract: the picker is in user-tz, the storage is UTC, the job
  fires at the correct UTC instant, the pre-publish checklist + "publishing in 1
  hour" reminder render in user-tz. DST + edge-zone behavior is specced.

If the scheduled-publish surface does NOT exist in main when 01h dispatches
(because the relevant work unit hasn't landed yet), this sub-spec retargets to
wire-up-on-arrival: it ships the spec + helper + render layer, and the
controller / form changes wait for the picker to exist.

## Files touched

### New — Helper

- `app/helpers/scheduled_publish_helper.rb`:
  - `parse_user_local_to_utc(date_str, time_str, user_tz)` — accepts the form's
    date + time strings, parses in the user's tz, returns a UTC `Time`. Raises a
    friendly error on parse failure.
  - `render_publish_at_for_user(publish_at_utc, user_tz, format: :long)` —
    converts the UTC stored value back to the user's tz for re-render.
  - `reminder_window(publish_at_utc, user_tz, offset:)` — given a publish
    instant + an offset (e.g., `-1.hour`), returns the UTC instant the reminder
    job should fire at. Used by the reminder cron.

### New — Specs

- `spec/helpers/scheduled_publish_helper_spec.rb` — happy / sad / edge:
  - Round-trip: pick `2026-06-01 09:00` in `Europe/Bucharest`, store as UTC
    `07:00`, render back to `09:00` user-local. Identity preserved.
  - DST spring-forward (US, 2026-03-08 02:00 → 03:00): scheduling a publish at
    `2026-03-08 02:30` in `America/Los_Angeles` is ambiguous — the helper
    rejects with a friendly error. Scheduling at `2026-03-08 03:30` succeeds.
  - DST fall-back (US, 2026-11-01 02:00 repeated): scheduling at
    `2026-11-01 01:30` is ambiguous — the helper picks the FIRST occurrence
    (pre-fallback) and surfaces a warning. (Confirm with user on dispatch — the
    alternative is to reject as ambiguous.)
  - Edge zones: `Pacific/Kiritimati` (UTC+14), `Pacific/Pago_Pago` (UTC-11),
    `Asia/Kolkata` (UTC+5:30), `Australia/Eucla` (UTC+8:45).
  - Reminder window calculation: 1-hour reminder for a 09:00 user-local publish
    fires at 08:00 user-local. Round-trip through DST.
- `spec/jobs/video_scheduled_publish_job_spec.rb` — extend the existing spec
  (the job itself ships with the scheduled-publish work unit; this sub-spec
  extends the spec to cover tz). Cases:
  - Job fires at the correct UTC instant regardless of the user's tz at schedule
    time.
  - User changes tz between schedule + fire: the stored UTC instant does NOT
    move. The publish fires at the originally-scheduled UTC instant, even though
    the user-local time changed.
- `spec/system/video_scheduled_publish_tz_spec.rb` — critical journey: pick a
  publish time in user-tz, confirm the form re-renders with the same user-local
  time after submit, confirm the DB stored UTC value matches.

### Edited (when scheduled-publish surface exists)

- `app/controllers/videos_controller.rb` (or the relevant scheduled- publish
  controller — verify exact location during dispatch) — pass form input through
  `parse_user_local_to_utc`.
- `app/views/videos/_scheduled_publish_form.html.erb` (or the relevant partial)
  — render the time picker with `data-tz="<%= current_user_tz %>"` so the JS
  picker (if any) labels the input as user-local.
- `app/jobs/video_scheduled_publish_job.rb` (or the relevant job) — no change to
  the firing logic (already UTC); add a guard logging `Current.user.time_zone`
  for observability.
- `app/jobs/video_publish_reminder_job.rb` (or equivalent) — renders the
  reminder body via `l_user_tz` (from 01a). Reminder cron schedule computed via
  the helper's `reminder_window`.

### Read-only inputs

- `app/helpers/time_zone_helper.rb` (from 01a).
- The Phase 4 / future scheduled-publish surface (if it exists when 01h
  dispatches).
- `docs/architecture.md` §"Timezone rendering rule" (from 01f).

## Acceptance

- [ ] `parse_user_local_to_utc` parses date + time strings in the user's tz and
      returns UTC. Rejects ambiguous (DST spring-forward gaps). Documents
      fall-back ambiguity behavior (lean: pick first occurrence, warn).
- [ ] `render_publish_at_for_user` round-trips UTC → user-local for re- render.
      Round-trip is lossless under normal conditions; DST handled explicitly.
- [ ] `reminder_window` computes the UTC instant for an N-offset reminder
      relative to a UTC publish instant + a user tz. Verified across DST
      jurisdictions.
- [ ] When the scheduled-publish form is wired (this sub-spec or the work unit
      that ships the form), the picker is labeled with the user's tz and the
      form submit converts to UTC at storage.
- [ ] The scheduled-publish job fires at the correct UTC instant. The user
      changing tz between schedule + fire does NOT move the UTC instant.
- [ ] Pre-publish checklist + "publishing in 1 hour" reminder render in the
      user's tz at render time (via `l_user_tz`).
- [ ] DST + edge-zone cases all spec-covered: spring-forward, fall-back,
      half-hour offset (`Asia/Kolkata`), quarter-hour offset
      (`Australia/Eucla`), UTC+14 (`Pacific/Kiritimati`), UTC-11
      (`Pacific/Pago_Pago`).
- [ ] Yes / no boundary: any JSON / MCP form payload carrying a flag (e.g.,
      "send-reminder enabled") uses `"yes"` / `"no"` strings. The tz string and
      the date / time strings are not Booleans; not affected.
- [ ] Friendly URLs preserved.
- [ ] No JS `confirm` / `alert` / `prompt` / `data-turbo-confirm`. The time
      picker is a `<input type="datetime-local">` or an existing Stimulus
      picker; either way no JS confirmation.
- [ ] Spec pyramid covers: helper (happy / sad / edge), job extension, system
      (critical journey).
- [ ] Brakeman + bundler-audit clean.

## Manual test recipe

1. `bin/dev` running. Open a video's edit / publish page (or the relevant
   scheduled-publish surface).
2. The user's tz is `Europe/Bucharest`. Pick a publish time of
   `2026-06-01 09:00`. Submit.
3. In Rails console: `Video.find(...).publish_at.to_s(:db)` shows
   `2026-06-01 07:00:00 UTC` (Bucharest is UTC+3 in DST). Reload the edit page —
   the picker re-renders `2026-06-01 09:00` user-local.
4. Change the user's tz to `America/Los_Angeles` via `/settings`. Reload the
   edit page. The picker now renders `2026-06-01 00:00` user-local (LA is UTC-7
   in DST). The stored UTC instant did NOT change.
5. In Rails console: `travel_to Time.parse("2026-06-01 06:55 UTC")`. Run the
   reminder cron. The 1-hour reminder fires for the user, body says "Publishing
   in 1 hour at 02:00 Los Angeles time" (or wherever the user is now).
6. `travel_to Time.parse("2026-06-01 07:00 UTC")`. Run the publish cron. The
   video publishes (Stub the YouTube API call). The job's log line includes
   `time_zone=America/Los_Angeles` for observability.
7. Re-run with a DST spring-forward scenario (US, 2026-03-08 02:30 LA tz): the
   form rejects with "That time does not exist due to DST spring-forward."

## Cross-stack scope

| Surface | Status  | Note                                                 |
| ------- | ------- | ---------------------------------------------------- |
| Web     | in      | Primary surface — the scheduled-publish picker form. |
| MCP     | partial | If MCP exposes a "schedule publish" tool (verify on  |
|         |         | dispatch), the input contract uses ISO 8601 with     |
|         |         | explicit tz offset. yes/no boundary on any flag.     |
| CLI     | partial | `pito videos publish --at "2026-06-01 09:00" --tz    |
|         |         | Europe/Bucharest` would mirror the Rails form.       |
|         |         | Defer to a CLI parity pass.                          |
| Website | out     | No change.                                           |

## Open questions

1. **DST fall-back ambiguity policy.** v1 leans: pick the FIRST occurrence
   (pre-fallback) and surface a non-blocking warning. Alternative: reject as
   ambiguous and force the user to pick a different time. **Confirm with user.**
2. **Scheduled-publish surface availability.** If the work unit shipping the
   picker hasn't landed when 01h dispatches, 01h ships the helper + render layer
   only. The form / controller wiring waits for the picker. **Confirm with user
   — go now or wait?**
3. **Reminder offsets.** v1: `[-30.minutes, -1.hour]` reminder window.
   Configurable per-user later. **Confirm with user.**
4. **MCP + CLI surfaces.** Both deferred for v1. **Confirm with user.**
5. **Cross-tz edit warning.** If a user with tz `A` schedules a publish, then
   another user with tz `B` opens the edit page (or `Current.user` changes tz
   between sessions), does the form warn about the tz change? v1 leans no — the
   picker always shows in the current user's tz; the stored UTC value is the
   source of truth. **Confirm with user.**
