# Phase 16 — Notification Model + Delivery Channels

> **Status:** specs landing 2026-05-10. Implementation pending.
>
> **Realignment work unit:** 8.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; work unit 8
>   ("Notification model + delivery channels + formatter + webhook delivery")
>   plus Resolved ambiguity #6 ("all-users-see-all; no per-user opt-in; webhooks
>   install-level — one each, shared").
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. The notifications half is the source of truth for Phase 16. Per-
>   user `notification_read(...)` join is rejected; install-level shared
>   read-state is the v1 shape per the realignment ambiguity.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install posture; no `tenant_id` on any new table; webhook URLs + feature
>   flags live as install credentials / `AppSetting` rows.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline this phase builds on.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12. `videos.published_at` / `videos.publish_at` /
>   `videos.privacy_status` / `videos.pre_publish_checked_at` are the columns
>   Phase 16's `video_published` / `video_pre_publish_check_missed`
>   notifications hook on.
> - `docs/plans/beta/14-game-model-igdb-sync/` — Phase 14. `games.release_date`
>   feeds the `game_release_*` notification offsets (T-30 / T-7 / T-1 / T-0) via
>   the calendar's `NotificationDispatchDeclaration`.
> - `docs/plans/beta/15-calendar/specs/01-calendar-data-model.md` — Phase 15.
>   `Calendar::NotificationDispatchDeclaration` is the read-only contract Phase
>   16's `NotificationScheduler` consumes. The contract is fixed; the writer
>   (this phase) materializes `Notification` rows from those declarations.

## Specs in this phase

This phase ships as three feature specs to keep the data tier, the formatter /
delivery tier, and the UI / MCP tier self-contained and reviewable:

1. `specs/01-notification-data-model-and-delivery.md` — `notifications` table,
   the `Notification` model + scopes, the install-level Discord + Slack webhook
   delivery posture (credentials + AppSetting flags), the
   `NotificationDeliveryChannel` abstraction with concrete `Discord` / `Slack`
   channels, the Sidekiq jobs (`NotificationDeliver`, `NotificationScheduler`,
   sidekiq-cron schedules), retry / backoff / webhook-failure handling.
2. `specs/02-notification-formatter.md` — per-event-type rendering. Title +
   body + URL templates; Discord rich-embed shape (with severity colors and
   emoji map); Slack block-kit shape; in-app structured payload; MCP plain- text
   payload. Truncation rules per channel.
3. `specs/03-notification-ui-and-mcp-tools.md` — `/notifications` index + show +
   mark-read routes, unread-badge in the nav header (Stimulus + Turbo Stream
   live update), the four MCP tools (`notifications_list`,
   `notifications_mark_read`, `notifications_mark_all_read`,
   `notifications_unread_count`), the `app`-scope gate, and the manual playbook
   covering the full end-to-end smoke.

Each spec carries its own acceptance / test sweep / manual playbook.

## Cross-stack scope

| Surface           | Status                                                                                    |
| ----------------- | ----------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                               |
| MCP rack app      | **In scope.** Spec 3 ships the four read / mark-read tools on the `app` scope.            |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10. CLI parity for new domains is a separate dispatch. |
| Astro / website   | **Skipped.** N/A.                                                                         |

## Next

Master agent dispatches `pito-rails-impl` against Spec 1 first (foundation),
then Spec 2 (consumes Spec 1's `Notification` model), then Spec 3 (consumes
Specs 1 + 2). MCP coverage in Spec 3 fans to `pito-mcp-impl` once the Rails side
is green.

## Sessions

### 2026-05-10 — Spec 01 implementation (rails-impl agent)

