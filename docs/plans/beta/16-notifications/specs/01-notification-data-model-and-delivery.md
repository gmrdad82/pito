# Phase 16 §1 — Notification Data Model + Delivery Channels

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. MCP +
> in-app UI live in §3. Formatter lives in §2.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 8. Resolved ambiguity #6:
>   all-users-see-all; webhooks install-level (one each, shared); no per- user
>   opt-in; no per-user read state.
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile note
>   5, notifications half. Source of truth for `notification` row shape, kinds,
>   severity ladder, scheduler cadence, retry policy, suppression rules. Note
>   5's `delivery_channel` table is collapsed in v1 to install-level
>   credentials + AppSetting flags per the realignment ambiguity.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
>   `tenant_id` on the new table; secrets in `Rails.application.credentials`.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — MCP tools for
>   this surface land in §3 on the `app` scope; not part of §1.
> - `docs/plans/beta/15-calendar/specs/01-calendar-data-model.md` —
>   `Calendar::NotificationDispatchDeclaration.declarations_for(entry)` is the
>   read contract this phase consumes. Calendar entries → kinds + `fires_at` +
>   severity. The scheduler in §1 materializes `Notification` rows from those
>   declarations and from non-calendar event sources (sync errors, YouTube
>   re-auth needs).
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — `videos.pre_publish_checked_at` and the four `pre_publish_*_ok` booleans
>   gate the `video_pre_publish_check_missed` event source.
> - `CLAUDE.md` — `yes` / `no` for external booleans; secrets in
>   `Rails.application.credentials`; bulk-as-foundation URL pattern; monospace
>   13px design; no JS `confirm` / `alert` / `prompt`.

## Goal

Bring up the `notifications` table, the `Notification` model, and the two
install-level webhook delivery channels (Discord + Slack) plus the in-app
delivery channel (which is just "the row exists and is unread"). Wire the
scheduler that walks `Calendar::NotificationDispatchDeclaration` output to
materialize `Notification` rows at the right times. Wire the non-calendar event
sources (sync errors; YouTube re-auth needs). Implement the retry / backoff loop
for webhook failures with idempotent re-delivery semantics. Surface a
per-channel "delivered_at" timestamp so the formatter (§2) and the UI (§3) can
render delivery state without re-running the webhook.

