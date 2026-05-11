# Phase 24 — Google Management on Channels

## One-line goal

Move every Google / YouTube OAuth management surface off `/settings` and onto
`/channels`, and ship a per-channel `[revoke]` flow that cascades a channel's
full data footprint (videos, analytics, diffs, change-logs, links,
rejected-imports, and — when the channel was the last one on its connection —
the `YoutubeConnection` itself, revoking the Google grant).

## Why

Today the Google connection UI lives in two places: the Settings index card
("Google" pane) and the dedicated `/settings/youtube` page. Both surfaces are
channel-shaped data leaking into Settings (which exists for app-wide
preferences). The user wants Settings to stop carrying channel-shaped state, and
they want a single, modal-confirmed `[revoke]` action that cleanly tears down a
channel and everything derived from it — including the underlying OAuth grant
when the channel was the only one keeping the grant alive.

Source-of-truth note:
`docs/notes/2026-05-11-02-08-34-google-section-move-to-channels-revoke-flow.md`.

## Scope

This phase carves five sub-specs:

| #   | Sub-spec slug                          | Surface                                                                                                  |
| --- | -------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 24a | `01a-drop-google-from-settings.md`     | Remove the Google card from `/settings`; remove the `/settings/youtube` page; redirect old URL.          |
| 24b | `01b-google-management-on-channels.md` | New Google management UI on `/channels` (index banner + per-channel inline panel on show).               |
| 24c | `01c-per-channel-revoke-modal.md`      | `[revoke]` action on `/channels/:slug` heading, wide-modal confirmation, controller wiring.              |
| 24d | `01d-delete-channel-data-job.md`       | Sidekiq `DeleteChannelDataJob` — cascading deletion; YoutubeConnection cleanup when last channel leaves. |
| 24e | `01e-bulk-revoke-on-channels-index.md` | Bulk-select + `[revoke N]` on `/channels` index (port from `/settings/youtube`).                         |

The master spec living next to this plan
(`specs/01-google-on-channels-and-revoke-flow.md`) is the umbrella that links
all five sub-specs and lists the autonomous decisions + open questions in one
place. Sub-specs are independently dispatchable to implementation lanes.

## Order of work

Sub-specs 24a, 24b, 24c, 24d can fan out in parallel — each touches a disjoint
file set. 24e ships last because it reuses the modal copy + controller shape
introduced by 24c and depends on 24a having already removed the legacy
bulk-revoke surface from `/settings/youtube`.

A reasonable dispatch wave:

1. Wave A (parallel): 24a, 24b, 24c, 24d.
2. Wave B: 24e.

## Checkboxes

- [x] 24a — Drop Google section from `/settings` + remove `/settings/youtube`
      (redirect).
- [x] 24b — Add Google management UI to `/channels` (index banner + show-page
      panel).
- [x] 24c — Per-channel `[revoke]` action + wide-modal confirmation.
- [x] 24d — `DeleteChannelDataJob` cascade.
- [x] 24e — Bulk `[revoke N]` on `/channels` index.

## Quality gates

Per `docs/plans/beta/beta.md`:

1. All checkboxes ticked (or moved to `dropped.md` with rationale).
2. `log.md` session entry summarizes the completed phase.
3. RSpec coverage for new code; full suite green.
4. Brakeman + bundler-audit clean.
5. Design alignment — if UI/UX changed, `docs/design.md` reflects it.
6. Manual test recipes provided in each sub-spec.
7. User has manually validated before commit. Always.
