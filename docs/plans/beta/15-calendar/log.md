# Phase 15 — Calendar Model + Views

> **Status:** specs landing 2026-05-10. Implementation pending.
>
> **Realignment work unit:** 7.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; work unit 7
>   ("Calendar model + views") plus Resolved ambiguity #5 (month grid + Schedule
>   view; day / week deferred).
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. Source of truth for the calendar entry shape, the eight `entry_type`
>   values, type-specific metadata jsonb, milestone rules, purchase-planned
>   entries, calendar views. The notifications half of the note is Phase 16
>   (next phase).
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install posture; no `tenant_id` on any new table.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope. (Phase 15 does not ship MCP tools; the
>   coverage matrix is documented for Phase 16's sibling.)
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline this phase builds on.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12. Establishes `videos.published_at`, `videos.publish_at`,
>   `videos.privacy_status`. Calendar's derived `video_published` /
>   `video_scheduled` entries depend on these columns existing.
> - `docs/plans/beta/14-game-model-igdb-sync/specs/01-data-model-and-igdb-client.md`
>   — Phase 14. Establishes `games.release_date`, `games.igdb_id`,
>   `games.igdb_slug`. Calendar's `game_release` derived entries depend on
>   `games.release_date` being populated.

## Specs in this phase

This phase ships as two feature specs to keep the data tier and the UI tier
self-contained and reviewable:

1. `specs/01-calendar-data-model.md` — `calendar_entries` table + the eight
   `entry_type` values + `milestone_rules` table + auto-derive jobs (from Video
   / Game / Channel) + manual entry CRUD model layer + idempotent firing
   semantics for milestone rules. Notification-firing hooks are declared here;
   delivery code is Phase 16.
2. `specs/02-calendar-views.md` — `/calendar/month/:year/:month` and
   `/calendar/schedule` routes + controllers + ERB views per `docs/design.md`
   - Stimulus navigation controller + quick-add manual entry form + edit /
     delete via the action confirmation page framework.

Each spec carries its own acceptance / test sweep / manual playbook.

## Cross-stack scope

| Surface           | Status                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                                                                                           |
| MCP rack app      | **Skipped.** Realignment work unit 9. The calendar MCP tools (`calendar_list`, `calendar_create`, etc.) land alongside Phase 16's notification tools. |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10. CLI parity for new domains is a separate dispatch.                                                             |
| Astro / website   | **Skipped.** N/A.                                                                                                                                     |

## Next

Master agent dispatches `pito-rails-impl` against the two specs in order once
the user signs off. Spec 1 is the foundation (Spec 2 reads / writes through Spec
1's models). Phase 16 (notifications) starts after Phase 15 lands and the user
validates.

## Sessions

(empty — appended after the user validates each implementation pass)
