# 01e — Daily digest scheduler

> Hourly cron + cross-tz user pickup + provider-specific payload rendering +
> retry-on-transient-failure delivery. **Depends on 01a (timezone foundation)
> and at least one of 01b / 01c (webhook panes).** Implementation agent:
> `pito-rails`.

## Goal

Fire a daily digest at 09:00 in each user's local timezone, to each of the
user's enabled webhook channels (Slack and/or Discord). Cron triggers every hour
at minute 0; the job picks users whose local time has just crossed 09:00 since
the last hourly run, renders a provider-specific payload (Slack blocks, Discord
embeds), and POSTs to each user's enabled `notification_delivery_channels` row
where `daily_digest = true`. Transient delivery failures retry; permanent
failures (4xx that aren't 429) give up cleanly and surface the error in a future
Notifications surface (Phase 16's in-app inbox). DST + edge-zone behavior is
specced exhaustively.

## Goal — content shape

Per provider, the digest summarizes the last 24 hours of pito activity:

- Channels synced (count + names).
- Videos imported / updated (count + titles).
- Footage imported (count + project names).
- Login attempts (if security feature ships before 01e — flag the dependency).
- Voyage / Meilisearch index status changes.
- Open notifications from Phase 16's notification table.

The exact field set is locked once the user resolves the "digest content shape
per provider" open question in `../plan.md`.

## Files touched

### New

- `db/migrate/YYYYMMDDHHMMSS_add_last_digest_run_at_to_users.rb` —
  `add_column :users, :last_digest_run_at, :datetime`, NOT NULL, default
  `Time.current` at migration time (so the first cron run after deploy doesn't
  double-fire). UTC-stored, per the storage rule.
- `app/jobs/daily_digest_scheduler_job.rb` — cron entry point. Runs hourly at
  minute 0. Picks users via:
  ```sql
  SELECT * FROM users
  WHERE EXISTS (
    SELECT 1 FROM notification_delivery_channels c
    WHERE c.user_id = users.id AND c.digest_enabled = true
  )
    AND last_digest_run_at < (utc_now - interval '23 hours')
    AND (
      -- the user-local 09:00 instant for "today" has passed
      ...
    );
  ```
  (Approximate; the Ruby-side picks the exact set via
  `ActiveSupport::TimeZone#parse("09:00")` and compares.) For each picked user,
  enqueues `DailyDigestDeliveryJob.perform_later(user_id)` and stamps
  `last_digest_run_at = Time.current`.
- `app/jobs/daily_digest_delivery_job.rb` — per-user delivery job. Loads the
  user's enabled `notification_delivery_channels` (digest_enabled = true),
  builds the digest payload via `Digests::Builder`, formats per provider via
  `Digests::SlackFormatter` / `Digests::DiscordFormatter`, POSTs via
  `Webhooks::SlackClient#deliver` / `Webhooks::DiscordClient#deliver`. Retries
  on transient failures (429
  - 5xx) via Sidekiq retry; gives up on permanent failures (400 / 401 / 404
    / 410) with an error log + a row in the `notifications` table (Phase 16)
    tagged as `kind: "digest_delivery_failed"`.
- `app/services/digests/builder.rb` — pure-Ruby builder. Reads the last 24h of
  pito activity, returns a structured Hash with sections. Provider-agnostic.
- `app/services/digests/slack_formatter.rb` — renders the Hash as Slack blocks
  (Block Kit). Returns a Hash POSTable as JSON.
- `app/services/digests/discord_formatter.rb` — renders the Hash as Discord
  embeds. Returns a Hash POSTable as JSON.
- `config/sidekiq.yml` (or `config/schedule.yml` if sidekiq-cron is wired there)
  — register the hourly cron entry:
  ```yaml
  daily_digest_scheduler:
    cron: "0 * * * *"
    class: DailyDigestSchedulerJob
    queue: default
  ```
- Specs:
  - `spec/jobs/daily_digest_scheduler_job_spec.rb` — picks the right user set
    per cron tick. Time-travel via `Timecop` /
    `ActiveSupport::Testing::TimeHelpers`:
    - User in `Etc/UTC` at 09:00 — picked at the 09:00 cron tick, not at 08:00
      or 10:00.
    - User in `Europe/Bucharest` (UTC+2 in winter, UTC+3 in summer) — picked at
      the 06:00 UTC tick in summer (DST), the 07:00 UTC tick in winter.
    - User in `Pacific/Kiritimati` (UTC+14) — picked at the 19:00 UTC tick on
      the previous day.
    - User in `Pacific/Pago_Pago` (UTC-11) — picked at the 20:00 UTC tick (next
      day local 09:00 = 20:00 UTC the day before).
    - DST spring-forward (US): clock jumps from 02:00 to 03:00 on the target
      day. The user-local 09:00 instant still exists (it's after the jump).
      Picked at the corrected UTC tick. Specs cover both the day of the jump and
      the day after.
    - DST fall-back (US): clock repeats 02:00. The user-local 09:00 instant is
      unambiguous. Fires once.
    - Edge: user changed tz between two cron ticks. The next tick picks them
      based on the new tz. `last_digest_run_at` guard prevents double-fire if
      the tz change moved 09:00 backwards.
    - Edge: user enabled `digest_enabled` after today's 09:00 already passed.
      Spec confirms they're NOT picked today; first digest fires tomorrow at
      09:00 user-local.
  - `spec/jobs/daily_digest_delivery_job_spec.rb` — per-user delivery happy /
    sad / edge:
    - One channel enabled (Slack only) — delivers to Slack.
    - Two channels enabled (Slack + Discord) — delivers to both.
    - Zero channels enabled — no-op, no error.
    - Slack returns 200, Discord returns 204 — both counted as success.
    - Slack returns 429 — Sidekiq retries with backoff.
    - Slack returns 500 — Sidekiq retries.
    - Discord returns 404 (webhook deleted) — does NOT retry, logs error,
      creates a notifications row.
    - Discord returns 401 — same as 404 (permanent).
    - Network timeout — Sidekiq retries.
    - User has no activity in the last 24h — `Digests::Builder` returns an "all
      quiet" payload; still delivered (per Mobile note's intent).
  - `spec/services/digests/builder_spec.rb` — section-by-section happy / empty /
    edge.
  - `spec/services/digests/slack_formatter_spec.rb` — renders all sections
    correctly as Slack Block Kit. Empty sections suppressed.
  - `spec/services/digests/discord_formatter_spec.rb` — renders all sections
    correctly as Discord embeds. Empty sections suppressed.
  - `spec/system/daily_digest_e2e_spec.rb` — critical journey: tick
    `daily_digest` in both panes, fast-forward time to the user's local 09:00,
    run the scheduler job inline, assert both WebMock stubs were called with the
    right payload.

### Edited

- `app/models/user.rb` — add `last_digest_run_at` to the whitelist / cast / etc
  as needed.
- `config/locales/en.yml` — copy for the "all quiet" digest fallback, digest
  section headers per provider.

### Read-only inputs

- `notification_delivery_channels` table (Phase 16; see also 01b + 01c).
- `app/services/webhooks/slack_client.rb` (from 01b).
- `app/services/webhooks/discord_client.rb` (from 01c).
- `app/helpers/time_zone_helper.rb` (from 01a) — used to render in-digest
  timestamps in the user's local tz.

## Acceptance

- [ ] Migration adds `last_digest_run_at` to `users`, NOT NULL, defaults to
      migration-time `Time.current` for existing rows.
- [ ] Cron entry registered in `config/sidekiq.yml` (or wherever sidekiq-cron
      reads from): `cron: "0 * * * *"` → `DailyDigestSchedulerJob`.
- [ ] `DailyDigestSchedulerJob` picks users whose user-local time has JUST
      crossed 09:00 since the previous run, per the time-travel specs above.
      Idempotent: re-running the job in the same hour does NOT double-fire.
- [ ] `DailyDigestDeliveryJob` delivers to ALL enabled
      `notification_delivery_channels` for the user where
      `digest_enabled = true`. Slack + Discord parallel-safe (each gets its own
      POST).
- [ ] Transient failures (429, 5xx, timeouts) retry via Sidekiq's default retry.
      Permanent failures (400, 401, 403, 404, 410) do NOT retry; they log +
      create a Phase 16 notification.
- [ ] Provider-specific payloads: Slack Block Kit, Discord embeds. Identical
      source data, two distinct shapes.
- [ ] DST behavior: spring-forward + fall-back specced. The job fires once per
      user per day regardless of DST transitions.
- [ ] Edge-tz coverage: `Pacific/Kiritimati`, `Pacific/Pago_Pago`,
      `Asia/Kolkata` (half-hour offset), `Australia/Eucla` (45-minute offset).
- [ ] Yes / no boundary: any JSON / MCP / form payload carrying the
      digest-enabled flag uses `"yes"` / `"no"` at the wire (already handled by
      01b + 01c; verify here).
- [ ] No JS `confirm` / `alert` / `prompt` — this sub-spec is all backend.
- [ ] Spec pyramid covers: job (scheduler + delivery), service (builder,
      slack_formatter, discord_formatter), system (E2E).
- [ ] Brakeman + bundler-audit clean.

## Manual test recipe

1. `bin/dev` running. Webhooks configured on both Slack + Discord with
   `daily_digest = true`.
2. In Rails console:
   ```ruby
   user = User.last
   user.update!(time_zone: "Europe/Bucharest", last_digest_run_at: 24.hours.ago)
   travel_to user.tz.parse("09:00 today") + 1.minute do
     DailyDigestSchedulerJob.new.perform
   end
   ```
3. Watch both Slack + Discord channels — a digest message lands in each within
   seconds.
4. Repeat with `user.update!(time_zone: "Pacific/Kiritimati")` and a matching
   `travel_to` block. Digest lands at the right UTC instant.
5. Trigger a deliberate failure: change one webhook URL to a known-bad one
   (server-side 404), then re-run the scheduler. The other delivery succeeds;
   the failing one creates a notifications row with
   `kind: "digest_delivery_failed"`.
6. Verify idempotence: run the scheduler twice within the same hour. The second
   run does NOT re-deliver (the `last_digest_run_at` guard prevents it).

## Cross-stack scope

| Surface | Status  | Note                                               |
| ------- | ------- | -------------------------------------------------- |
| Web     | partial | Settings panes (01b + 01c) read the digest_enabled |
|         |         | state. Failure surface lands in Phase 16's in-app  |
|         |         | notifications inbox.                               |
| MCP     | out     | Digest is server-side delivery; no MCP surface.    |
| CLI     | out     | Server-side; no CLI surface.                       |
| Website | out     | No change.                                         |

## Open questions

1. **Digest content shape.** The Mobile note describes the v1 sections at a high
   level. Detailed field selection per section needs user input (e.g., do we
   include OAuth token expiry warnings? Voyage quota? Sidekiq queue depth?).
   **Confirm with user before dispatch.**
2. **"All quiet" fallback.** When the last 24h had zero activity, the digest
   still fires per the Mobile note. v1 sends a one-line "no activity in the last
   24 hours" message. **Confirm with user.**
3. **DST transition policy.** Spring-forward across 09:00: fire at the next slot
   (10:00 user-local). Fall-back at 09:00: fire once (track
   `last_digest_run_at`). **Confirm with user.**
4. **Retry budget.** Sidekiq's default retry count (25) is excessive for
   transient webhook failures. v1 caps at 5 retries with exponential backoff.
   **Confirm with user.**
5. **Bulk-vs-per-user delivery.** Each user gets a per-user
   `DailyDigestDeliveryJob`. For 100+ users this fans out cleanly. **Confirm
   with user that the architecture matches expectations.**
6. **Delivery failure visibility.** Failures land in Phase 16's in-app
   notifications inbox. Does the user also want an email fallback when webhook
   delivery permanently fails? v1 leans no. **Confirm.**
