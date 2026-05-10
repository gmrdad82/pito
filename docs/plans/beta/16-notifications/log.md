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

(empty — appended after the user validates each implementation pass)