Spec 01 (data model + delivery channels) implemented and verified. Two prior
sibling commits (`6391f12` "Fix Turbo Frame mismatch on bulk actions across 5
list surfaces" and `2b271ec` "Phase 19 close-out + Phase 14 Spec 02 + Phase 16
Spec 01 partial") had already landed all of the production code, factories, and
specs. This session re-derived the same files end to end against the spec to
confirm there is no drift, then ran the full Phase 16 suite green.

**Files (all already committed in the two prior commits — no new diffs to
HEAD):**

- Migrations: `20260510170000_create_notifications.rb`,
  `20260510170001_add_webhook_flags_to_app_settings.rb`.
- Model: `app/models/notification.rb` (8 kinds, 4 severities, scopes,
  state methods, idempotency-keys validator, URL well-formedness validator).
- AppSetting helpers: `discord_delivery_enabled?` /
  `slack_delivery_enabled?` (AND-of AppSetting flag with credentials key).
- Channels: `app/services/notification_delivery_channel.rb` (base,
  `TransientFailure` raise-once posture for 5xx / 429 / network),
  `discord.rb`, `slack.rb`, `in_app.rb`.
- Source helpers: `notification_source.rb` namespace,
  `sync_error.rb`, `youtube_reauth_needed.rb`,
  `video_pre_publish_check_missed.rb`.
- Scheduler service: `notification_scheduler.rb` (calendar declarations
  walker + `find_or_create_by!` idempotency, occurred-entry firing for
  `milestone_manual` / `custom`).
- Payload-builder stub: `notification_payload_builder.rb` (Spec 02 will
  replace with per-kind templates).
- Jobs: `notification_deliver.rb` (Sidekiq, retry: 5, 1m / 5m / 15m /
  1h / 6h ladder), `notification_scheduler_job.rb` (cron wrapper).
- Cron: `config/sidekiq_cron.yml` registers `notification_scheduler`
  every minute.

**Specs (all already committed):**

| File                                                                  | Examples |
| --------------------------------------------------------------------- | -------- |
| `spec/factories/notifications.rb`                                     | n/a      |
| `spec/models/notification_spec.rb`                                    | 52       |
| `spec/models/app_setting_spec.rb` (additions)                         | 36 total |
| `spec/services/notification_delivery_channel_spec.rb`                 | 17       |
| `spec/services/notification_delivery_channel/discord_spec.rb`         | 21       |
| `spec/services/notification_delivery_channel/slack_spec.rb`           | 13       |
| `spec/services/notification_delivery_channel/in_app_spec.rb`          | 4        |
| `spec/services/notification_source/sync_error_spec.rb`                | 6        |
| `spec/services/notification_source/youtube_reauth_needed_spec.rb`     | 7        |
| `spec/services/notification_source/video_pre_publish_check_missed_spec.rb` | 7   |
| `spec/services/notification_scheduler_spec.rb`                        | 16       |
| `spec/jobs/notification_deliver_spec.rb`                              | 8        |
| `spec/jobs/notification_scheduler_job_spec.rb`                        | 2        |
| **Phase 16 suite total**                                              | **189**  |

### Quality gates

- `bundle exec rspec` (Phase 16 sweep + adjacent) — green (189 examples,
  0 failures).
- `bundle exec rspec` (full suite) — 3010 examples, 8 failures, 1
  pending. The 8 failures are all pre-existing and unrelated (Phase 14
  Spec 02 in-flight rework: `games_spec.rb` IGDB seed-id collisions,
  `composites_spec.rb` path-traversal request, `video_game_link_spec.rb`
  cascade-on-delete; `calendar/month_spec.rb` non-numeric route
  constraint test, also pre-existing). None of them touch the
  notification surface; they are sibling-agent territory.
- `bundle exec rubocop` (notification surface only — 29 files including
  the migrations, models, services, jobs, factory, specs) — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings.

### Master agent decisions honored

1. **Payload-builder v1 stub.** Minimal stub returning
   `{ title: humanized_event_type, body: nil, url: nil, event_payload: {} }`
   plus an `overrides:` hash so source helpers can supply their per-kind
   strings without waiting for Spec 02. Spec 02 replaces with per-kind
   templates.
2. **Phase 7 / 12 / 13 callsite wiring — DEFERRED.** The three source
   helpers (`SyncError.report!`, `YoutubeReauthNeeded.report!`,
   `VideoPrePublishCheckMissed.report!`) ship with full unit specs; the
   parent jobs (`Youtube::TokenRefresher`, `VideoSyncBack`,
   analytics-sync engine) were NOT modified per the brief. Wiring lands
   in a follow-up dispatch — the parent jobs already track the relevant
   state (`needs_reauth` flip, sync-back error string, missed-check
   detection in Phase 12), so wiring is a one-liner per call site.
3. **Single `retry_count` per row.** Discord + Slack retries on the
   same row both bump the same counter; row counter may read above 5
   if both channels have failed. Documented for Spec 03's UI rendering.
4. **`config/sidekiq_cron.yml` placement.** Followed Phase 15's
   established pattern (`milestone_evaluator`, `calendar_occurred_flipper`).
   New `notification_scheduler` entry mirrors that shape.

### Cross-cutting note (drift / surfaced)

- **UUID vs bigint.** Spec 01 calls for UUID primary keys per ADR 0003;
  the actual schema (calendar_entries, milestone_rules, users, ...)
  uses bigint. Bigint chosen here for FK referential consistency. ADR
  0003 may need an amendment for the URL-vs-PK distinction; flagged
  for master-agent review (Phase 15's log already surfaced the same
  issue).
- **`scheduled_for` column.** Master decision dropped it from v1
  (YAGNI). Schema reflects the drop.

### Manual playbook (handed to user)

The spec ships an 11-step manual playbook (credentials block edit, run
migration, toggle delivery flags, trigger calendar-derived event, sync
error helper, YouTube re-auth helper, missed pre-publish check helper,
webhook failure simulation, full RSpec, rubocop, Sidekiq cron page).
Awaiting user validation before commit.

### Blockers / next steps

- **Spec 02 (formatter)** — replaces the payload-builder stub with
  per-kind Discord embed / Slack block-kit / in-app structured payloads.
- **Spec 03 (UI + MCP tools)** — `/notifications` index + show + mark-read
  routes, four MCP tools on the `app` scope, unread-badge.
- **Source-helper callsite wiring** — three one-line additions in
  Phase 7 / 12 / 13 jobs (`Youtube::TokenRefresher`, `VideoSyncBack`,
  analytics-sync engine). Best landed alongside Spec 02 / 03 so the
  full notification surface ships together.

## 2026-05-10 — Spec 01 security audit fixes (F1–F4)

### Context

Security review of Spec 01 returned four findings rated HIGH / MEDIUM.
Fixed forward in a single rails-impl pass; no new spec doc, only code
+ tests.

### What was implemented

1. **F1 (HIGH) — open-redirect via protocol-relative URL.**
   `Notification::APP_PATH_PATTERN` was `\A/[^\s]*\z` — accepted
   `//evil.com/x` and `/\evil.com/x`. Tightened to
   `\A/(?![/\\])[^\s]*\z`: leading `/` required, second character must
   not be `/` or `\`. Interior double slashes (`/foo//bar`) still pass.
   Added eight regression tests covering the bypass shapes plus
   explicit `javascript:` / `data:` / `vbscript:` / `file:` documenting
   that the pattern shape rejects them.
2. **F2 (MEDIUM) — outbound webhook timeouts.** Hoisted a
   `configure_http(http)` helper onto the base
   `NotificationDeliveryChannel` so Discord and Slack inherit
   identical settings: `open_timeout=5`, `read_timeout=10`,
   `write_timeout=10`, `ssl_timeout=5`. Both `perform_post`
   implementations now call `configure_http(http)` before
   `http.request`. Added per-channel specs that capture the `Net::HTTP`
   instance and assert the four timeouts.
3. **F3 (MEDIUM) — webhook host allowlist.** Each channel now
   exposes `deliverable_url?(url)` (Discord:
   `DISCORD_HOSTS = %w[discord.com discordapp.com]`, Slack:
   `SLACK_HOSTS = %w[hooks.slack.com]`). `enabled?` now folds in the
   allowlist plus a non-blank URL check; a misconfigured URL logs a
   `Rails.logger.warn` once per delivery attempt and returns
   `Result.new(status: :skipped, reason: :disabled)` (no POST is sent
   — verified by the absence of a WebMock stub causing an error if the
   path were exercised). Tests cover valid hosts, attacker-controlled
   hosts, loopback, http-only, the wrong slack subdomain, malformed
   URIs, and the warn log line.
4. **F4 (MEDIUM) — CHECK vs cascade conflict.** New migration
   `db/migrate/20260510190000_fix_notifications_calendar_entry_cascade.rb`
   replaces the `:nullify` FK on `source_calendar_entry_id` with
   `:cascade`. Without `dedup_key`, deleting a calendar entry would
   NULL the FK and raise CHECK; cascade is the cleanest interpretation
   — calendar-derived rows die with their source. The original
   migration is NOT rewritten. Spec rewritten: the old "FK becomes
   NULL" test is replaced by two cascade regression tests (with and
   without an auxiliary `dedup_key`).

