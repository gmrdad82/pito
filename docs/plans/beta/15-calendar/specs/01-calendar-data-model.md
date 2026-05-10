# Phase 15 §1 — Calendar Data Model

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. MCP tool
> surface is realignment work unit 9, deferred (lands alongside Phase 16's
> notification tools). Rust CLI parity is realignment work unit 10, deferred.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 7. Resolved ambiguity #5 (month
>   grid + Schedule view, day / week deferred). Resolved ambiguity #6
>   (notification surface defers per-user opt-in; notifications fire from
>   calendar entries — Phase 16).
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. Source of truth for the entry shape, the eight `entry_type` values,
>   type-specific metadata jsonb keys, milestone-rule firing semantics, and
>   purchase-planned linkage.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — no
>   `tenant_id` on any new table.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — post-Phase-8 schema baseline. The `created_by_user_id` column on user-
>   authored rows pattern from ADR 0003 §"Decision" applies here.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12. `videos.published_at`, `videos.publish_at`,
>   `videos.privacy_status`, `videos.title`. Calendar's derived
>   `video_published` / `video_scheduled` entries depend on these.
> - `docs/plans/beta/14-game-model-igdb-sync/specs/01-data-model-and-igdb-client.md`
>   — Phase 14. `games.release_date`, `games.igdb_id`, `games.igdb_slug`,
>   `games.title`. Calendar's `game_release` derived entries depend on these.
> - `CLAUDE.md` — yes/no booleans at every external boundary; secrets in
>   `Rails.application.credentials`; monospace 13px design.

## Goal

Translate Mobile note 5's calendar half into schema + models + auto-derive jobs.
Bring up `calendar_entries` (the unified entry table; eight `entry_type` values;
type-specific `metadata jsonb`) and `milestone_rules` (the declarative rule
table that fires `milestone_auto` calendar entries once analytics thresholds are
crossed). Wire the auto-derivation of `video_published`, `video_scheduled`,
`channel_published`, and `game_release` entries from the canonical source rows;
respect last-write- wins semantics with the `manual_date_override` opt-out for
`game_release`. Wire the `purchase_planned` entry → `game_release` entry
reference per note 5's "Purchase planned" subsection. Declare the
notification-firing hooks (calendar entry → which notification kind / when) so
Phase 16 has a contract to consume; no notification delivery code lands here.

