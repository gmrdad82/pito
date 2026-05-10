# Beta progress snapshot — 2026-05-10 22:30

## Implementation: ~92%

## What landed since 21:30

- **Phase 13 closeout (analytics):** Spec 01/02/03 reviewer + security audit +
  F1+F2+F3 fix-forward (ServiceFactory routing, retry-on-401, per-resource
  refresh lock). +25 specs.
- **Phase 14 closeout (game model + IGDB):** Spec 02/03 security audit + F1+F2
  fix-forward (IGDB client + Composite::TileCache HTTP timeouts) +
  Igdb::TokenCache third-path fix. +9 specs.
- **Phase 16 closeout (notifications):** Spec 02/03 reviewer + security audit +
  F1+F2+F3 fix-forward (URL scheme allowlist on in-app + 3 outbound formatters;
  per-user mark-read rate limit). +57 specs.
- **Phase 20 (friendly URLs app-wide):** Implementation + 1053 friendly-URL
  specs across 10 models, redirects, MCP inputs, lifecycle system spec.
  Channel + Footage use custom finders (slug derived from partial column);
  Game/Video/Note use friendly_id natural-column finders;
  Project/Bundle/Collection/MilestoneRule use slugged + history + finders.
  JSON-safe `FriendlyRedirect` concern.
- **Phase 21 (JSON endpoints for CLI/MCP parity):** spec + plan landed (828
  lines), 8 decisions locked, implementation IN FLIGHT.

## Suite size

~4400+ RSpec examples. Phase 20 added 1053; Phases 13/14/16 fix-forwards added
~91 combined. Pre-existing flakes confirmed unrelated to current sessions.

## Phase status table

| Phase                     | Status                                             |
| ------------------------- | -------------------------------------------------- |
| 8 — tenant drop           | ✓ done                                             |
| 9 — GoogleIdentity rename | ✓ done                                             |
| 10 — MCP scope sim        | ✓ done                                             |
| 11 — Channel sync         | ⏸ blocked on schema input                          |
| 12 — Video schema         | ✓ done                                             |
| 13 — Analytics            | ✓ done (sec CLEAR, 3 medium fix-forwarded)         |
| 14 — Game + IGDB          | ✓ done (sec CLEAR, 2+1 medium fix-forwarded)       |
| 15 — Calendar             | ✓ done (sec CLEAR, 2 medium fix-forwarded)         |
| 16 — Notifications        | ✓ done (Specs 01/02/03 sec CLEAR, fixes-forwarded) |
| 18 — CLI parity           | ◐ partial; awaits Phase 21 endpoints               |
| 19 — Phase 7.5 close-out  | ✓ done                                             |
| 20 — Friendly URLs        | ✓ done                                             |
| 21 — JSON endpoints       | spec ✓; impl IN FLIGHT                             |

## Outstanding work

- Phase 21 JSON endpoints — IN FLIGHT
- Phase 11 (Channel sync) — blocked on your schema input
- Phase 12 distribution — deferred ~6 months
- Phase 18 (CLI parity) — awaits Phase 21
- 2 pre-existing flakes (calendar/month, composites) — confirmed not
  regressions; tracked in follow-ups

## Validation queue when you're back

Playbooks at `docs/orchestration/playbooks/2026-05-10-*.md`:

- Phase 13 reviewer + security
- Phase 14 Spec 02/03 reviewer + security
- Phase 15 calendar (earlier)
- Phase 16 Spec 02/03 reviewer + security
- Phase 20 friendly URLs lifecycle (system spec covers core journey)

## Master agent's next moves

1. Land Phase 21 JSON endpoints → commit
2. Dispatch CLI parity sweep against new endpoints (Phase 18 advance)
3. Dispatch MCP follow-up tools against new endpoints
4. Stop on Phase 11 (Channel sync) — schema input needed