### Files touched

- `app/models/notification.rb` — `APP_PATH_PATTERN` tightened.
- `app/services/notification_delivery_channel.rb` — `configure_http`
  helper; `deliverable_url?` subclass interface (default false).
- `app/services/notification_delivery_channel/discord.rb` — allowlist
  constant, `enabled?` integration, `deliverable_url?`,
  `perform_post` calls `configure_http`.
- `app/services/notification_delivery_channel/slack.rb` — same shape
  as Discord with `SLACK_HOSTS`.
- `db/migrate/20260510190000_fix_notifications_calendar_entry_cascade.rb`
  — new.
- `db/schema.rb` — re-emitted by the migration (FK now `:cascade`).
- `spec/models/notification_spec.rb` — F1 protection block + cascade
  regression tests; old nullify test rewritten.
- `spec/services/notification_delivery_channel/discord_spec.rb` — F2
  timeouts block + F3 allowlist block.
- `spec/services/notification_delivery_channel/slack_spec.rb` — same.

### Test outcome

`bundle exec rspec` for the in-scope files (notification model,
delivery base, discord, slack, deliver job): 138 examples, 0
failures. `bundle exec rubocop` clean across the changed files.
`bundle exec brakeman -q -w2`: 0 security warnings.

Three pre-existing failures elsewhere in the suite
(`spec/requests/calendar/month_spec.rb:35`,
`spec/requests/composites_spec.rb:28`,
`spec/services/notification_formatter/discord_spec.rb:231`) are
unrelated to this audit pass and live outside the strict scope
declared by the task.

### Open follow-ups

- Spec 02's `notification_formatter/discord_spec.rb:231` script-tag
  escape assertion is failing; that file is part of the in-progress
  Spec 02 work, not Spec 01, and was excluded from this audit's scope.
- The credentials block remains the same key shape
  (`notifications.discord_webhook_url`,
  `notifications.slack_webhook_url`); operators who configure a URL
  outside the new allowlist will see delivery skipped and a warn line
  rather than a POST. Manual playbook should mention this once Spec 02
  / 03 assemble the user-facing settings page.