This is realignment work unit 7's data tier. Phase 15 §2 builds the views on top
of these models. Phase 16 builds notifications on top of these models +
milestone rules.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Storage shape — single table with `entry_type` enum + per-type metadata jsonb.** Per note 5's `calendar_entry(...)` model. NOT per-kind tables. Eight enum values: `channel_published`, `video_published`, `video_scheduled`, `game_release`, `purchase_planned`, `milestone_manual`, `milestone_auto`, `custom`. Note 5 calls these eight by name.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Q2  | **Cross-references — direct foreign keys for every typed reference.** NOT polymorphic. Each entry type that references a domain row gets a typed nullable FK column (`video_id`, `game_id`, `channel_id`, `project_id`, `milestone_rule_id`, `parent_entry_id`). Polymorphic was the brief's recommendation; the architect picks typed FKs because (a) each `entry_type` has at most one cross-reference shape, (b) typed FKs let `dependent: :destroy` cascade work cleanly per type, (c) the calendar view queries (`upcoming releases without purchase`) are LEFT JOINs that benefit from typed columns over `entryable_type=...` filters. The brief's "or polymorphic" framing is honored with a typed-FK alternative.                                                       |
| Q3  | **Tenant-free.** No `tenant_id` on any new table. Per ADR 0003.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Q4  | **Source provenance.** Three values: `manual` (user-created), `derived` (written by sync jobs from Video / Channel / Game), `auto` (computed by milestone evaluator from analytics tables). Stored as integer-backed `enum` on `calendar_entries.source`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Q5  | **State.** Four values per note 5: `scheduled`, `occurred`, `cancelled`, `superseded`. Integer-backed enum. Default `scheduled` for future-dated entries; auto-flipped to `occurred` by the daily occurred-flipper job (or stamped on insert if `starts_at` is in the past).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Q6  | **Time zones.** Every timestamp is `timestamptz` (UTC at rest). The `timezone` column on `calendar_entries` stores the IANA tz the entry was authored in, defaulting to the install tz from `AppSetting.timezone` (a new install-level setting added in this spec). Display logic in §2 converts to local. Per note 5's `timezone` field.                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Q7  | **All-day vs. timed.** A boolean `all_day` column. When true, the time portion of `starts_at` / `ends_at` is ignored on display (rendered as "Mar 14" rather than "Mar 14 09:00"). Stored as actual UTC midnight in the entry's authored timezone for unambiguous comparison. Per note 5's `all_day boolean` field.                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Q8  | **Multi-day entries.** A nullable `ends_at`. NULL means point-in-time. Non-null + `all_day=true` is a span (game launch week — single entry spanning days). Non-null + `all_day=false` is a timed span (event from 18:00–22:00). The month grid (§2) renders multi-day entries as a continuous bar across grid cells. Per note 5's `ends_at` field.                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Q9  | **Recurrence.** Out of scope for v1. No recurrence rule format selection. The brief lists "recurring (bool), recurrence_rule (jsonb)"; the architect drops these to keep the data tier tight. Justification: note 5 does NOT mention recurrence — the closest it has is the daily milestone evaluator and the `tba_remind_monthly` per-game flag. Both are handled by background jobs (the milestone evaluator + the reminder scheduler), not by storing a recurrence rule on a single entry. The brief's example ("Video published — every Tuesday at 09:00") is a publishing-cadence concept, not a calendar-entry concept; if it lands later it becomes a separate `publishing_schedule` model. **Defer recurrence to a follow-up spec.** Open question #1 if user disagrees. |
| Q10 | **Milestone rules.** Per note 5's `milestone_rule` shape. Idempotent firing via `fired_at IS NULL` predicate. Disabling does NOT clear `fired_at`; re-arming requires explicit `fired_at = NULL` write (admin-only). This phase ships the model + the evaluator job skeleton; Phase 13 (analytics) ships the actual metric reads, Phase 16 the delivery.                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Q11 | **Purchase planned linkage.** A `purchase_planned` entry's metadata holds `game_release_entry_id` (the parent `calendar_entries.id`). The architect promotes this from metadata-jsonb to a real `parent_entry_id` foreign key column (typed, indexed, `dependent: :nullify`). Per Q2 — typed FKs over JSON pointers. The other purchase fields (`purchase_kind`, `storefront`, `storefront_name`, `storefront_url`, `amount`, `currency`, `ordered_at`, `confirmation_ref`) stay in `metadata jsonb`.                                                                                                                                                                                                                                                                            |
| Q12 | **Manual milestones.** Stored with `entry_type='milestone_manual'`, `source='manual'`, no FK to anything. Per note 5's "Manual milestones" subsection.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Q13 | **Custom entries.** `entry_type='custom'`, `source='manual'`. Free-form. No FK. Per note 5's `custom` enum value.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Q14 | **`created_by_user_id`.** Per ADR 0003 §"Decision": user-authored rows carry `created_by_user_id` (nullable for system-created `derived` / `auto` rows). Display only — never used for access control.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Q15 | **Read-only enforcement for derived / auto entries.** Model-level: `before_save` callback rejects writes to derived / auto entries except for the `metadata.user_overrides` jsonb sub-key (per note 5's "Derived and auto entries should not be hand-edited"). The controller layer (§2) renders these as read-only. Re-syncs overwrite by `(entry_type, source_ref)` upsert.                                                                                                                                                                                                                                                                                                                                                                                                    |
| Q16 | **`source_ref` shape.** A jsonb column carrying typed pointers per note 5: `{channel_id: <uuid>}` for `channel_published`, `{video_id: <uuid>}` for `video_published` / `video_scheduled`, `{game_id: <uuid>, igdb_id: <int?>}` for `game_release`, `{milestone_rule_id: <uuid>, metric_value_at_fire: <num>}` for `milestone_auto`. Indexed via GIN for re-sync upsert lookups.                                                                                                                                                                                                                                                                                                                                                                                                 |
| Q17 | **Notification-firing hooks.** This phase declares which calendar entries trigger which notification `kind` and at which offsets. Stored as a class-level `NOTIFICATION_KINDS_FIRED_BY_TYPE` constant + an `enqueueable_notifications_for(entry)` Calendar service. Phase 16 reads these declarations to build the actual `Notification` rows. NO `notifications` table is created in this phase — Phase 16 owns it.                                                                                                                                                                                                                                                                                                                                                             |
| Q18 | **Test posture.** Exhaustive per the brief. Every entry type, every recurrence skip, every cross-reference path, every edge case. Specs enumerated in §"Test sweep".                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |

## Migration posture (LOCKED)

**Additive on the post-Phase-8/12/14 schema.** This phase runs after:

- Phase 8 has dropped `tenant_id` everywhere and reseeded.
- Phase 12 has expanded `videos` with `published_at`, `publish_at`,
  `privacy_status`, `title`, etc.
- Phase 14 has expanded `games` with `release_date`, `igdb_id`, `igdb_slug`,
  `title`.

Therefore:

- `add_column` / `create_table` only. No `drop_column`, no `rename_table`.
- `add_foreign_key` for every typed FK on `calendar_entries`.
- Rollback is permitted (mechanical) but not a hard requirement; document a
  `change` block where Rails can auto-reverse and a manual `up` / `down` only
  where it cannot.

If the implementation agent finds a column or table already exists, STOP and
surface — do not silently reuse.

## Files touched

### Schema / migrations

- `db/migrate/<NN>_create_calendar_entries.rb` (new) — central table.
- `db/migrate/<NN>_create_milestone_rules.rb` (new) — declarative rule table.
- `db/migrate/<NN>_add_calendar_timezone_to_app_settings.rb` (new) — adds the
  install-level `timezone` column to `app_settings`. Default `"UTC"`. The
  implementation agent verifies the column does not already exist; if it does,
  that migration is a no-op.
- `db/schema.rb` — auto-regenerated. Acceptance check: every column + table
  listed in §"Schema" below appears with the declared type + nullability +
  default.

### Models

- `app/models/calendar_entry.rb` (new) — central model. See §"Model:
  CalendarEntry".
- `app/models/milestone_rule.rb` (new) — declarative rule. See §"Model:
  MilestoneRule".
- `app/models/app_setting.rb` (light edit) — accessors for the new `timezone`
  column. Default `"UTC"`. Validation: must be a valid IANA tz name
  (`ActiveSupport::TimeZone.find_tzinfo(value)` returns truthy).

### Concerns / hooks

- `app/models/concerns/calendar_derivable.rb` (new) — small mixin providing
  `derive_calendar_entry!` and `revoke_calendar_entry!` for Video / Channel /
  Game. Each host model implements two methods: `calendar_entry_attributes` (the
  attribute hash to upsert) and `calendar_entry_source_ref` (the jsonb pointer
  for `source_ref`).
- `app/models/video.rb` (light edit) — `include CalendarDerivable`; define
  `calendar_entry_attributes` and `calendar_entry_source_ref`; add
  `after_save :sync_calendar_entry` callback gated on relevant attribute changes
  (`published_at`, `publish_at`, `privacy_status`, `title`).
- `app/models/channel.rb` (light edit) — same pattern. The `channel_published`
  derivation keys on `channels.created_at` per note 5 ("derived from
  `channel.created_at` for tenant channels"; the word "tenant" is a leftover
  from the pre-ADR-0003 framing — this spec uses the install-scoped semantics).
- `app/models/game.rb` (light edit) — same pattern. The `game_release`
  derivation keys on `games.release_date`. Re-sync overwrites unless
  `manual_date_override = true` (a new boolean column on `games`, see §"Schema"
  — this is the small Phase 14 carryover Note 5 calls out; the architect adds it
  here rather than chasing back into Phase 14).

### Services

- `app/services/calendar/derivation.rb` (new) — orchestrator. Single public
  method `sync!(host)` performs the upsert: lookup by
  `(entry_type, source_ref)`, upsert attributes, preserve
  `metadata.user_overrides` from any existing row, save. Used by the three host
  callbacks above.
- `app/services/calendar/milestone_evaluator.rb` (new — skeleton only in this
  phase) — single public method `evaluate_all!`. Iterates
  `MilestoneRule.where(enabled: true, fired_at: nil)`, reads the metric per
  `(scope_type, scope_id, metric, metric_window)`, compares against `threshold`
  per `direction`, and on crossing writes a `milestone_auto` calendar entry +
  stamps `fired_at`. **The metric read is a stub in this phase** — Phase 13
  (analytics) wires real reads. The skeleton accepts a `metric_reader` injection
  point so the test suite can stub. See §"Services: milestone evaluator".
- `app/services/calendar/notification_dispatch_declaration.rb` (new) — small
  read-only helper Phase 16 will consume. Maps each `calendar_entry` to the list
  of notification kinds + offsets it should fire. NOT a writer; never inserts
  notification rows. Returns hashes per kind. See §"Services: notification
  dispatch declaration".
- `app/services/calendar/occurred_flipper.rb` (new) — daily Sidekiq cron job.
  Iterates
  `CalendarEntry.where(state: :scheduled).where("starts_at <= ?", Time.current)`
  and flips `state` to `:occurred`. See §"Services: occurred flipper".

### Jobs

- `app/jobs/calendar_derivation_job.rb` (new) — Sidekiq wrapper around
  `Calendar::Derivation#sync!` for the cases where the callback flow needs to be
  deferred (e.g., bulk Video reseed during Phase 12 sync). Single argument:
  `(host_class, host_id)`.
- `app/jobs/milestone_evaluator_job.rb` (new) — Sidekiq wrapper around
  `Calendar::MilestoneEvaluator#evaluate_all!`. Triggered by the analytics sync
  cron (Phase 13) AND by a daily fallback cron (this phase) at 02:00 UTC.
- `app/jobs/calendar_occurred_flipper_job.rb` (new) — Sidekiq cron job, runs
  every hour at minute 5. Flips ripe `:scheduled` entries to `:occurred`.
- `config/sidekiq.yml` (light edit) — register the two cron schedules
  (`milestone_evaluator_job` daily at 02:00 UTC; `calendar_occurred_flipper_job`
  hourly at minute 5).

### Routes

This phase ships data-tier only. **No new routes** in §1. Routes land in §2
(`/calendar/month/:year/:month`, `/calendar/schedule`).

### Out of scope (this spec)

- Calendar views (`/calendar/...`) — Phase 15 §2.
- Notification rows + delivery channels + formatter + webhook delivery —
  Phase 16.
- MCP tools (`calendar_*`, `purchase_*`, `milestone_rule_*`) — realignment work
  unit 9.
- CLI parity — realignment work unit 10.
- Recurrence (per Q9) — deferred follow-up.
- iCal export / sync — note 5's "Future hooks (not now)".
- Calendar sharing — single-install multi-user; no multi-user features in v1.
- Email delivery — note 5's explicit non-goal.
- Live IGDB / Steam / GOG / Epic API hits to enrich `game_release` — Phase 14
  owns these; calendar consumes existing `games` columns.

## Schema

### `calendar_entries` table (new)

| #   | Column                 | Type          | Null | Default | Index                  | Notes                                                                                                                                                                          |
| --- | ---------------------- | ------------- | ---- | ------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `id`                   | `uuid`        | NOT  | (pk)    | (pk)                   | UUID primary key per ADR 0003 "UUIDs in URLs and API payloads".                                                                                                                |
| 2   | `entry_type`           | `integer`     | NOT  | —       | btree                  | Rails enum. See §"Enum: entry_type".                                                                                                                                           |
| 3   | `source`               | `integer`     | NOT  | `0`     | btree                  | Rails enum: `manual=0`, `derived=1`, `auto=2`.                                                                                                                                 |
| 4   | `state`                | `integer`     | NOT  | `0`     | btree                  | Rails enum: `scheduled=0`, `occurred=1`, `cancelled=2`, `superseded=3`.                                                                                                        |
| 5   | `title`                | `string`      | NOT  | —       | —                      | Short display name. Length 1..255. Validated.                                                                                                                                  |
| 6   | `description`          | `text`        | NULL | —       | —                      | Free-form. Max 5000 chars (validated).                                                                                                                                         |
| 7   | `starts_at`            | `timestamptz` | NOT  | —       | btree                  | Point-in-time or span start. UTC at rest.                                                                                                                                      |
| 8   | `ends_at`              | `timestamptz` | NULL | —       | btree (where not null) | Span end; NULL for point-in-time entries.                                                                                                                                      |
| 9   | `all_day`              | `boolean`     | NOT  | `false` | —                      | When true, render time portion as suppressed.                                                                                                                                  |
| 10  | `timezone`             | `string`      | NOT  | `"UTC"` | —                      | IANA tz name the entry was authored in. Default lifted from `AppSetting.timezone` at insert.                                                                                   |
| 11  | `metadata`             | `jsonb`       | NOT  | `{}`    | gin                    | Type-specific fields per §"Per-type metadata schemas". Includes `user_overrides` sub-key for derived / auto entries.                                                           |
| 12  | `source_ref`           | `jsonb`       | NULL | —       | gin                    | Pointer back to canonical row(s) for derived / auto entries. NULL for manual entries. Per Q16.                                                                                 |
| 13  | `video_id`             | `uuid`        | NULL | —       | btree (where not null) | FK → `videos.id`. Set for `video_published` / `video_scheduled` derived entries. NULL otherwise. `dependent: :destroy` from Video.                                             |
| 14  | `game_id`              | `uuid`        | NULL | —       | btree (where not null) | FK → `games.id`. Set for `game_release` derived/manual entries. NULL otherwise. `dependent: :destroy` from Game.                                                               |
| 15  | `channel_id`           | `uuid`        | NULL | —       | btree (where not null) | FK → `channels.id`. Set for `channel_published` derived entries. NULL otherwise. `dependent: :destroy` from Channel.                                                           |
| 16  | `project_id`           | `uuid`        | NULL | —       | btree (where not null) | FK → `projects.id`. Optional manual entries can attach to a project (e.g., a project milestone). `dependent: :nullify`.                                                        |
| 17  | `parent_entry_id`      | `uuid`        | NULL | —       | btree (where not null) | FK → `calendar_entries.id`. Set for `purchase_planned` entries pointing at the related `game_release` entry. `dependent: :nullify`.                                            |
| 18  | `milestone_rule_id`    | `uuid`        | NULL | —       | btree (where not null) | FK → `milestone_rules.id`. Set for `milestone_auto` entries. `dependent: :nullify`.                                                                                            |
| 19  | `manual_date_override` | `boolean`     | NOT  | `false` | —                      | For `game_release` entries. When true, IGDB sync may not overwrite `starts_at`. Per note 5.                                                                                    |
| 20  | `release_precision`    | `integer`     | NULL | —       | —                      | Rails enum: `day=0`, `month=1`, `quarter=2`, `year=3`, `tba=4`. NULL for non-`game_release` entries. Per note 5.                                                               |
| 21  | `tba_remind_monthly`   | `boolean`     | NOT  | `false` | —                      | Per-entry monthly TBA reminder flag for `game_release` entries with coarser-than-day precision. Phase 16 consumes. Per note 5.                                                 |
| 22  | `notify_anyway`        | `boolean`     | NOT  | `false` | —                      | Per-entry override for `purchase_planned` suppression rule. When true, the linked `game_release` fires reminders even though a purchase exists. Phase 16 consumes. Per note 5. |
| 23  | `created_by_user_id`   | `uuid`        | NULL | —       | btree (where not null) | FK → `users.id`, `dependent: :nullify`. NULL for derived / auto rows. Per ADR 0003.                                                                                            |
| 24  | `created_at`           | `timestamptz` | NOT  | —       | —                      |                                                                                                                                                                                |
| 25  | `updated_at`           | `timestamptz` | NOT  | —       | —                      |                                                                                                                                                                                |

**Composite indexes:**

- `(entry_type, starts_at)` — for the month-grid range query.
- `(state, starts_at)` — for the schedule view's "upcoming" queries and the
  occurred-flipper job.
- `(entry_type, source_ref) USING gin` is implied by the gin on `source_ref`;
  the implementation agent picks whether to add a partial expression index for
  the four derived `(entry_type, source_ref →> '<id_key>')` upsert paths or rely
  on the GIN. Recommendation: GIN on `source_ref` only; the upsert lookups are
  by typed FK (`video_id` / `game_id` / `channel_id`) which are already indexed.

**Foreign keys:**

- `calendar_entries.video_id → videos.id` (`ON DELETE CASCADE`).
- `calendar_entries.game_id → games.id` (`ON DELETE CASCADE`).
- `calendar_entries.channel_id → channels.id` (`ON DELETE CASCADE`).
- `calendar_entries.project_id → projects.id` (`ON DELETE SET NULL`).
- `calendar_entries.parent_entry_id → calendar_entries.id`
  (`ON DELETE SET NULL`).
- `calendar_entries.milestone_rule_id → milestone_rules.id`
  (`ON DELETE SET NULL`).
- `calendar_entries.created_by_user_id → users.id` (`ON DELETE SET NULL`).

**Check constraints:**

- `ends_at IS NULL OR ends_at >= starts_at` — guards span sanity.

### `milestone_rules` table (new)

| #   | Column               | Type            | Null | Default | Index                  | Notes                                                                                                                                      |
| --- | -------------------- | --------------- | ---- | ------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `id`                 | `uuid`          | NOT  | (pk)    | (pk)                   | UUID primary key.                                                                                                                          |
| 2   | `name`               | `string`        | NOT  | —       | —                      | E.g. "100 subs on main channel". Length 1..255.                                                                                            |
| 3   | `scope_type`         | `integer`       | NOT  | —       | btree                  | Rails enum: `tenant=0` (renamed in code to `install`), `channel=1`, `video=2`. Per note 5.                                                 |
| 4   | `scope_id`           | `uuid`          | NULL | —       | btree (where not null) | NULL for `install` scope. UUID FK semantics — but kept as plain uuid + `scope_type` discriminator, not a polymorphic FK (per Q2).          |
| 5   | `metric`             | `string`        | NOT  | —       | btree                  | E.g. `subscriberCount`, `views`, `likes`, `estimatedMinutesWatched`, `subscribersGained`. Stored as the YouTube Analytics API metric name. |
| 6   | `metric_window`      | `integer`       | NOT  | `0`     | —                      | Rails enum: `lifetime=0`, `seven_day=1`, `twentyeight_day=2`, `ninety_day=3`. Maps to note 5's `lifetime` / `7d` / `28d` / `90d`.          |
| 7   | `threshold`          | `decimal(20,4)` | NOT  | —       | —                      | Threshold value the metric must cross.                                                                                                     |
| 8   | `direction`          | `integer`       | NOT  | `0`     | —                      | Rails enum: `cross_up=0`, `cross_down=1`. Per note 5.                                                                                      |
| 9   | `fired_at`           | `timestamptz`   | NULL | —       | btree                  | Idempotency key. NULL = never fired; non-NULL = already fired and won't re-fire unless cleared.                                            |
| 10  | `enabled`            | `boolean`       | NOT  | `true`  | btree                  |                                                                                                                                            |
| 11  | `created_by_user_id` | `uuid`          | NULL | —       | btree (where not null) | FK → `users.id`, `dependent: :nullify`. Per ADR 0003.                                                                                      |
| 12  | `created_at`         | `timestamptz`   | NOT  | —       | —                      |                                                                                                                                            |
| 13  | `updated_at`         | `timestamptz`   | NOT  | —       | —                      |                                                                                                                                            |

### `app_settings` table — column addition

| #   | Column     | Type     | Null | Default | Notes                                                                                                                     |
| --- | ---------- | -------- | ---- | ------- | ------------------------------------------------------------------------------------------------------------------------- |
| 1   | `timezone` | `string` | NOT  | `"UTC"` | IANA tz name. Used as the install-level default for new calendar entries. Validated as a real IANA tz at the model layer. |

### `games` table — column addition

| #   | Column                 | Type      | Null | Default | Notes                                                                                                                                                                                                                                                                              |
| --- | ---------------------- | --------- | ---- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `manual_date_override` | `boolean` | NOT  | `false` | Per note 5 §"Game release" "A `manual_date_override` boolean on the entry says ...". Lives on `games`, not `calendar_entries`, because it's the canonical Game release-date guard. The `calendar_entries.manual_date_override` mirror (Q19) is denormalized for query convenience. |

The implementation agent verifies via `git grep` that no Phase 14 spec already
adds this column. If Phase 14 has already shipped it, this entry is a no-op;
otherwise it lands here.

## Per-type metadata schemas

Each `entry_type` declares the keys allowed in `metadata`. The model layer
enforces the shape via a JSON schema validator at the model level
(`validates_with CalendarEntryMetadataValidator`). Unknown keys on save are
stripped. Known keys missing on load are returned as `nil` to the caller. The
`user_overrides` sub-key is allowed on every type.

### `channel_published`

Source: derived from `channels.created_at`. No type-specific keys required.
`metadata` shape:

```json
{
  "user_overrides": { "<key>": "<value>" }
}
```

### `video_published`

Source: derived from `videos.published_at` when `privacy_status` is `public` or
`unlisted`. `metadata` shape:

```json
{
  "user_overrides": { "<key>": "<value>" }
}
```

### `video_scheduled`

Source: derived from `videos.publish_at` while `videos.privacy_status = private`
AND `publish_at` is in the future. Per note 5: when the scheduled time passes,
the entry is **superseded** (state flips to `superseded`), and a new
`video_published` entry is written. `metadata` shape: same as `video_published`.

### `game_release`

Source: `manual` (user-typed pre-IGDB) OR `derived` (IGDB-attached). `metadata`
shape (per note 5):

```json
{
  "platforms": ["PS5", "Switch"],
  "release_window": "Q3 2026",
  "igdb_id": 12345,
  "igdb_slug": "celeste",
  "user_overrides": { "<key>": "<value>" }
}
```

`game_id` is a real column (Q2). `release_precision` is a real column (Q19).
`manual_date_override` is a real column (Q19) — read on the attached `games` row
(NOT on `calendar_entries`). The IGDB sync flow (Phase 14) checks
`games.manual_date_override` before overwriting `calendar_entries.starts_at`.

### `purchase_planned`

Source: `manual`. `parent_entry_id` is a real column pointing at the related
`game_release`. `metadata` shape (per note 5):

```json
{
  "purchase_kind": "preorder | reservation | purchased",
  "storefront": "Steam | GOG | Epic | PSN | Nintendo eShop | Xbox | Physical | Other",
  "storefront_name": "GAME.es",
  "storefront_url": "https://...",
  "amount": "59.99",
  "currency": "EUR",
  "ordered_at": "2026-05-09T10:00:00Z",
  "confirmation_ref": "AB123",
  "user_overrides": { "<key>": "<value>" }
}
```

`notify_anyway` is a real column (Q22).

### `milestone_manual`

Source: `manual`. `metadata` shape:

```json
{
  "user_overrides": { "<key>": "<value>" }
}
```

### `milestone_auto`

Source: `auto`. `milestone_rule_id` is a real column. `metadata` includes
`metric_value_at_fire` (the metric value at the moment of crossing) plus
`user_overrides`:

```json
{
  "metric_value_at_fire": 100000,
  "user_overrides": { "<key>": "<value>" }
}
```

`source_ref` mirrors `{milestone_rule_id, metric_value_at_fire}` for audit
symmetry.

### `custom`

Source: `manual`. `metadata` shape:

```json
{
  "tags": ["tag1", "tag2"],
  "user_overrides": { "<key>": "<value>" }
}
```

`tags` is optional, free-form, used by the schedule view's filter UI (§2).

## Enum: `entry_type`

```ruby
enum :entry_type, {
  channel_published: 0,
  video_published: 1,
  video_scheduled: 2,
  game_release: 3,
  purchase_planned: 4,
  milestone_manual: 5,
  milestone_auto: 6,
  custom: 7
}
```

## Model: CalendarEntry

```ruby
class CalendarEntry < ApplicationRecord
  belongs_to :video, optional: true
  belongs_to :game, optional: true
  belongs_to :channel, optional: true
  belongs_to :project, optional: true
  belongs_to :parent_entry,
             class_name: "CalendarEntry",
             optional: true
  belongs_to :milestone_rule, optional: true
  belongs_to :created_by_user,
             class_name: "User",
             optional: true

  has_many :child_entries,
           class_name: "CalendarEntry",
           foreign_key: :parent_entry_id,
           dependent: :nullify

  enum :entry_type, { channel_published: 0, video_published: 1,
                      video_scheduled: 2, game_release: 3,
                      purchase_planned: 4, milestone_manual: 5,
                      milestone_auto: 6, custom: 7 }
  enum :source, { manual: 0, derived: 1, auto: 2 }
  enum :state, { scheduled: 0, occurred: 1, cancelled: 2,
                 superseded: 3 }
  enum :release_precision, { day: 0, month: 1, quarter: 2,
                             year: 3, tba: 4 }, prefix: true

  validates :title, presence: true,
                    length: { in: 1..255 }
  validates :description, length: { maximum: 5000 }
  validates :timezone, presence: true,
                       inclusion: { in: ->(_) { ActiveSupport::TimeZone::MAPPING.values + ActiveSupport::TimeZone::MAPPING.keys } }
  validates_with CalendarEntryMetadataValidator
  validates_with CalendarEntryCrossReferenceValidator
  validate :ends_at_after_starts_at
  validate :derived_entries_have_source_ref
  validate :purchase_planned_has_parent_entry
  validate :milestone_auto_has_rule

  before_validation :stamp_install_timezone, on: :create
  before_save :reject_writes_to_derived_outside_user_overrides

  scope :in_range, ->(start_at, end_at) {
    where("starts_at < ? AND (ends_at IS NULL OR ends_at >= ?)",
          end_at, start_at)
  }
  scope :upcoming_releases, -> {
    where(entry_type: :game_release)
      .where("starts_at >= ?", Time.current)
      .order(:starts_at)
  }
  scope :upcoming_releases_without_purchase, -> {
    upcoming_releases
      .left_joins(:child_entries)
      .where(child_entries: { id: nil })
  }
  scope :recent_milestones, ->(window: 30.days) {
    where(entry_type: %i[milestone_manual milestone_auto])
      .where(starts_at: window.ago..Time.current)
  }

  def derived_or_auto?
    derived? || auto?
  end

  def read_only?
    derived_or_auto?
  end

  private

  def ends_at_after_starts_at
    return if ends_at.nil?
    return if ends_at >= starts_at
    errors.add(:ends_at, "must be after or equal to starts_at")
  end

  def derived_entries_have_source_ref
    return unless derived_or_auto?
    return if source_ref.present?
    errors.add(:source_ref,
               "is required for derived / auto entries")
  end

  def purchase_planned_has_parent_entry
    return unless purchase_planned?
    return if parent_entry_id.present?
    errors.add(:parent_entry_id,
               "is required for purchase_planned entries")
  end

  def milestone_auto_has_rule
    return unless milestone_auto?
    return if milestone_rule_id.present?
    errors.add(:milestone_rule_id,
               "is required for milestone_auto entries")
  end

  def stamp_install_timezone
    return if timezone.present?
    self.timezone = AppSetting.first&.timezone || "UTC"
  end

  def reject_writes_to_derived_outside_user_overrides
    return unless derived_or_auto?
    return if new_record?
    forbidden = changes.keys - %w[updated_at metadata]
    return if forbidden.empty?
    return if metadata_changes_only_user_overrides?
    errors.add(:base,
               "derived / auto entries are read-only outside metadata.user_overrides")
    throw(:abort)
  end

  def metadata_changes_only_user_overrides?
    return true unless metadata_changed?
    before, after = changes["metadata"]
    before_without_overrides = (before || {}).except("user_overrides")
    after_without_overrides = (after || {}).except("user_overrides")
    before_without_overrides == after_without_overrides
  end
end
```

The implementation agent extracts `CalendarEntryMetadataValidator` and
`CalendarEntryCrossReferenceValidator` into
`app/validators/calendar_entry_metadata_validator.rb` and
`app/validators/calendar_entry_cross_reference_validator.rb` respectively. The
cross-reference validator enforces:

- `channel_published` requires `channel_id`, forbids `video_id` / `game_id` /
  `parent_entry_id` / `milestone_rule_id`.
- `video_published` / `video_scheduled` require `video_id`, forbid `game_id` /
  `channel_id` / `parent_entry_id` / `milestone_rule_id`.
- `game_release` allows `game_id` (nullable per pre-IGDB case), forbids
  `video_id` / `channel_id` / `parent_entry_id` / `milestone_rule_id`.
- `purchase_planned` requires `parent_entry_id`, forbids `video_id` /
  `channel_id` / `milestone_rule_id`. May have `game_id` (denormalized pointer
  to the game the purchase covers; convenience for queries).
- `milestone_manual` forbids all FKs except optional `project_id`.
- `milestone_auto` requires `milestone_rule_id`, forbids `video_id` /
  `channel_id` / `game_id` / `parent_entry_id`.
- `custom` forbids all FKs except optional `project_id`.

## Model: MilestoneRule

```ruby
class MilestoneRule < ApplicationRecord
  belongs_to :created_by_user,
             class_name: "User",
             optional: true

  has_many :calendar_entries,
           dependent: :nullify

  enum :scope_type, { install: 0, channel: 1, video: 2 }
  enum :metric_window, { lifetime: 0, seven_day: 1,
                         twentyeight_day: 2, ninety_day: 3 }
  enum :direction, { cross_up: 0, cross_down: 1 }

  validates :name, presence: true,
                   length: { in: 1..255 }
  validates :metric, presence: true,
                     length: { maximum: 255 }
  validates :threshold,
            numericality: true
  validate :scope_id_presence_matches_scope_type
  validate :scope_id_references_valid_target

  def fire!(metric_value:, fired_at: Time.current)
    raise "already fired" if self.fired_at.present?
    transaction do
      update!(fired_at: fired_at)
      CalendarEntry.create!(
        entry_type: :milestone_auto,
        source: :auto,
        state: :occurred,
        title: name,
        starts_at: fired_at,
        all_day: false,
        timezone: AppSetting.first&.timezone || "UTC",
        milestone_rule_id: id,
        source_ref: { milestone_rule_id: id,
                      metric_value_at_fire: metric_value },
        metadata: { metric_value_at_fire: metric_value,
                    user_overrides: {} }
      )
    end
  end

  def re_arm!
    update!(fired_at: nil)
  end

  private

  def scope_id_presence_matches_scope_type
    if install? && scope_id.present?
      errors.add(:scope_id, "must be nil for install scope")
    elsif !install? && scope_id.blank?
      errors.add(:scope_id, "is required for #{scope_type} scope")
    end
  end

  def scope_id_references_valid_target
    return if install? || scope_id.blank?
    klass = channel? ? Channel : Video
    return if klass.exists?(id: scope_id)
    errors.add(:scope_id,
               "does not reference an existing #{scope_type}")
  end
end
```

## Services: derivation

```ruby
module Calendar
  class Derivation
    # Upsert a derived calendar entry for a host row (Video / Channel /
    # Game). Idempotent — re-syncs overwrite by (entry_type, source_ref)
    # but preserve metadata.user_overrides.
    def self.sync!(host)
      attrs = host.calendar_entry_attributes
      return revoke!(host) if attrs.nil?
      ref = host.calendar_entry_source_ref
      type = host.calendar_entry_type

      existing = CalendarEntry
        .where(entry_type: type)
        .where("source_ref @> ?::jsonb", ref.to_json)
        .first

      if existing
        preserved = (existing.metadata || {})["user_overrides"] || {}
        existing.assign_attributes(attrs)
        existing.metadata = (attrs[:metadata] || {})
          .merge("user_overrides" => preserved)
        existing.save!
        existing
      else
        CalendarEntry.create!(
          attrs.merge(
            entry_type: type,
            source: :derived,
            source_ref: ref
          )
        )
      end
    end

    # Mark the derived entry superseded (NOT deleted) when the host
    # condition no longer applies (e.g., a video flips back to private
    # after being scheduled).
    def self.revoke!(host)
      type = host.calendar_entry_type
      ref = host.calendar_entry_source_ref
      CalendarEntry
        .where(entry_type: type)
        .where("source_ref @> ?::jsonb", ref.to_json)
        .update_all(state: CalendarEntry.states[:superseded],
                    updated_at: Time.current)
    end
  end
end
```

The `CalendarDerivable` mixin (consumed by Video / Channel / Game) implements
`calendar_entry_type`, `calendar_entry_attributes` (returning `nil` to signal
"this host should NOT have a derived entry right now"), and
`calendar_entry_source_ref`. Per host:

- **Channel.** Type `:channel_published`. Attrs:
  `title: "channel joined: #{self.title || self.url}"`, `starts_at: created_at`,
  `all_day: true`. Ref: `{channel_id: id}`. Always derives once per channel.
- **Video.** Type depends on state:
  - `privacy_status` is `:public` or `:unlisted` AND `published_at` is not nil →
    `:video_published`, attrs `title: "video published: #{title}"`,
    `starts_at: published_at`, `all_day: false`.
  - `privacy_status` is `:private` AND `publish_at` is not nil AND
    `publish_at > Time.current` → `:video_scheduled`, attrs
    `title: "scheduled: #{title}"`, `starts_at: publish_at`, `all_day: false`.
  - Neither condition → return nil (revokes any prior derived entry).
  - Video has TWO possible source_ref keys (`{video_id: id, kind: "published"}`
    and `{video_id: id, kind: "scheduled"}`) so the transition published →
    scheduled doesn't collide on upsert.
- **Game.** Type `:game_release`. Attrs: `title: "released: #{title}"`,
  `starts_at: release_date.in_time_zone(install_tz).beginning_of_day`,
  `all_day: true`, `release_precision: ...` (mapped from Phase 14's IGDB
  `release_precision` field). Ref: `{game_id: id}`. Returns nil if
  `release_date` is nil. **Respects `manual_date_override`**: if true, the
  derive call assigns every attr EXCEPT `starts_at` / `release_precision`.

## Services: notification dispatch declaration

This is read-only metadata Phase 16 will consume. Single source of truth for
"calendar entry → notification kinds + offsets." Lives in this phase so the data
tier carries the contract.

```ruby
module Calendar
  module NotificationDispatchDeclaration
    # Returns an array of { kind:, fires_at:, severity: } hashes for a
    # given CalendarEntry. Phase 16's NotificationScheduler reads this
    # to know which Notification rows to insert at which times.
    #
    # NO insert happens here. NO delivery happens here. This is metadata
    # only; Phase 16 owns the writer.
    def self.declarations_for(entry)
      case entry.entry_type
      when "game_release"
        game_release_declarations(entry)
      when "video_scheduled"
        video_scheduled_declarations(entry)
      when "milestone_auto"
        [{ kind: "milestone_reached",
           fires_at: entry.starts_at,
           severity: "success" }]
      else
        []
      end
    end

    def self.game_release_declarations(entry)
      return [] if entry.release_precision.present? &&
                   entry.release_precision != "day"
      offsets = [
        [30.days, "info",  false],  # T-30 (default off)
        [7.days,  "info",  true],   # T-7  (default on)
        [1.day,   "warn",  true],   # T-1  (default on)
        [0.days,  "success", true]  # T-0  (default on)
      ]
      suppress_pre_release = entry.child_entries
        .where(entry_type: :purchase_planned)
        .where(notify_anyway: false)
        .exists?
      offsets.flat_map do |offset, severity, default_on|
        next [] unless default_on
        next [] if suppress_pre_release && offset > 0.days
        [{ kind: "game_release_upcoming",
           fires_at: entry.starts_at - offset,
           severity: severity }]
      end + [{ kind: "game_release_today",
               fires_at: entry.starts_at,
               severity: "success" }]
    end

    def self.video_scheduled_declarations(entry)
      [{ kind: "video_scheduled_publishing_soon",
         fires_at: entry.starts_at - 1.hour,
         severity: "info" }]
    end
  end
end
```

The constant offsets list (`[30.days, "info", false]`, etc.) is a default; Phase
16's `AppSetting` extensions surface user-tunable toggles per offset. This phase
ships the defaults inline; Phase 16 moves them to settings.

## Services: milestone evaluator

```ruby
module Calendar
  class MilestoneEvaluator
    def initialize(metric_reader: DefaultMetricReader.new)
      @metric_reader = metric_reader
    end

    def evaluate_all!
      MilestoneRule.where(enabled: true, fired_at: nil).find_each do |rule|
        evaluate(rule)
      end
    end

    def evaluate(rule)
      value = @metric_reader.read(
        scope_type: rule.scope_type,
        scope_id: rule.scope_id,
        metric: rule.metric,
        window: rule.metric_window
      )
      return if value.nil?
      crossed = case rule.direction
                when "cross_up"   then value >= rule.threshold
                when "cross_down" then value <= rule.threshold
                end
      return unless crossed
      rule.fire!(metric_value: value)
    end

    # Phase 13 (analytics) replaces this stub. The injection point lets
    # the test suite use a hash-backed reader.
    class DefaultMetricReader
      def read(scope_type:, scope_id:, metric:, window:)
        # Phase 13 wires this against
        # ChannelWindowSummary / VideoWindowSummary / Channel snapshots.
        # Phase 15 ships the skeleton returning nil.
        nil
      end
    end
  end
end
```

## Services: occurred flipper

```ruby
module Calendar
  class OccurredFlipper
    def self.flip_ripe!
      CalendarEntry
        .where(state: :scheduled)
        .where("starts_at <= ?", Time.current)
        .update_all(state: CalendarEntry.states[:occurred],
                    updated_at: Time.current)
    end
  end
end
```

## Files touched (test surfaces)

### Test sweep

The implementation agent owns the full sweep. Each spec name below MUST end up
in the repo on green.

- `spec/factories/calendar_entries.rb` (new) — factory + traits per entry_type.
  Each trait provides the minimum valid metadata + FK shape.
- `spec/factories/milestone_rules.rb` (new) — factory + traits for install /
  channel / video scope.
- `spec/models/calendar_entry_spec.rb` (new) — exhaustive.
- `spec/models/milestone_rule_spec.rb` (new) — exhaustive.
- `spec/validators/calendar_entry_metadata_validator_spec.rb` (new).
- `spec/validators/calendar_entry_cross_reference_validator_spec.rb` (new).
- `spec/services/calendar/derivation_spec.rb` (new).
- `spec/services/calendar/notification_dispatch_declaration_spec.rb` (new).
- `spec/services/calendar/milestone_evaluator_spec.rb` (new).
- `spec/services/calendar/occurred_flipper_spec.rb` (new).
- `spec/jobs/calendar_derivation_job_spec.rb` (new).
- `spec/jobs/milestone_evaluator_job_spec.rb` (new).
- `spec/jobs/calendar_occurred_flipper_job_spec.rb` (new).
- `spec/models/video_calendar_derivation_spec.rb` (new) — Video host callback
  flow.
- `spec/models/channel_calendar_derivation_spec.rb` (new) — Channel host
  callback flow.
- `spec/models/game_calendar_derivation_spec.rb` (new) — Game host callback
  flow.

### Required test cases (exhaustive — implementation agent enumerates each)

#### `spec/models/calendar_entry_spec.rb`

Validations:

- title presence + length 1..255 (boundary at 0, 1, 255, 256).
- description nil OK; length max 5000 (boundary).
- timezone validates against IANA tz; rejects "Mars/Olympus".
- ends_at NULL OK; ends_at == starts_at OK; ends_at < starts_at fails.
- `derived` source requires `source_ref` non-empty; `auto` source same.
- `purchase_planned` requires `parent_entry_id`.
- `milestone_auto` requires `milestone_rule_id`.

Cross-reference validator (one happy + one sad per entry_type):

- `channel_published` happy with `channel_id` only.
- `channel_published` sad with `video_id` set.
- `video_published` happy with `video_id` only.
- `video_published` sad with `game_id` set.
- `video_scheduled` happy + sad mirror.
- `game_release` happy with `game_id` set.
- `game_release` happy with `game_id` nil (pre-IGDB).
- `game_release` sad with `parent_entry_id` set.
- `purchase_planned` happy with `parent_entry_id` + optional `game_id`.
- `purchase_planned` sad with `parent_entry_id` nil.
- `milestone_manual` happy with no FKs except optional `project_id`.
- `milestone_manual` sad with `video_id` set.
- `milestone_auto` happy with `milestone_rule_id`.
- `milestone_auto` sad with `milestone_rule_id` nil.
- `custom` happy with no FKs.
- `custom` sad with `video_id` set.

Read-only enforcement:

- A `derived` row with `state: scheduled` cannot have its `title` rewritten by a
  normal `update!(...)` call.
- A `derived` row CAN have `metadata.user_overrides` rewritten.
- A `derived` row CAN have other `metadata` keys rewritten ONLY by the
  `Calendar::Derivation` service (which reaches through and bypasses the
  callback by re-using attribute assignment in a controlled way — the test
  asserts that direct user-facing controllers get blocked).
- A `manual` row CAN have any field rewritten freely.

Scopes:

- `in_range(a, b)` returns entries whose `[starts_at, ends_at)` overlap
  `[a, b)`. Boundary tests.
- `upcoming_releases` returns only `game_release` entries with
  `starts_at >= now`, sorted ascending.
- `upcoming_releases_without_purchase` excludes any release that has a child
  `purchase_planned`.
- `recent_milestones(window: 30.days)` returns both manual and auto milestones
  in the last 30 days.

Enums:

- All four enum families round-trip via the public API (string ↔ integer).

Time zones / DST:

- An entry authored in `"Europe/Madrid"` on the day DST flips forward is stored
  as the right UTC instant; `starts_at.in_time_zone("Europe/Madrid")`
  round-trips to the original local time.
- An entry authored on a leap-year Feb 29 is stored without truncation; query
  `in_range(Feb 1..Mar 1)` returns it.
- A year-boundary entry (Dec 31 23:30 → Jan 1 00:30 in the install tz) is stored
  as the right UTC instant.

`stamp_install_timezone`:

- New entry without explicit `timezone` lifts the install-level
  `AppSetting.timezone`.
- New entry with explicit `timezone` keeps the explicit value.
- AppSetting absent → falls back to `"UTC"`.

#### `spec/models/milestone_rule_spec.rb`

- name + threshold + metric presence.
- `scope_type=install` rejects `scope_id` non-nil.
- `scope_type=channel` requires `scope_id` AND requires the referenced channel
  exists.
- `scope_type=video` requires `scope_id` AND requires the referenced video
  exists.
- `fire!(metric_value:)` writes a `milestone_auto` calendar entry, sets
  `fired_at`, raises on second call.
- `fire!` rolls back both writes if the calendar_entry insert fails.
- `re_arm!` clears `fired_at`; rule fires again on next evaluation.
- `enabled=false` skips evaluation; flipping to true after fire does NOT re-fire
  (per note 5: "Disabling a rule (enabled=false) without clearing fired_at means
  it won't re-fire if later re-enabled").

#### `spec/services/calendar/derivation_spec.rb`

- First `sync!` of a Video that's `public` writes a new `video_published` entry.
- Second `sync!` with the same Video state is idempotent (no duplicate).
- A `sync!` after the title changes overwrites `title` on the existing entry.
- A `sync!` preserves `metadata.user_overrides` set on the prior row.
- A `sync!` of a Video that's `private` and has `publish_at` in the future
  writes `video_scheduled`.
- A subsequent `sync!` after the video flips to `public` writes
  `video_published` AND supersedes the prior `video_scheduled` (per note 5
  §"Channel / video publish entries: when the scheduled time passes, the entry
  is **superseded** (not deleted)").
- A `sync!` of a Channel writes `channel_published` keyed on `created_at`.
- A `sync!` of a Game with `release_date=nil` does nothing (revoke is no-op for
  absent prior entry).
- A `sync!` of a Game with `release_date` set writes `game_release`.
- A `sync!` of a Game with `manual_date_override=true` and existing entry
  preserves the existing `starts_at` and `release_precision` while overwriting
  `title` / `metadata.platforms`.

#### `spec/services/calendar/notification_dispatch_declaration_spec.rb`

- `game_release` with `release_precision='day'` and no purchase → T-7, T-1, T-0
  declarations + game_release_today at T-0.
- `game_release` with `release_precision='day'` and a child `purchase_planned`
  (notify_anyway=false) → only T-0 + game_release_today.
- `game_release` with `release_precision='day'` and a child `purchase_planned`
  (notify_anyway=true) → all four declarations.
- `game_release` with `release_precision='quarter'` → no declarations (per note
  5).
- `video_scheduled` → one declaration at starts_at - 1h.
- `milestone_auto` → one declaration at starts_at, severity success.
- All other entry types → empty array.

#### `spec/services/calendar/milestone_evaluator_spec.rb`

- A rule with `direction=cross_up`, `threshold=100`, metric reader returns 50 →
  no fire.
- Same rule, reader returns 100 → fire (boundary equal).
- Same rule, reader returns 101 → fire.
- A rule with `direction=cross_down`, `threshold=10`, reader returns 20 → no
  fire.
- Same rule, reader returns 5 → fire.
- A rule with `enabled=false` → never fires regardless of metric.
- A rule with `fired_at` already set → never fires regardless of metric.
- `evaluate_all!` iterates every enabled, never-fired rule.
- An exception inside `fire!` is rescued per-rule (one bad rule does NOT block
  the others).

#### `spec/services/calendar/occurred_flipper_spec.rb`

- Entry with `state=scheduled` AND `starts_at` in the past → flipped to
  `occurred`.
- Entry with `state=scheduled` AND `starts_at` in the future → not touched.
- Entry with `state=cancelled` → not touched even if past.
- Entry with `state=superseded` → not touched.

#### `spec/models/video_calendar_derivation_spec.rb`

- Saving a video that flips `private → public` triggers
  `Calendar::Derivation#sync!` and writes a `video_published` entry.
- Saving a video that sets `publish_at` while `private` triggers sync! and
  writes a `video_scheduled` entry.
- Saving a video that flips `public → private` triggers sync! and supersedes the
  prior `video_published` entry.
- Saving a video with no relevant attribute change does NOT trigger sync!
  (callback gating works).
- `Video.destroy` cascades to the calendar entry (FK on_delete: cascade).

#### `spec/models/channel_calendar_derivation_spec.rb`

- Creating a channel writes a `channel_published` entry keyed on `created_at`.
- Updating an irrelevant attribute does NOT re-derive.
- Destroying a channel cascades to the calendar entry.

#### `spec/models/game_calendar_derivation_spec.rb`

- Setting `games.release_date` for the first time writes a `game_release` entry.
- Setting `games.release_date=nil` after a prior derive supersedes the entry.
- Updating `games.title` re-derives, overwriting the entry's title.
- Updating `games.release_date` while `manual_date_override=true` preserves the
  entry's `starts_at`.
- Destroying a game cascades to the calendar entry.

#### `spec/factories/calendar_entries.rb` traits

The implementation agent ships these traits (one per entry_type) so the rest of
the test suite can use them ergonomically:

- `:channel_published` (assigns `channel`, `source_ref`).
- `:video_published` (assigns `video`, `source_ref`).
- `:video_scheduled` (assigns `video`, `source_ref`,
  `starts_at: 2.days.from_now`).
- `:game_release` (assigns `game`, `release_precision: :day`).
- `:purchase_planned` (assigns `parent_entry`, `metadata` storefront hash).
- `:milestone_manual`.
- `:milestone_auto` (assigns `milestone_rule`, `metadata.metric_value_at_fire`).
- `:custom`.

#### `spec/jobs/*`

- `CalendarDerivationJob` — calls `Calendar::Derivation#sync!` with the right
  host class + id; idempotent.
- `MilestoneEvaluatorJob` — invokes
  `Calendar::MilestoneEvaluator#evaluate_all!`.
- `CalendarOccurredFlipperJob` — invokes `Calendar::OccurredFlipper#flip_ripe!`.

#### Edge cases (exhaustive)

- **Leap year.** Feb 29 entry round-trips through serialization.
- **DST forward.** Entry authored at 02:30 local on the spring-forward day
  stores the correct UTC instant; display converts back without ambiguity (the
  canonical interpretation: Rails treats 02:30 as the later, post-jump 03:30
  local — assert that).
- **DST backward.** Entry authored at 02:30 local on the fall-back day stores
  the first occurrence (the pre-shift instant) — assert that Rails' default
  interpretation lands on the post-shift moment, then document the limitation in
  a comment on the migration.
- **Year boundary.** Entry on Dec 31 23:30 in Europe/Madrid →
  `in_range(Jan 1 00:00..Jan 2 00:00)` (UTC) returns it.
- **Idempotent re-sync.** Calling `Calendar::Derivation#sync!(video)` twice in a
  row on an unchanged Video produces zero diffs.
- **Cascade on host delete.** Deleting a Video / Channel / Game cascades to the
  linked calendar_entry.
- **Cascade on parent delete (purchase_planned).** Deleting a `game_release`
  does NOT delete its child `purchase_planned` entries — `dependent: :nullify`
  per Q11.

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Schema

- [ ] `db/schema.rb` shows a `calendar_entries` table with every column listed
      in §"Schema: calendar_entries".
- [ ] `db/schema.rb` shows a `milestone_rules` table with every column listed in
      §"Schema: milestone_rules".
- [ ] `db/schema.rb` shows a `timezone` column on `app_settings`.
- [ ] `db/schema.rb` shows a `manual_date_override` boolean on `games` (if Phase
      14 hasn't already added it).
- [ ] All foreign keys listed in §"Schema: calendar_entries" land with the
      declared `ON DELETE` semantics.
- [ ] All composite indexes land.
- [ ] The migration's `up` runs cleanly on a freshly-loaded schema.

### Models / validations

- [ ] `CalendarEntry` defines four enums with the listed integer mappings.
- [ ] `MilestoneRule` defines three enums with the listed integer mappings.
- [ ] Every validator listed in §"Model: CalendarEntry" rejects the sad path AND
      accepts the happy path.
- [ ] Cross-reference validator rejects mismatched FK + entry_type combinations
      per the table above.
- [ ] Read-only enforcement blocks writes to derived entries outside
      `metadata.user_overrides`.
- [ ] `MilestoneRule#fire!` is idempotent (second call raises).
- [ ] `MilestoneRule#fire!` rolls back both writes on failure.

### Services

- [ ] `Calendar::Derivation#sync!` upserts by `(entry_type,     source_ref)`.
- [ ] `Calendar::Derivation#sync!` preserves `metadata.user_overrides` on
      overwrite.
- [ ] `Calendar::Derivation#revoke!` flips state to `superseded`, does NOT
      delete.
- [ ] `Calendar::NotificationDispatchDeclaration#declarations_for` returns the
      declarations listed in §"Services: notification dispatch declaration" for
      every entry_type.
- [ ] `Calendar::MilestoneEvaluator#evaluate_all!` fires only enabled,
      never-fired rules whose metric crosses the threshold.
- [ ] `Calendar::OccurredFlipper#flip_ripe!` flips only ripe, `:scheduled`
      entries.

### Jobs

- [ ] `CalendarDerivationJob` enqueues and runs cleanly.
- [ ] `MilestoneEvaluatorJob` is registered as a Sidekiq cron at `02:00 UTC`
      daily.
- [ ] `CalendarOccurredFlipperJob` is registered as a Sidekiq cron at minute 5
      of every hour.

### Tests

- [ ] `bundle exec rspec` passes.
- [ ] Every spec file listed in §"Test sweep" exists.
- [ ] Test count delta logged in `docs/plans/beta/15-calendar/log.md`.

## Manual playbook (post-implementation)

1. **Pull the latest schema.** Run `bin/rails db:migrate`. Confirm
   `db/schema.rb` regenerates with the new tables and columns. Run
   `bin/rails db:seed` to verify the seed flow doesn't break (the seed does NOT
   seed calendar entries — derived entries appear from existing Video / Channel
   / Game rows on first save).
2. **Verify auto-derive from Channel.** Open a Rails console and run
   `Channel.first.touch`. Confirm a `channel_published` entry exists:
   `CalendarEntry.where(entry_type: :channel_published).count` should be ≥ 1.
3. **Verify auto-derive from Video.** Find a video with `privacy_status=public`
   and `published_at` set; touch it. Confirm a `video_published` entry:
   `Video.first.calendar_entries` (via the FK) returns the row.
4. **Verify auto-derive from Game.** Set
   `Game.first.update!(release_date: Date.current + 30.days)`. Confirm a
   `game_release` entry exists at the right `starts_at`.
5. **Verify supersede on Video flip.** Flip a video from `public` to `private`.
   Confirm the prior `video_published` entry's `state` is now `superseded`, NOT
   deleted.
6. **Verify manual_date_override.** Set
   `Game.first.update!(manual_date_override: true)`. Update
   `Game.first.update!(release_date: Date.current + 60.days)`. Confirm the
   calendar entry's `starts_at` did NOT shift (per the override semantic — the
   IGDB sync flow respects it; manual updates of `release_date` do shift it ONLY
   if the user reaches through the UI directly — see Open question #2).
7. **Verify milestone_rule fire.** Create a rule:
   `MilestoneRule.create!(name: "100 subs", scope_type: :install, metric: "subscriberCount", metric_window: :lifetime, threshold: 100, direction: :cross_up)`.
   Inject a metric reader stub returning 150. Run
   `Calendar::MilestoneEvaluator.new(metric_reader: stub) .evaluate_all!`.
   Confirm a `milestone_auto` entry exists + `rule.fired_at` is non-nil.
8. **Verify idempotent re-fire.** Run `evaluate_all!` again. Confirm the rule is
   skipped (`fired_at` already set).
9. **Verify occurred flipper.** Backdate an entry's `starts_at` to 1 hour ago.
   Run `Calendar::OccurredFlipper.flip_ripe!`. Confirm `state` flipped to
   `occurred`.
10. **Verify cascade.** Delete a Video. Confirm its derived calendar entries are
    gone.
11. **Run RSpec green; rubocop clean.** `bundle exec rspec` and
    `bundle exec rubocop` both clean.

## Cross-stack scope

| Surface           | Status                                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Data tier only; views land in §2.                                                            |
| MCP rack app      | **Skipped.** Realignment work unit 9. The calendar MCP tools land alongside Phase 16's notification tools. |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10.                                                                     |
| Astro / website   | **Skipped.** N/A.                                                                                          |

## Copy questions to escalate (master agent asks user before dispatch)

The architect calls these out; the user picks the wording. Do NOT pick copy in
the spec.

1. **Default title text for derived entries.** The architect's drafts above use
   English imperatives:
   - `channel_published`: `"channel joined: <title or url>"`
   - `video_published`: `"video published: <title>"`
   - `video_scheduled`: `"scheduled: <title>"`
   - `game_release`: `"released: <title>"` These titles are user-visible on the
     calendar grid. User picks the final wording; lowercase per
     `docs/design.md`.

2. **`milestone_auto` title shape.** The current draft uses `MilestoneRule.name`
   verbatim ("100 subs on main channel"). User confirms: keep verbatim, prepend
   "milestone: ", or other.

3. **`purchase_planned` title default.** Architect proposes
   `"<purchase_kind>: <linked game title> @ <storefront>"` — e.g.,
   `"preorder: Celeste @ Steam"`. User confirms.

4. **State labels.** `scheduled` / `occurred` / `cancelled` / `superseded` are
   internal enum strings. The schedule view (§2) surfaces them as user-facing
   labels. User picks per-state copy; architect's lean: keep the enum strings as
   labels, lowercase monospace.

5. **`release_precision` labels.** The five values (`day`, `month`, `quarter`,
   `year`, `tba`) surface in the schedule view. User picks display labels;
   architect's lean: keep as-is.

## Open questions (architect cannot decide; master agent surfaces to user)

1. **Recurrence — defer or include?** Per Q9, the architect drops `recurring` /
   `recurrence_rule` from the schema and treats recurring publishing-cadence
   concepts as a separate `publishing_schedule` model in a follow-up. The brief
   mentions recurrence ("Video published — every Tuesday at 09:00"). User
   confirms defer or asks for inclusion. If included, architect's lean: RRULE
   iCalendar-style strings (RFC 5545) stored in a single `recurrence_rule` text
   column on `calendar_entries` — the `ice_cube` gem expands them at read time.
   Adds significant surface area.

2. **Manual `Game.release_date` updates and the override.** Q11 states
   `manual_date_override` guards against IGDB sync overwrites. Open: when the
   user manually changes `Game.release_date` via the web UI, should the calendar
   entry's `starts_at` shift even when `manual_date_override=true`? Architect's
   lean: **yes, shift**. Manual UI edits ARE the user setting the date; the
   override is specifically about IGDB re-sync.

3. **Multi-day `game_release` for "launch week".** Note 5 doesn't address
   multi-day spans for releases. Architect's lean: keep `ends_at` open for any
   entry type but never auto-derive a multi-day span (Phase 14 derive uses
   point-in-time `release_date` only). User can manually edit a derived entry's
   `metadata.user_overrides` to include a multi-day note, OR create a separate
   `custom` entry.

4. **`AppSetting.timezone` default.** Architect lifts UTC as default. The user
   is the operator; they may want their local tz seeded. Open: should the seed
   (Phase 8 `db/seeds.rb`) read `Rails.application.credentials.owner.timezone`
   and stamp `AppSetting.timezone` from it? Architect's lean: yes, but as a
   follow-up — Phase 15 ships UTC default, the user updates via `/settings`
   (existing surface) post-deploy. If the user wants one-line setup instead, the
   seed gains a tz read.

5. **`MilestoneRule.scope_type` enum naming.** Note 5 calls the install-wide
   scope `tenant`. ADR 0003 dropped the term `tenant`. The architect renames to
   `install` in the enum and the schema. User confirms or picks `app` / `global`
   / other.

6. **`metric_window` precision.** Architect picks `lifetime`, `seven_day`,
   `twentyeight_day`, `ninety_day` per note 5. User picks final names (note 5
   has them as `7d` / `28d` / `90d` strings; the Rails enum can mirror those if
   user prefers).

7. **`Calendar::Derivation#sync!` re-entrancy with bulk Video updates.** Phase
   12's bulk sync of videos (Sidekiq jobs running in parallel) may race on the
   upsert. The architect's draft uses a single `where(...).first` lookup +
   `create!` or `assign_attributes + save!`. If two jobs race, one will hit a
   uniqueness violation if a unique index exists on `(entry_type, source_ref)`.
   Architect's lean: **add a partial unique expression index on
   `(entry_type, source_ref->>'video_id')` for `entry_type IN (1,2)` and
   `(entry_type, source_ref->>'channel_id')` for `entry_type=0` and
   `(entry_type, source_ref->>'game_id')` for `entry_type=3`** — three small
   partial indexes that catch the race. The Derivation service rescues the
   uniqueness violation and retries the lookup once.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. Default title text for derived entries (verbatim per architect's drafts):
   - `channel_published`: `"channel joined: <title or url>"`
   - `video_published`: `"video published: <title>"`
   - `video_scheduled`: `"scheduled: <title>"`
   - `game_release`: `"released: <title>"`
2. `milestone_auto` title — keep `MilestoneRule.name` verbatim (no
   `"milestone:"` prefix).
3. `purchase_planned` title —
   `<purchase_kind>: <linked game title> @ <storefront>` (e.g.,
   `preorder: Celeste @ Steam`).
4. State labels — keep enum strings as labels: `scheduled` / `occurred` /
   `cancelled` / `superseded`. Lowercase monospace per design system.
5. `release_precision` labels — keep as-is: `day` / `month` / `quarter` / `year`
   / `tba`.

### Open-question decisions

1. **Recurrence** — defer entirely. Drop `recurring` and `recurrence_rule` from
   the Phase 15 schema. Recurring publishing-cadence concepts get a separate
   `publishing_schedule` model in a follow-up phase.
2. **Manual `Game.release_date` UI updates** — shift `calendar_entry.starts_at`
   even when `manual_date_override=true`. The override is specifically about
   IGDB re-sync; manual UI edits ARE the user setting the date.
3. **Multi-day `game_release`** — keep `ends_at` open for any entry type but
   never auto-derive a multi-day span. Phase 14 derivation uses point-in-time
   `release_date` only. User can manually edit `metadata.user_overrides` to add
   a multi-day note OR create a separate `custom` entry.
4. **`AppSetting.timezone` default** — UTC default. User updates via `/settings`
   post-deploy. Phase 15 ships UTC; the seed-from-credentials enhancement is a
   follow-up.
5. **`MilestoneRule.scope_type` enum naming** — rename `tenant` → `install`
   (Note 5's pre-ADR-0003 vocabulary cleanup).
6. **`metric_window` precision** — use string-form names matching Phase 13:
   `7d`, `28d`, `90d`, `lifetime`. (Override architect's `seven_day` proposal —
   Phase 13 already uses the short-form `7d` enum, and consistency across the
   codebase wins.)
7. **`Calendar::Derivation#sync!` race-condition handling** — add three partial
   unique expression indexes per the architect's lean:
   `(entry_type, source_ref->>'video_id')` for `entry_type IN (1,2)`,
   `(entry_type, source_ref->>'channel_id')` for `entry_type=0`,
   `(entry_type, source_ref->>'game_id')` for `entry_type=3`. The Derivation
   service rescues uniqueness violations and retries the lookup once.

## Non-goals (explicit)

- Calendar views — Phase 15 §2.
- Notifications — Phase 16.
- MCP tools — work unit 9.
- CLI parity — work unit 10.
- Recurrence — deferred.
- iCal export — deferred.
- Calendar sharing — single-install multi-user; no sharing surface.
- Email delivery — note 5's explicit non-goal.
- Live IGDB / Steam / GOG / Epic API hits in this phase.

## Reviewer checkpoints (post-implementation)

The reviewer agent runs:

1. `bundle exec rspec` — green.
2. `bundle exec rubocop` — clean.
3. `bundle exec brakeman -q` — clean.
4. Manual playbook §1-§11.
5. Spec file count delta logged in `docs/plans/beta/15-calendar/log.md`.
6. `git grep 'tenant\|tenant_id\|Current\.tenant'` returns ZERO matches in
   `app/models/calendar_entry.rb`, `app/models/milestone_rule.rb`, every new
   service, every new job, every new spec.
7. The `CalendarEntry` validations reject every sad-path entry listed in
   §"Required test cases".