This is realignment work unit 8's data + delivery tier. §2 ships the formatter
that turns a `Notification` into a Discord / Slack / MCP / in-app payload. §3
ships the in-app inbox UI + MCP tools.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Audience model.** All-users-see-all. Single shared notification stream. NO `notification_reads(notification_id, user_id, read_at)` join. NO per-user filter on the index. `notifications.in_app_read_at` is a single nullable timestamp on the row; any authenticated user marking-read marks-for-everyone. Per realignment ambiguity #6.                                                                                                                                                                                                                                                                                                                                                         |
| Q2  | **Delivery channel surfaces.** Four:                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
|     | (a) **In-app** — the row exists. "Delivered" means the row was inserted; `created_at` doubles as `in_app_delivered_at`. Read-state via `in_app_read_at`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
|     | (b) **Discord webhook** — install-level webhook URL in credentials. `discord_delivered_at` stamped on success.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
|     | (c) **Slack webhook** — install-level webhook URL in credentials. `slack_delivered_at` stamped on success.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
|     | (d) **MCP** — pull-only. No "delivered" state for MCP; tools in §3 read the same rows the in-app inbox sees.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Q3  | **Channel abstraction.** `NotificationDeliveryChannel` base class (POROs, NOT models — channels are not persisted; configuration is install-level). Two concrete subclasses: `NotificationDeliveryChannel::Discord`, `NotificationDeliveryChannel::Slack`. Common interface: `enabled?`, `deliver(notification)`, `delivered_at_column`. The base class owns retry semantics; subclasses own payload assembly + endpoint POST. The formatter (§2) provides the per-channel payload via a separate `NotificationFormatter` collaborator — see §2.                                                                                                                                                    |
| Q4  | **Webhook credentials shape.** `Rails.application.credentials.notifications.discord_webhook_url` and `.slack_webhook_url`. Both nullable (the user may have only one configured, both, or neither). Read at delivery time; missing URL means `enabled?` returns false (delivery short-circuits, in-app row still lands).                                                                                                                                                                                                                                                                                                                                                                            |
| Q5  | **AppSetting feature flags.** Two new boolean columns on `app_settings`: `discord_enabled` (default `false`) and `slack_enabled` (default `false`). Both must be true AND the corresponding webhook URL must be present for delivery to fire. The Settings UI (deferred — see "Out of scope") later toggles these without a deploy.                                                                                                                                                                                                                                                                                                                                                                 |
| Q6  | **Event sources.** Six (per the brief):                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
|     | (a) **`video_published`** — fires when a `Video` transitions to `privacy_status: public` or `:unlisted`. Source: Phase 12 + Phase 15's `video_published` calendar entry derivation.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
|     | (b) **`video_pre_publish_check_missed`** — fires when a sync-back observes a video that is `public` / `unlisted` AND `pre_publish_checked_at IS NULL` (i.e., the user published outside pito; the checklist surface never ran). Architect's choice: post-publish detection ONLY. Pito does NOT block publish on missed checks; the notification is informational.                                                                                                                                                                                                                                                                                                                                   |
|     | (c) **`game_release_upcoming`** + **`game_release_today`** — fires at T-30 / T-7 / T-1 / T-0 (severity escalating per note 5's ladder). Suppression on linked `purchase_planned` per Phase 15's declaration shape. Source: `Calendar::NotificationDispatchDeclaration`.                                                                                                                                                                                                                                                                                                                                                                                                                             |
|     | (d) **`milestone_reached`** — fires when a `MilestoneRule` fires (Phase 15 + 13). Source: `Calendar::NotificationDispatchDeclaration` for the `milestone_auto` calendar entry.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
|     | (e) **`calendar_entry_firing`** — fires when a manual milestone / custom calendar entry's `starts_at` is reached AND the entry has been flipped to `occurred` by Phase 15's `OccurredFlipper`. Architect promotes this to a real notification source despite note 5 not naming it explicitly — it's the natural surface for "manual milestone happened." See Open question #1 if disagreement.                                                                                                                                                                                                                                                                                                      |
|     | (f) **`sync_error`** — fires when a sync job (channel sync, video sync-back, analytics sync) raises a typed error. Source: Phase 7's `Youtube::Client` audit + Phase 12's `VideoSyncBack` job + Phase 13's analytics sync engine. The job calls a `NotificationSource::SyncError.report!(...)` helper that inserts a `Notification` row with severity `urgent`.                                                                                                                                                                                                                                                                                                                                     |
|     | (g) **`youtube_reauth_needed`** — fires when a `YoutubeConnection` (post-Phase-9) flips `needs_reauth = true`. Source: Phase 7. The Phase-7 `OAuth::TokenRefresher` calls `NotificationSource::YoutubeReauthNeeded.report!(connection)` on the flip. Severity `urgent`.                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Q7  | **Storage shape.** Single `notifications` table per the brief: `id, kind, title, body, url, event_type, event_payload (jsonb), severity, in_app_read_at, discord_delivered_at, slack_delivered_at, last_error, retry_count, scheduled_for, fires_at, source_calendar_entry_id, source_milestone_rule_id, created_by_user_id, created_at, updated_at`. UUIDs per ADR 0003. The `kind` and `event_type` distinction: `kind` is the notification-class enum (one of the seven event sources above; UI categorizes by this); `event_type` is the canonical machine-readable string used for templating + analytics + future filtering (matches the calendar `entry_type` plus the non-calendar values). |
| Q8  | **Tenant-free.** No `tenant_id`. Per ADR 0003.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Q9  | **Retention.** Forever for v1. No pruning job. Pito's scale doesn't need it. Open question #2 captures this for the user to confirm.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Q10 | **Idempotency.** `Notification` rows for calendar-derived events use a `(event_type, source_calendar_entry_id, fires_at)` unique index so the scheduler's twice-per-minute walk never double-creates. Non-calendar events use `(event_type, dedup_key)` where `dedup_key` is supplied by the source (e.g., `"channel-sync-#{channel.id}-#{Date.current}"` for sync errors — one notification per channel per day even on repeated retries).                                                                                                                                                                                                                                                         |
| Q11 | **Retry posture for webhook delivery.** Sidekiq job retries with exponential backoff: 1m, 5m, 15m, 1h, 6h. After the 5th failure, the channel-specific `*_delivered_at` stays NULL forever, `last_error` carries the final reason, `retry_count` carries 5. The in-app row stays visible (delivery to the user-visible inbox is independent of webhook delivery). NO automatic disable of the channel; per Open question #4 the user decides whether 410 Gone deserves a special-case auto-disable.                                                                                                                                                                                                 |
| Q12 | **Read-state shape.** Single `in_app_read_at` column on the row, nullable. NULL = unread; non-NULL = read by some user at that time. Marking-read is a write to the row. Marking-unread is a write to NULL. No separate per-user join. Per Q1.                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Q13 | **Yes / no boundary.** Per CLAUDE.md, every external boolean (URL params, JSON, MCP I/O) uses `"yes"` / `"no"`. The MCP tools in §3 emit `"yes"` / `"no"` for `read` / `delivered`. Internal storage stays Boolean / timestamp. §3 owns the conversion; §1 owns the timestamp columns.                                                                                                                                                                                                                                                                                                                                                                                                              |
| Q14 | **Test posture.** Exhaustive per the brief.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

## Migration posture (LOCKED)

**Additive on the post-Phase-8/12/14/15 schema.** This phase runs after:

- Phase 8 has dropped `tenant_id` everywhere and reseeded.
- Phase 12 has expanded `videos`.
- Phase 14 has expanded `games`.
- Phase 15 has shipped `calendar_entries` + `milestone_rules` + the
  `Calendar::NotificationDispatchDeclaration` service.

Therefore:

- `add_column` / `create_table` only. No `drop_column`, no `rename_table`.
- `add_foreign_key` for the typed FK (`source_calendar_entry_id`,
  `source_milestone_rule_id`, `created_by_user_id`).
- Rollback is permitted (mechanical) but not a hard requirement; document a
  `change` block where Rails can auto-reverse and a manual `up` / `down` only
  where it cannot.

If the implementation agent finds a column or table already exists, STOP and
surface — do not silently reuse.

## Files touched

### Schema / migrations

- `db/migrate/<NN>_create_notifications.rb` (new) — central table.
- `db/migrate/<NN>_add_webhook_flags_to_app_settings.rb` (new) — adds
  `discord_enabled` (boolean, default `false`, NOT NULL) and `slack_enabled`
  (boolean, default `false`, NOT NULL) to `app_settings`. Implementation agent
  verifies the columns do not already exist; if either does, that part of the
  migration is a no-op.
- `db/schema.rb` — auto-regenerated. Acceptance check: every column + index
  listed in §"Schema" below appears with the declared type + nullability +
  default.

### Models

- `app/models/notification.rb` (new) — central model. See §"Model:
  Notification".
- `app/models/app_setting.rb` (light edit) — add accessors / class-level helpers
  `discord_delivery_enabled?` and `slack_delivery_enabled?` that AND the
  AppSetting flag with the credentials check (URL present). Pattern matches the
  existing `voyage_configured?` / `voyage_indexing_project_notes?` helpers.

### Services / channels

- `app/services/notification_delivery_channel.rb` (new) — base class. Single
  public method `deliver(notification)` returning a result struct (`:ok` /
  `:skipped` / `:failed` with reason). The base owns the retry-aware bookkeeping
  (stamps `*_delivered_at`, `last_error`, `retry_count`); subclasses implement
  `enabled?`, `webhook_url`, `delivered_at_column`, `payload_for(notification)`
  (delegates to §2's formatter), and `perform_post(url, payload)`.
- `app/services/notification_delivery_channel/discord.rb` (new) —
  Discord-specific subclass. Reads
  `Rails.application.credentials.notifications.discord_webhook_url`. Calls the
  §2 formatter's `discord_payload(notification)` method. POSTs via `Net::HTTP`
  (or the existing project-standard HTTP client; the implementation agent picks
  — see Open question #5). Records the call in a hypothetical `webhook_calls`
  audit if Phase 7's audit pattern extends here (Open question #6 — defer until
  needed). Treats 2xx as success; 4xx (except 429) as terminal failure (no
  retry); 5xx + 429
  - network errors as transient (retries via Sidekiq).
- `app/services/notification_delivery_channel/slack.rb` (new) — Slack- specific
  subclass. Same shape, different URL credential key, calls
  `slack_payload(notification)` on the formatter.
- `app/services/notification_delivery_channel/in_app.rb` (new) — no-op delivery
  channel. Exists for symmetry; the in-app "delivery" is the `Notification`
  row's existence. Returns `:ok` synchronously with no HTTP. Useful so the test
  suite + the scheduler can iterate channels uniformly.

### Jobs

- `app/jobs/notification_deliver.rb` (new) — Sidekiq job. Single argument:
  `(notification_id, channel_kind)` where `channel_kind` is `"discord"` /
  `"slack"` / `"in_app"`. Resolves the channel, invokes `deliver`, persists the
  result. Sidekiq `retry: 5` with exponential backoff per Q11. Class-level
  `sidekiq_retry_in` block implements the 1m / 5m / 15m / 1h / 6h ladder.
- `app/jobs/notification_scheduler.rb` (new) — Sidekiq cron job. Runs every
  minute. Walks the calendar for "ripe" declarations (the declaration's
  `fires_at` is in the past AND no `Notification` row exists for
  `(event_type, source_calendar_entry_id, fires_at)`). Inserts the rows;
  enqueues a `NotificationDeliver` job per enabled channel (per row, per channel
  — three channels max). See §"Service: NotificationScheduler" for pseudo-code.
- `config/sidekiq.yml` (light edit) — register the new cron schedule
  (`notification_scheduler` every minute).

### Notification source helpers (non-calendar event sources)

- `app/services/notification_source.rb` (new namespace).
- `app/services/notification_source/sync_error.rb` (new) — class method
  `report!(job:, error:, dedup_key:)`. Inserts a `Notification` row with
  `event_type: "sync_error"`, severity `:urgent`. Idempotent on
  `(event_type, dedup_key)`.
- `app/services/notification_source/youtube_reauth_needed.rb` (new) — class
  method `report!(connection)`. Inserts `event_type: "youtube_reauth_needed"`,
  severity `:urgent`. Idempotent on
  `(event_type, "youtube-reauth-#{connection.id}")`.
- `app/services/notification_source/video_pre_publish_check_missed.rb` (new) —
  class method `report!(video)`. Called by the Phase 12 `VideoSyncBack` job
  after a sync that observes `pre_publish_checked_at IS NULL` AND
  `privacy_status IN ('public', 'unlisted')` AND `published_at IS NOT NULL`.
  Idempotent on `(event_type, "missed-check-#{video.id}")`.

The implementation agent wires these helpers' callsites in the existing jobs
(Phase 7 / 12 / 13). The existing job code is touched ONLY where the `report!`
call is added; no other changes. The implementation agent surfaces a list of
touched files in `log.md`.

### Out of scope (this spec)

- `Notification` formatter (per-event-type templating, Discord embed shape,
  Slack block-kit shape) — Phase 16 §2.
- In-app routes / views / Stimulus controllers — Phase 16 §3.
- MCP tools — Phase 16 §3.
- Settings UI for `discord_enabled` / `slack_enabled` toggles — defer to a
  follow-up. The columns ship in this spec; the toggle UI lands later. For v1,
  the user runs
  `bin/rails runner "AppSetting.first.update!(discord_enabled: true)"` manually
  OR uses the bin/rails console; the manual playbook covers this step.
- Webhook auto-disable on 410 Gone — Open question #4.
- Webhook delivery audit table parallel to `youtube_api_calls` — Open question
  #6.
- Email / push delivery — non-goals.
- Per-user notification preferences — non-goals (per Q1).
- Notification grouping / coalescing across multiple events — Open question #3.
- Pruning / retention — Q9.
- TZ-aware rendering of timestamps inside Discord embeds — defer to §2; for v1
  stamp UTC ISO-8601 in the embed footer and let Discord render it.

## Schema

### `notifications` table (new)

| #   | Column                     | Type          | Null | Default | Index                  | Notes                                                                                                                                                                           |
| --- | -------------------------- | ------------- | ---- | ------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `id`                       | `uuid`        | NOT  | (pk)    | (pk)                   | UUID primary key per ADR 0003.                                                                                                                                                  |
| 2   | `kind`                     | `integer`     | NOT  | —       | btree                  | Rails enum. See §"Enum: kind".                                                                                                                                                  |
| 3   | `event_type`               | `string`      | NOT  | —       | btree                  | Machine-readable canonical name. One of the seven event sources (Q6). Length 1..64.                                                                                             |
| 4   | `severity`                 | `integer`     | NOT  | `0`     | btree                  | Rails enum: `info=0`, `success=1`, `warn=2`, `urgent=3`. Per note 5's severity ladder.                                                                                          |
| 5   | `title`                    | `string`      | NOT  | —       | —                      | Short display name. Length 1..255. Validated. Set by the formatter at insert time.                                                                                              |
| 6   | `body`                     | `text`        | NULL | —       | —                      | Free-form longer description. Max 5000 chars validated.                                                                                                                         |
| 7   | `url`                      | `string`      | NULL | —       | —                      | Where to navigate when clicked / followed. Validated as a URL when present (HTTP/HTTPS or path-relative — see Open question #7).                                                |
| 8   | `event_payload`            | `jsonb`       | NOT  | `{}`    | gin                    | Denormalized snapshot the formatter renders against. Survives source-row mutations (the calendar entry / video / channel can change; the notification body remains historical). |
| 9   | `dedup_key`                | `string`      | NULL | —       | —                      | For non-calendar event sources. NULL for calendar-derived rows (those dedup on `source_calendar_entry_id` + `fires_at`).                                                        |
| 10  | `fires_at`                 | `timestamptz` | NOT  | —       | btree                  | When the notification is scheduled to materialize. For instant-fire events this is the insert moment.                                                                           |
| 11  | `scheduled_for`            | `timestamptz` | NULL | —       | btree (where not null) | For pre-scheduled rows (game-release T-30 / T-7 / T-1) the scheduler inserts the row up to N minutes early and stamps this with the intended fire moment. Q1 of §"Scheduler".   |
| 12  | `in_app_read_at`           | `timestamptz` | NULL | —       | btree (where not null) | NULL = unread. Single shared read-state column per Q1.                                                                                                                          |
| 13  | `discord_delivered_at`     | `timestamptz` | NULL | —       | —                      | Stamped by `NotificationDeliveryChannel::Discord` on success.                                                                                                                   |
| 14  | `slack_delivered_at`       | `timestamptz` | NULL | —       | —                      | Stamped by `NotificationDeliveryChannel::Slack` on success.                                                                                                                     |
| 15  | `retry_count`              | `integer`     | NOT  | `0`     | —                      | Bumped on each retry attempt across all channels (single counter is acceptable for v1; per-channel counters are Open question #8).                                              |
| 16  | `last_error`               | `text`        | NULL | —       | —                      | Last delivery error message. Truncated at 1000 chars.                                                                                                                           |
| 17  | `source_calendar_entry_id` | `uuid`        | NULL | —       | btree (where not null) | FK → `calendar_entries.id`, `dependent: :nullify`. Set for calendar-derived notifications (Q6 a / c / d / e).                                                                   |
| 18  | `source_milestone_rule_id` | `uuid`        | NULL | —       | btree (where not null) | FK → `milestone_rules.id`, `dependent: :nullify`. Set for `milestone_reached` rows (Q6 d). Convenience pointer; the rule is also reachable via the calendar entry.              |
| 19  | `created_by_user_id`       | `uuid`        | NULL | —       | btree (where not null) | FK → `users.id`, `dependent: :nullify`. NULL for system-generated rows. Per ADR 0003. Set when a user manually re-fires a notification (future surface).                        |
| 20  | `created_at`               | `timestamptz` | NOT  | —       | btree                  |                                                                                                                                                                                 |
| 21  | `updated_at`               | `timestamptz` | NOT  | —       | —                      |                                                                                                                                                                                 |

**Composite indexes:**

- `(in_app_read_at, created_at DESC)` — index for the in-app inbox ordering
  ("unread first, recent first"). Partial: `WHERE in_app_read_at IS NULL` for
  the unread-fast-path used by `unread_count`.
- `(event_type, source_calendar_entry_id, fires_at) UNIQUE WHERE source_calendar_entry_id IS NOT NULL`
  — idempotency for calendar-derived rows. Q10.
- `(event_type, dedup_key) UNIQUE WHERE dedup_key IS NOT NULL` — idempotency for
  non-calendar event sources. Q10.

**Foreign keys:**

- `notifications.source_calendar_entry_id → calendar_entries.id`
  (`ON DELETE SET NULL`).
- `notifications.source_milestone_rule_id → milestone_rules.id`
  (`ON DELETE SET NULL`).
- `notifications.created_by_user_id → users.id` (`ON DELETE SET NULL`).

**Check constraints:**

- `(source_calendar_entry_id IS NOT NULL) OR (dedup_key IS NOT NULL)` — every
  row must be uniquely identifiable for idempotent re-creation.

### `app_settings` table — column additions

| #   | Column            | Type      | Null | Default | Notes                                                                                           |
| --- | ----------------- | --------- | ---- | ------- | ----------------------------------------------------------------------------------------------- |
| 1   | `discord_enabled` | `boolean` | NOT  | `false` | Master toggle for Discord webhook delivery. Both this AND a non-blank webhook URL must be true. |
| 2   | `slack_enabled`   | `boolean` | NOT  | `false` | Master toggle for Slack webhook delivery. Both this AND a non-blank webhook URL must be true.   |

## Enum: `kind`

```ruby
enum :kind, {
  video_published: 0,
  video_pre_publish_check_missed: 1,
  game_release_upcoming: 2,
  game_release_today: 3,
  milestone_reached: 4,
  calendar_entry_firing: 5,
  sync_error: 6,
  youtube_reauth_needed: 7
}
```

`event_type` mirrors the enum string for v1. The two columns are kept distinct
so a future split (e.g., `kind` becomes a UI category, while `event_type` grows
to many subtypes) is non-breaking.

## Model: Notification

```ruby
class Notification < ApplicationRecord
  belongs_to :source_calendar_entry,
             class_name: "CalendarEntry",
             optional: true
  belongs_to :source_milestone_rule,
             class_name: "MilestoneRule",
             optional: true
  belongs_to :created_by_user,
             class_name: "User",
             optional: true

  enum :kind, {
    video_published: 0,
    video_pre_publish_check_missed: 1,
    game_release_upcoming: 2,
    game_release_today: 3,
    milestone_reached: 4,
    calendar_entry_firing: 5,
    sync_error: 6,
    youtube_reauth_needed: 7
  }
  enum :severity, { info: 0, success: 1, warn: 2, urgent: 3 }

  validates :event_type, presence: true,
                         length: { in: 1..64 }
  validates :title, presence: true,
                    length: { in: 1..255 }
  validates :body, length: { maximum: 5000 }
  validates :url, length: { maximum: 1000 }
  validates :fires_at, presence: true
  validates :last_error, length: { maximum: 1000 }
  validate :url_is_well_formed_when_present
  validate :idempotency_keys_present

  scope :unread, -> { where(in_app_read_at: nil) }
  scope :read,   -> { where.not(in_app_read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_kind, ->(k) { where(kind: k) }
  scope :ripe_for_delivery, -> {
    where("fires_at <= ?", Time.current)
  }
  scope :pending_discord, -> { where(discord_delivered_at: nil) }
  scope :pending_slack,   -> { where(slack_delivered_at: nil) }

  def mark_read!(at: Time.current)
    update!(in_app_read_at: at)
  end

  def mark_unread!
    update!(in_app_read_at: nil)
  end

  def read?
    in_app_read_at.present?
  end

  def unread?
    !read?
  end
end
```

Validators:

- `url_is_well_formed_when_present`: per Open question #7, the architect picks
  "either an absolute http(s) URL OR a leading-slash app path". The
  implementation agent enforces with a regex and surfaces in the spec.
- `idempotency_keys_present`: enforces the check constraint at the model layer
  (clearer error than Postgres's CHECK message).

## Service: NotificationScheduler

Pseudo-code for the every-minute cron job:

```ruby
class NotificationScheduler
  WINDOW = 5.minutes # how far ahead of fires_at to materialize rows

  def perform
    materialize_calendar_declarations
    materialize_occurred_calendar_entries
  end

  private

  def materialize_calendar_declarations
    horizon = Time.current + WINDOW
    CalendarEntry
      .where(state: %i[scheduled occurred])
      .where("starts_at <= ?", horizon + 365.days) # bound the scan
      .find_each do |entry|
        Calendar::NotificationDispatchDeclaration
          .declarations_for(entry).each do |decl|
            next if decl[:fires_at] > horizon
            ensure_row!(
              event_type: decl[:kind],
              kind: decl[:kind],
              severity: decl[:severity],
              fires_at: decl[:fires_at],
              source_calendar_entry: entry
            )
          end
      end
  end

  def materialize_occurred_calendar_entries
    # For manual milestones / custom entries that just flipped to
    # `occurred` (Phase 15 OccurredFlipper). Phase 15's flipper does
    # not know about Notification; we observe via a scope.
    CalendarEntry
      .where(entry_type: %i[milestone_manual custom])
      .where(state: :occurred)
      .where("starts_at <= ?", Time.current)
      .where.not(id: Notification.where(
        event_type: "calendar_entry_firing"
      ).select(:source_calendar_entry_id))
      .find_each do |entry|
        ensure_row!(
          event_type: "calendar_entry_firing",
          kind: :calendar_entry_firing,
          severity: :info,
          fires_at: entry.starts_at,
          source_calendar_entry: entry
        )
      end
  end

  def ensure_row!(event_type:, kind:, severity:, fires_at:,
                  source_calendar_entry:)
    payload = NotificationPayloadBuilder
      .build(
        event_type: event_type,
        calendar_entry: source_calendar_entry
      )
    notification = Notification.find_or_create_by!(
      event_type: event_type,
      source_calendar_entry_id: source_calendar_entry.id,
      fires_at: fires_at
    ) do |n|
      n.kind = kind
      n.severity = severity
      n.title = payload[:title]
      n.body = payload[:body]
      n.url = payload[:url]
      n.event_payload = payload[:event_payload]
    end
    enqueue_deliveries(notification) if notification.previously_new_record?
  end

  def enqueue_deliveries(notification)
    NotificationDeliver.perform_async(notification.id, "in_app")
    if AppSetting.discord_delivery_enabled?
      NotificationDeliver.perform_async(notification.id, "discord")
    end
    if AppSetting.slack_delivery_enabled?
      NotificationDeliver.perform_async(notification.id, "slack")
    end
  end
end
```

`NotificationPayloadBuilder` is the §2 collaborator — its declaration lives here
as an interface; its implementation lands in §2.

## Service: NotificationDeliveryChannel base

```ruby
class NotificationDeliveryChannel
  Result = Struct.new(:status, :reason, keyword_init: true)

  def self.for(kind)
    case kind.to_s
    when "discord" then Discord.new
    when "slack"   then Slack.new
    when "in_app"  then InApp.new
    else
      raise ArgumentError, "unknown channel: #{kind.inspect}"
    end
  end

  def deliver(notification)
    return Result.new(status: :skipped, reason: :disabled) unless enabled?
    return Result.new(status: :skipped, reason: :already_delivered) if already_delivered?(notification)

    payload = payload_for(notification)
    response = perform_post(webhook_url, payload)

    case response.code.to_i
    when 200..299
      stamp_delivered!(notification)
      Result.new(status: :ok)
    when 400..499
      record_failure!(notification, "HTTP #{response.code}: #{response.body.to_s.first(500)}")
      raise PermanentFailure if response.code.to_i != 429
      Result.new(status: :failed, reason: :rate_limited) # 429 retries
    else
      record_failure!(notification, "HTTP #{response.code}")
      Result.new(status: :failed, reason: :transient)
    end
  rescue => e
    record_failure!(notification, e.message)
    raise # let Sidekiq retry; PermanentFailure is the only swallowed error
  end

  # Subclass interface (must override):
  def enabled?;          raise NotImplementedError; end
  def webhook_url;       raise NotImplementedError; end
  def delivered_at_column; raise NotImplementedError; end
  def payload_for(_n);   raise NotImplementedError; end
  def perform_post(_u, _p); raise NotImplementedError; end

  private

  def already_delivered?(notification)
    notification.read_attribute(delivered_at_column).present?
  end

  def stamp_delivered!(notification)
    notification.update!(
      delivered_at_column => Time.current,
      last_error: nil
    )
  end

  def record_failure!(notification, message)
    notification.update!(
      last_error: message.to_s.first(1000),
      retry_count: notification.retry_count + 1
    )
  end

  class PermanentFailure < StandardError; end
end
```

The `InApp` subclass returns `:ok` immediately with no HTTP. The `Discord` and
`Slack` subclasses delegate `payload_for` to §2's formatter
(`NotificationFormatter::Discord.payload_for(notification)` /
`NotificationFormatter::Slack.payload_for(notification)`).

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Schema

- [ ] `db/schema.rb` shows the `notifications` table with every column + index
      listed in §"Schema".
- [ ] `db/schema.rb` shows the new `discord_enabled` + `slack_enabled` columns
      on `app_settings`.
- [ ] `db/schema.rb` shows the unique partial index on
      `(event_type, source_calendar_entry_id, fires_at)`.
- [ ] `db/schema.rb` shows the unique partial index on
      `(event_type, dedup_key)`.
- [ ] `db/schema.rb` shows the partial index on `in_app_read_at` for the
      unread-fast-path.
- [ ] The migration's `up` runs cleanly on a freshly-loaded schema:
      `bin/rails db:drop db:create db:migrate db:seed` succeeds.
- [ ] The CHECK constraint
      `(source_calendar_entry_id IS NOT NULL) OR (dedup_key IS NOT NULL)` is
      enforced at the database layer.

### Models

- [ ] `Notification` defines the `kind` and `severity` enums per §"Enum: kind".
- [ ] `Notification` defines `unread`, `read`, `recent`, `by_kind`,
      `ripe_for_delivery`, `pending_discord`, `pending_slack` scopes.
- [ ] `Notification#mark_read!` sets `in_app_read_at` and persists.
- [ ] `Notification#mark_unread!` clears `in_app_read_at` and persists.
- [ ] `Notification#read?` / `#unread?` reflect the column.
- [ ] `Notification` validates URL well-formedness.
- [ ] `Notification` rejects rows with neither `source_calendar_entry_id` NOR
      `dedup_key` (model + DB).
- [ ] `AppSetting.discord_delivery_enabled?` returns true iff
      `discord_enabled = true` AND credentials carry a non-blank
      `notifications.discord_webhook_url`.
- [ ] `AppSetting.slack_delivery_enabled?` mirrors the above for Slack.

### Services / channels

- [ ] `NotificationDeliveryChannel.for("discord")` returns a Discord instance;
      `.for("slack")` returns Slack; `.for("in_app")` returns InApp; unknown
      kind raises.
- [ ] `Discord#deliver(notification)` POSTs to the credentials URL, stamps
      `discord_delivered_at` on success, records `last_error` on failure.
- [ ] `Slack#deliver(notification)` mirrors the above for Slack.
- [ ] `InApp#deliver(notification)` is a synchronous no-op returning `:ok`.
- [ ] Both `Discord` and `Slack` short-circuit (`:skipped`, reason `:disabled`)
      when `enabled?` returns false (either AppSetting flag false OR webhook URL
      blank).
- [ ] Both `Discord` and `Slack` short-circuit (`:skipped`, reason
      `:already_delivered`) when the column is already stamped.
- [ ] 4xx (except 429) is treated as terminal — the Sidekiq job does NOT retry
      beyond the immediate raise.
- [ ] 5xx + 429 + network errors raise `StandardError` so Sidekiq retries.
- [ ] After 5 failed retries, `retry_count = 5` and `last_error` is the final
      message; the channel column stays NULL.

### Scheduler

- [ ] `NotificationScheduler#perform` walks calendar entries and materializes
      rows for each ripe declaration.
- [ ] Re-running `NotificationScheduler#perform` does NOT create duplicate rows
      (the unique partial index enforces this; the `find_or_create_by!` produces
      no error path other than race- condition tolerance per Sidekiq's
      exactly-once-ish semantics).
- [ ] `NotificationScheduler` enqueues `NotificationDeliver` for each enabled
      channel on row insert (and ONLY on row insert).
- [ ] `NotificationScheduler` materializes `calendar_entry_firing` rows for
      `milestone_manual` / `custom` entries that have flipped to `occurred`.
- [ ] `NotificationScheduler` does NOT re-materialize for entries that already
      have a `calendar_entry_firing` notification row.

### Sidekiq

- [ ] `NotificationDeliver` is a `Sidekiq::Job`.
- [ ] `NotificationDeliver` retries with the 1m / 5m / 15m / 1h / 6h ladder
      (encoded in `sidekiq_retry_in`).
- [ ] `NotificationDeliver` caps at 5 retries (`sidekiq_options retry: 5`).
- [ ] `config/sidekiq.yml` registers the `notification_scheduler` cron schedule
      running every minute.

### Source helpers

- [ ] `NotificationSource::SyncError.report!(...)` inserts a row with
      `event_type: "sync_error"`, `severity: :urgent`, the supplied `dedup_key`.
- [ ] `NotificationSource::SyncError.report!(...)` is idempotent: a second call
      with the same `dedup_key` does NOT insert a duplicate.
- [ ] `NotificationSource::YoutubeReauthNeeded.report!(connection)` inserts an
      `urgent` row idempotent on
      `("youtube_reauth_needed", "youtube-reauth-#{connection.id}")`.
- [ ] `NotificationSource::VideoPrePublishCheckMissed.report!(video)` inserts an
      `info` row idempotent on
      `("video_pre_publish_check_missed", "missed-check-#{video.id}")`.

## Test sweep

The implementation agent owns the full sweep. Each spec name below MUST end up
in the repo on green.

- `spec/factories/notifications.rb` (new) — factory + traits per kind. Each
  trait provides the minimum valid attribute shape (`source_calendar_entry` for
  calendar-derived; `dedup_key` for non-calendar).
- `spec/models/notification_spec.rb` (new) — exhaustive.
- `spec/models/app_setting_spec.rb` (light edit) — add the
  `discord_delivery_enabled?` / `slack_delivery_enabled?` cases.
- `spec/services/notification_delivery_channel_spec.rb` (new) — base class
  behavior (using a test subclass).
- `spec/services/notification_delivery_channel/discord_spec.rb` (new) —
  Discord-specific.
- `spec/services/notification_delivery_channel/slack_spec.rb` (new) —
  Slack-specific.
- `spec/services/notification_delivery_channel/in_app_spec.rb` (new) — InApp
  no-op.
- `spec/services/notification_scheduler_spec.rb` (new).
- `spec/services/notification_source/sync_error_spec.rb` (new).
- `spec/services/notification_source/youtube_reauth_needed_spec.rb` (new).
- `spec/services/notification_source/video_pre_publish_check_missed_spec.rb`
  (new).
- `spec/jobs/notification_deliver_spec.rb` (new).
- `spec/jobs/notification_scheduler_job_spec.rb` (new — wraps the cron
  registration; the service spec covers behavior).

### Required test cases (exhaustive — implementation agent enumerates each)

#### `spec/models/notification_spec.rb`

Validations:

- [ ] `it "is invalid without an event_type"`.
- [ ] `it "rejects event_type longer than 64 characters"` (boundary).
- [ ] `it "is invalid without a title"`.
- [ ] `it "rejects titles longer than 255 characters"` (boundary).
- [ ] `it "rejects bodies longer than 5000 characters"` (boundary).
- [ ] `it "rejects URLs longer than 1000 characters"` (boundary).
- [ ] `it "accepts a fully-qualified https URL"`.
- [ ] `it "accepts a leading-slash app path"` (e.g., `/videos/1`).
- [ ] `it "rejects a malformed URL"` (e.g., `not-a-url`).
- [ ] `it "rejects a row with neither source_calendar_entry_id NOR     dedup_key"`.
- [ ] `it "accepts a row with source_calendar_entry_id only"`.
- [ ] `it "accepts a row with dedup_key only"`.
- [ ] `it "accepts a row with both source_calendar_entry_id AND     dedup_key"`
      (defensive — both are allowed even though only one is required).
- [ ] `it "is invalid without fires_at"`.
- [ ] `it "rejects last_error longer than 1000 characters"` (boundary).

Enums:

- [ ] `it "exposes the seven kinds"` (one assertion per kind name).
- [ ] `it "exposes the four severities"`.

Scopes:

- [ ] `unread` returns rows where `in_app_read_at IS NULL` only.
- [ ] `read` returns rows where `in_app_read_at IS NOT NULL` only.
- [ ] `recent` orders by `created_at DESC`.
- [ ] `by_kind(:sync_error)` filters correctly.
- [ ] `ripe_for_delivery` returns rows whose `fires_at <= now`.
- [ ] `pending_discord` excludes rows with a stamped `discord_delivered_at`.
- [ ] `pending_slack` excludes rows with a stamped `slack_delivered_at`.

State methods:

- [ ] `mark_read!` stamps `in_app_read_at`.
- [ ] `mark_read!(at:)` accepts an explicit timestamp.
- [ ] `mark_unread!` clears `in_app_read_at`.
- [ ] `read?` reflects the column.
- [ ] `unread?` reflects the column.

Idempotency:

- [ ] Inserting a second row with the same
      `(event_type, source_calendar_entry_id, fires_at)` raises a uniqueness
      error at the DB layer.
- [ ] Inserting a second row with the same `(event_type, dedup_key)` raises a
      uniqueness error at the DB layer.
- [ ] The CHECK constraint is enforced for direct SQL inserts (use
      `ActiveRecord::Base.connection.execute` to bypass model validations and
      assert the DB rejects the row).

Edge cases:

- [ ] `event_payload` defaults to `{}`.
- [ ] `retry_count` defaults to `0`.
- [ ] `severity` defaults to `:info`.
- [ ] Belongs-to associations: `source_calendar_entry` resolves;
      `source_milestone_rule` resolves; `created_by_user` resolves.
- [ ] `source_calendar_entry` deletion sets the FK to NULL (cascade verified by
      inserting a calendar entry, a notification, deleting the entry, asserting
      the row survives with NULL FK).
- [ ] `source_milestone_rule` deletion sets the FK to NULL.
- [ ] `created_by_user` deletion sets the FK to NULL.

Flaw tests:

- [ ] **Smuggle a `<script>` tag in `title` / `body` / `url`**: persisted as
      text; never auto-rendered as HTML (the UI escapes — §3).
- [ ] **Inject a unicode title** (emoji, RTL marks, zero-width joiners): stored
      verbatim; round-trips correctly.
- [ ] **1000 unread notifications**: scope queries return correct count in
      <100ms (the partial index makes this trivial; spec asserts the timing as a
      smoke).
- [ ] **Very long body** (4999 chars): saves; 5001 chars: rejected.

#### `spec/models/app_setting_spec.rb` (additions)

- [ ] `discord_delivery_enabled?` returns true iff `discord_enabled = true` AND
      credentials webhook URL is non-blank.
- [ ] `discord_delivery_enabled?` returns false when `discord_enabled = false`,
      regardless of URL.
- [ ] `discord_delivery_enabled?` returns false when the URL is blank,
      regardless of the flag.
- [ ] `discord_delivery_enabled?` returns false when no AppSetting row exists.
- [ ] Slack mirrors all four cases.

#### `spec/services/notification_delivery_channel_spec.rb`

Base-class behavior (test using a stubbed subclass):

- [ ] `for("discord")` / `for("slack")` / `for("in_app")` return the right
      subclass.
- [ ] `for("unknown")` raises `ArgumentError`.
- [ ] `deliver` short-circuits when `enabled?` is false.
- [ ] `deliver` short-circuits when the row is already delivered.
- [ ] `deliver` calls `payload_for` and `perform_post`.
- [ ] `deliver` stamps the column on 2xx.
- [ ] `deliver` records `last_error` and bumps `retry_count` on 5xx.
- [ ] `deliver` raises on 5xx so Sidekiq retries.
- [ ] `deliver` raises on network error.
- [ ] `deliver` does NOT raise on 4xx (terminal failure path).
- [ ] `deliver` raises on 429 (rate-limit retries).

#### `spec/services/notification_delivery_channel/discord_spec.rb`

- [ ] `enabled?` integrates `AppSetting.discord_delivery_enabled?`.
- [ ] `webhook_url` reads from credentials.
- [ ] `delivered_at_column` is `:discord_delivered_at`.
- [ ] `payload_for` delegates to `NotificationFormatter::Discord.payload_for`.
- [ ] `perform_post` POSTs JSON to the webhook URL with the right Content-Type.
- [ ] **Webmock fixture: 204 No Content**: stamp `discord_delivered_at`, no
      error.
- [ ] **Webmock fixture: 400 Bad Request**: terminal failure; no retry.
- [ ] **Webmock fixture: 401 Unauthorized**: terminal failure.
- [ ] **Webmock fixture: 404 Not Found**: terminal failure.
- [ ] **Webmock fixture: 429 Too Many Requests**: transient; raises.
- [ ] **Webmock fixture: 500 Internal Server Error**: transient; raises.
- [ ] **Webmock fixture: 502 Bad Gateway**: transient; raises.
- [ ] **Webmock fixture: 503 Service Unavailable**: transient; raises.
- [ ] **Webmock fixture: 504 Gateway Timeout**: transient; raises.
- [ ] **Webmock fixture: timeout**: transient; raises.
- [ ] **Webmock fixture: malformed response body** (200 with garbage): stamps as
      success (Discord doesn't require a JSON response).
- [ ] **Retry exhaustion**: after 5 transient failures, `retry_count` stays at
      5; `last_error` carries the final message; column stays NULL.
- [ ] **AppSetting flag false**: `enabled?` false → skipped.
- [ ] **Webhook URL blank in credentials**: `enabled?` false → skipped.
- [ ] **Already delivered**: `delivered_at_column` non-NULL → skipped with
      `:already_delivered`.

#### `spec/services/notification_delivery_channel/slack_spec.rb`

Mirror of Discord cases. Same matrix. Replace credential key + column name +
formatter call.

#### `spec/services/notification_delivery_channel/in_app_spec.rb`

- [ ] `enabled?` always true (the in-app channel is the source of truth).
- [ ] `deliver(notification)` returns `:ok` synchronously without hitting any
      HTTP.
- [ ] `deliver(notification)` does NOT mutate the row (the in-app "delivery" is
      implicit in the row's existence).

#### `spec/services/notification_scheduler_spec.rb`

- [ ] **Calendar declaration → row insert**: a `CalendarEntry` with a ripe
      declaration produces exactly one Notification row.
- [ ] **Re-run does not duplicate**: a second `perform` call for the same window
      does NOT create a duplicate.
- [ ] **Future declaration not yet ripe**: not materialized.
- [ ] **Past declaration**: materialized.
- [ ] **Multiple kinds per entry** (game-release T-7 + T-1 + T-0): each produces
      a separate Notification row, each with its own `fires_at`.
- [ ] **Suppression on `purchase_planned`**: when a `game_release` has a linked
      `purchase_planned` with `notify_anyway = false`, the T-7 and T-1
      declarations are suppressed (Phase 15's declaration logic handles this;
      spec verifies the scheduler honors it).
- [ ] **`notify_anyway = true`**: full ladder fires.
- [ ] **`release_precision` coarser than day**: no offsets fire.
- [ ] **`milestone_auto` entry → `milestone_reached` row**: one row per rule
      firing.
- [ ] **`milestone_manual` entry flipped to `:occurred` →
      `calendar_entry_firing` row**: exactly once.
- [ ] **`custom` entry flipped to `:occurred` → `calendar_entry_firing` row**:
      exactly once.
- [ ] **Already-materialized `calendar_entry_firing`**: no duplicate on
      subsequent runs.
- [ ] **Per-channel enqueue**: `NotificationDeliver` enqueued for `in_app`
      always; for `discord` only when `discord_delivery_enabled?`; for `slack`
      only when `slack_delivery_enabled?`.
- [ ] **No enqueue on `find_or_create_by!` find path**: existing row is returned
      without a delivery enqueue.

#### `spec/services/notification_source/sync_error_spec.rb`

- [ ] `report!(job:, error:, dedup_key:)` inserts a row.
- [ ] Severity is `:urgent`.
- [ ] `event_type` is `"sync_error"`.
- [ ] `event_payload` carries the job class name and the error message.
- [ ] Idempotent: second call with same `dedup_key` returns the existing row.
- [ ] Different `dedup_key` produces a different row.
- [ ] `created_by_user_id` is NULL (system-generated).

#### `spec/services/notification_source/youtube_reauth_needed_spec.rb`

- [ ] `report!(connection)` inserts a row.
- [ ] Severity is `:urgent`.
- [ ] `event_type` is `"youtube_reauth_needed"`.
- [ ] `dedup_key` is `"youtube-reauth-#{connection.id}"`.
- [ ] Idempotent on a second call for the same connection.
- [ ] Different connection ids produce distinct rows.
- [ ] `event_payload` carries the connection's email.
- [ ] `url` points at the YouTube re-auth screen (`/oauth/youtube/start` or
      whatever Phase 7 / 9 lands; implementation agent confirms).

#### `spec/services/notification_source/video_pre_publish_check_missed_spec.rb`

- [ ] `report!(video)` inserts a row.
- [ ] Severity is `:info`.
- [ ] `event_type` is `"video_pre_publish_check_missed"`.
- [ ] `dedup_key` is `"missed-check-#{video.id}"`.
- [ ] Idempotent.
- [ ] `event_payload` carries `video.title` and the missing-check list (which of
      the four `pre_publish_*_ok` booleans were false).
- [ ] `url` points at the video edit page.

#### `spec/jobs/notification_deliver_spec.rb`

- [ ] **In-app channel**: synchronous, no HTTP, returns `:ok`.
- [ ] **Discord channel**: routes to the Discord channel; on success stamps the
      column.
- [ ] **Slack channel**: routes to the Slack channel; on success stamps the
      column.
- [ ] **Unknown channel kind**: raises `ArgumentError`.
- [ ] **Notification not found**: silently no-ops (row was deleted between
      enqueue and run).
- [ ] **Sidekiq retry config**: `sidekiq_options retry: 5`.
- [ ] **`sidekiq_retry_in` ladder**: 60 / 300 / 900 / 3600 / 21600 seconds for
      retries 0..4 (asserted by calling the proc with the retry index and
      matching).

#### Cross-event integration tests

- [ ] **Phase 12 video sync-back observes a missed-check video**:
      `NotificationSource::VideoPrePublishCheckMissed.report!` is called; a row
      lands.
- [ ] **Phase 7 OAuth refresher flips `needs_reauth`**:
      `NotificationSource::YoutubeReauthNeeded.report!` is called.
- [ ] **A sync job raises**: a wrapper helper (the implementation agent picks
      the helper shape) calls `NotificationSource::SyncError.report!` with a
      stable `dedup_key`.

#### Edge cases (across the spec set)

- [ ] **AppSetting row missing**: `discord_delivery_enabled?` returns false
      safely.
- [ ] **Credentials key missing**: `Discord#enabled?` returns false safely.
- [ ] **`fires_at` in the distant future**: scheduler skips.
- [ ] **`fires_at` exactly now**: scheduler materializes.
- [ ] **Multiple notifications fire in the same minute**: scheduler handles all
      in one pass; deliveries enqueue without contention.
- [ ] **Race on `find_or_create_by!`**: the unique index serializes; one row
      lands; the second attempt finds-rather-than-creates.

#### Flaw tests

- [ ] **Smuggle `notification_id` from a different row**: §3 owns this test; §1
      ensures the model has no per-user-id filter that would naturally provide
      IDOR protection (it doesn't — by design, all users see all rows). Verify
      the model has no such filter.
- [ ] **Smuggle a webhook URL via the `event_payload`**: payload is stored as
      data; never used as the delivery target. The delivery target comes from
      credentials only.
- [ ] **Inject untrusted HTML into webhook payload**: §2 owns this test (the
      formatter must escape). §1 verifies the model stores raw text without
      transformation.
- [ ] **Race on dedup_key**: two simultaneous `report!` calls with the same
      `dedup_key` produce exactly one row (DB unique index enforces).

## Manual playbook (post-implementation)

Architect outlines; reviewer fills in remaining steps after spec lands.

1. **Update credentials.** Run
   `bin/rails credentials:edit --environment development`. Add:
   ```yaml
   notifications:
     discord_webhook_url: <your-discord-webhook-url>
     slack_webhook_url: <your-slack-webhook-url>
   ```
   Repeat for `--environment test` if the test suite uses real webhooks via
   WebMock recording (it should not — WebMock stubs cover the integration
   cases).
2. **Run the migration.**
   ```bash
   bin/rails db:migrate
   ```
   Confirm `db/schema.rb` carries the `notifications` table and the two new
   `app_settings` columns.
3. **Toggle delivery flags.**
   ```bash
   bin/rails runner "AppSetting.first.update!(discord_enabled: true, slack_enabled: true)"
   ```
   Or via `bin/rails console`. (The Settings UI toggle lands later.)
4. **Trigger a calendar-derived notification.** With Phase 15 already shipped,
   create a manual `game_release` calendar entry with
   `starts_at = 8.days.from_now`:
   ```bash
   bin/rails console
   CalendarEntry.create!(
     entry_type: :game_release, source: :manual,
     title: "test release", starts_at: 8.days.from_now,
     timezone: "UTC", state: :scheduled,
     metadata: {}, source_ref: nil
   )
   ```
   Wait up to 1 minute (the cron) OR run
   `bin/rails runner "NotificationScheduler.new.perform"` immediately. Confirm a
   `Notification` row lands with `event_type = "game_release_upcoming"` (the T-7
   declaration).
5. **Confirm delivery.** Open Discord; the test webhook channel shows the embed.
   Open Slack; the test webhook shows the block. The `Notification` row's
   `discord_delivered_at` and `slack_delivered_at` are stamped.
6. **Trigger a sync error.**
   ```bash
   bin/rails runner "NotificationSource::SyncError.report!(job: ChannelSync, error: StandardError.new('boom'), dedup_key: 'test-1')"
   ```
   Confirm one row lands with severity `:urgent`. A second call with the same
   `dedup_key` returns the same row (no duplicate).
7. **Trigger a YouTube re-auth.** With Phase 7 shipped:
   ```bash
   bin/rails runner "YoutubeConnection.first.update!(needs_reauth: true); NotificationSource::YoutubeReauthNeeded.report!(YoutubeConnection.first)"
   ```
   Confirm one urgent row lands.
8. **Trigger a missed pre-publish check.** With Phase 12 shipped: create or find
   a `Video` with `privacy_status = :public`, `published_at IS NOT NULL`,
   `pre_publish_checked_at IS NULL`. Run
   `NotificationSource::VideoPrePublishCheckMissed.report!(video)`. Confirm one
   info row lands with `url` pointing at the video edit page.
9. **Test webhook failure.** Misconfigure the Discord URL in credentials (e.g.,
   point at `https://example.com/missing`). Trigger a notification. Confirm the
   in-app row lands; the `discord_delivered_at` stays NULL; `last_error` carries
   the HTTP status. After 5 retries the row stops retrying. Re-fix the URL; run
   `NotificationDeliver.perform_async(<id>, "discord")` manually to confirm a
   fresh delivery succeeds (the row's `discord_delivered_at` stamps).
10. **Run the full RSpec suite.**
    ```bash
    bundle exec rspec
    ```
    Confirm green. Note the spec count delta in `log.md`.
11. **Run rubocop.**
    ```bash
    bundle exec rubocop
    ```
    Confirm clean.
12. **Verify Sidekiq cron.** Open `/sidekiq/cron`. Confirm
    `notification_scheduler` is registered every minute.

## Cross-stack scope

| Surface           | Status                                                |
| ----------------- | ----------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                           |
| MCP rack app      | **Skipped (this spec).** §3 ships the four MCP tools. |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10.                |
| Astro / website   | **Skipped.** N/A.                                     |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **AppSetting flag display labels** (for the future Settings UI). Suggested:
   `discord delivery` / `slack delivery`. User confirms.
2. **Webhook misconfigured warning copy** (rendered in the in-app inbox header
   when a row's `last_error` is non-NULL). Suggested:
   `webhook delivery failing — check credentials`. User confirms.
3. **`event_payload` keys**. The §2 formatter consumes these; spec 1 reserves
   the schema. Suggested keys per kind:
   - `video_published`:
     `{ video_id, video_title, channel_id, channel_title, published_at, watch_url }`
   - `video_pre_publish_check_missed`:
     `{ video_id, video_title, missing_checks: ["game", "age", "paid_promotion", "end_screen"] }`
   - `game_release_upcoming` / `game_release_today`:
     `{ game_id, game_title, release_date, days_until, igdb_url, platforms }`
   - `milestone_reached`:
     `{ rule_id, rule_name, metric, threshold, metric_value_at_fire, scope_type, scope_id }`
   - `calendar_entry_firing`:
     `{ entry_id, entry_type, title, description, starts_at }`
   - `sync_error`: `{ job_class, error_class, error_message }`
   - `youtube_reauth_needed`: `{ connection_id, connection_email }` User
     confirms or picks alternative.
4. **`fires_at` for non-calendar event sources**. Architect picks `Time.current`
   (instant fire). User confirms.
5. **`url` shape for each event**. Architect's defaults:
   - `video_published` → `/videos/:id`
   - `video_pre_publish_check_missed` → `/videos/:id/edit`
   - `game_release_upcoming` / `game_release_today` → `/games/:id`
   - `milestone_reached` → `/calendar/entries/:calendar_entry_id`
   - `calendar_entry_firing` → `/calendar/entries/:calendar_entry_id`
   - `sync_error` → `/sidekiq` (the developer surface) OR `/notifications/:id`
     (the in-app inbox detail). Architect leans `/notifications/:id`.
   - `youtube_reauth_needed` → `/oauth/youtube/start` (Phase 7 re-auth start)
     User confirms.

## Open questions (architect cannot decide; master agent surfaces to user)

1. **`calendar_entry_firing` event source.** Architect promotes manual
   milestones / custom entries to a real notification source despite note 5 not
   naming it explicitly. User confirms or rejects.
2. **Retention policy.** Forever for v1 per Q9. User confirms or sets a pruning
   window (e.g., 1 year).
3. **Notification grouping / coalescing.** Should N `video_published` events
   from one channel within Y minutes collapse into one notification? Architect's
   lean: NO, defer until noise becomes a problem.
4. **Webhook auto-disable on 410 Gone.** When a webhook URL returns 410 Gone
   (Discord / Slack signal of "this hook is dead"), should the system flip
   `discord_enabled` / `slack_enabled` to false automatically? Architect's lean:
   NO for v1; surface in the in-app inbox via a banner instead. The user's
   single-install posture makes manual intervention fine.
5. **HTTP client choice.** Discord + Slack POST. Architect's lean: `Net::HTTP`
   (stdlib) for v1. If the project already standardizes on Faraday or HTTP.rb,
   use that. Implementation agent surfaces if a project-standard exists.
6. **Webhook delivery audit table.** A parallel to `youtube_api_calls` for
   outbound webhook calls. Architect's lean: NO for v1; the `Notification` row's
   `last_error` + `retry_count` carries enough. Surface as a follow-up if
   debugging needs grow.
7. **`url` column shape.** Architect's lean: accept absolute http(s) URLs OR
   leading-slash app paths (`/videos/:id`). Reject anything else. User confirms.
8. **Per-channel retry counters.** Architect ships a single `retry_count` for v1
   (acceptable since all channels follow the same backoff ladder). Per-channel
   counters are a follow-up if needed.
9. **`scheduled_for` vs. `fires_at`**. Architect ships both columns: `fires_at`
   is the canonical "when does this notification fire" (used by the scheduler's
   predicate); `scheduled_for` is reserved for future use (e.g.,
   user-rescheduled rows where the original `fires_at` is preserved). For v1 the
   column is always NULL on insert. Implementation agent may drop
   `scheduled_for` if no v1 call site uses it; user confirms.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. **AppSetting flag display labels** → `discord delivery` / `slack delivery`.
2. **Webhook misconfigured warning copy** →
   `webhook delivery failing — check credentials`.
3. **`event_payload` keys per kind** → Architect's drafts verbatim:
   - `video_published`:
     `{ video_id, video_title, channel_id, channel_title, published_at, watch_url }`
   - `video_pre_publish_check_missed`:
     `{ video_id, video_title, missing_checks: [...] }`
   - `game_release_upcoming` / `game_release_today`:
     `{ game_id, game_title, release_date, days_until, igdb_url, platforms }`
   - `milestone_reached`:
     `{ rule_id, rule_name, metric, threshold, metric_value_at_fire, scope_type, scope_id }`
   - `calendar_entry_firing`:
     `{ entry_id, entry_type, title, description, starts_at }`
   - `sync_error`: `{ job_class, error_class, error_message }`
   - `youtube_reauth_needed`: `{ connection_id, connection_email }`
4. **`fires_at` for non-calendar event sources** → `Time.current` (instant
   fire).
5. **`url` shape per event** → Architect's drafts verbatim. `sync_error` →
   `/notifications/:id`. `youtube_reauth_needed` → `/oauth/youtube/start`.

### Open-question decisions

1. **`calendar_entry_firing` event source** → Yes, ship. First-class promotion
   of manual milestones / custom entries to a notification source.
2. **Retention policy** → Forever for v1. No pruning. If retention becomes a
   problem, add later.
3. **Notification grouping / coalescing** → Defer. Per-event delivery in v1.
   Surface in a follow-up if noise emerges.
4. **Webhook auto-disable on 410 Gone** → No auto-disable in v1. Surface
   failures via the in-app inbox banner. Operator manually disables via
   AppSetting if needed.
5. **HTTP client choice** → `Net::HTTP` (stdlib). Implementation agent surfaces
   if a project-standard HTTP client (Faraday, HTTP.rb) is already established.
6. **Webhook delivery audit table** → No parallel table in v1. The
   `Notification` row's `last_error` + `retry_count` carries enough.
7. **`url` column shape** → Accept absolute http(s) URLs OR leading-slash app
   paths (`/videos/:id`). Reject anything else.
8. **Per-channel retry counters** → Single `retry_count` for v1. Per-channel
   counters are a follow-up if needed.
9. **`scheduled_for` vs `fires_at`** → DROP `scheduled_for` from the v1 schema.
   YAGNI; if user-rescheduling lands later, the column gets added then. Override
   the architect's "ship both" recommendation.

## Non-goals (explicit)

- Per-user notification preferences (per Q1).
- Email delivery.
- Push notifications.
- Notification content from external sources (third-party events).
- CLI parity (work unit 10).
- Settings UI for `discord_enabled` / `slack_enabled` (toggle ships in this spec
  at the column level; UI lands as a follow-up).
- Webhook delivery audit table.
- Per-event-type templating (§2).
- In-app routes / views / Stimulus controllers (§3).
- MCP tools (§3).
- Pruning / retention.
- Webhook auto-disable.

## Implementation lane assignment

Single lane: **rails-impl** (or `pito-rails-impl`). Touches:

- `db/migrate/`, `db/schema.rb`
- `app/models/notification.rb`, `app/models/app_setting.rb`
- `app/services/notification_delivery_channel.rb` + subclasses
- `app/services/notification_source/*`
- `app/services/notification_scheduler.rb`
- `app/jobs/notification_deliver.rb`, `app/jobs/notification_scheduler_job.rb`
- `config/sidekiq.yml`
- `spec/**`

No `extras/cli/`, no `extras/website/`, no `app/views/`, no `app/controllers/`,
no `app/mcp/`, no `docs/`. Spec 2 + Spec 3 own those surfaces.
