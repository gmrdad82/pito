# Beta progress snapshot — 2026-05-10 21:30

## Implementation: ~85%

| Unit                     | Phase  | Status                                                                 |
| ------------------------ | ------ | ---------------------------------------------------------------------- |
| 1 — Tenant drop          | 8      | ✓ done + reviewed + security clean                                     |
| 2 — MCP scope sim        | 10     | ✓ done + reviewed + security clean                                     |
| 3 — Channel sync         | 11     | ⏸ blocked on schema input                                              |
| 4 — Video schema         | 12     | ✓ done + reviewer + security + F1/F2 fix                               |
| 5 — Analytics            | 13     | ✓ all 3 specs in main + reviewer; security audit in flight             |
| 6 — Game model + IGDB    | 14     | ✓ all 3 specs + reviewers; security audit in flight                    |
| 7 — Calendar             | 15     | ✓ done + reviewer + security + F1/F2 fix + UX restructure              |
| 8 — Notifications        | 16     | ✓ all 3 specs + Spec 01 security + F1-F4 fix; reviewer 02/03 in flight |
| 9 — MCP catalog          | folded | ✓                                                                      |
| 10 — CLI parity          | 18     | ◐ partial; rest awaits JSON APIs                                       |
| 11 — Phase 7.5 close-out | 19     | ✓                                                                      |
| 12 — Distribution        | n/a    | ⏸ deferred                                                             |

Plus Phase 9 (GoogleIdentity rename) ✓ and Phase 20 (friendly URLs app-wide) ◐.

## UX polish landed

- Pane primitives: pane / pane--wide / pane--narrow / pane--game-detail /
  pane.pane--standalone / pane-row--game-show
- `[label]` (no inner spaces) project-wide; `[ ] checkbox` carved-out exception
- Lead paragraphs: 1 sentence per line via `<br>`
- Navbar: [home][calendar] · [channels][videos] ·
  [projects][games][notifications] fluid |hotkey-driven search| ·
  [settings][logout]
- Footer: 2 rows (nav + copy)
- Theme keybind n→t
- Hotkeys: `/` global search, `i` IGDB search
- Game show: 3-pane layout (cover/details + sync + linked videos)
- Game show/edit split + resync mutex + indicator animation
- Calendar restructure: [+] in breadcrumb, [prev]/[today]/[next] aligned, [ ]
  all master toggle, view persistence
- Project show: timelines pane → videos pane
- Notifications: superscript badge, modal detail, dynamic mark-button, cleanup
  cron
- Settings index: 5-row pane-row grid + user account section
- IGDB filter: main_game category only

## Suite size

~3850+ RSpec examples, mostly green. Some pre-existing flakes / order-dependent
issues.

## Outstanding

- Phase 11 Channel sync — blocked on your schema input
- Phase 12 distribution — deferred ~6 months
- Phase 18 CLI parity — partial; awaits JSON APIs
- Phase 20 friendly URLs — migrations applied; model wiring + spec sweep in
  flight
- Phase 13/14/16 security audits — IN FLIGHT
- Phase 16 Spec 02/03 reviewer — IN FLIGHT

## Validation queue when you're back

Playbooks + security findings under
`docs/orchestration/playbooks/2026-05-10-phase-*.md`. Walk in order, validate
via `bin/dev`.

## Master agent's next moves

1. Land in-flight reviewer + security agents → commit playbooks
2. Phase 20 friendly_id full coverage sweep → verify all 8 resources resolve via
   slug
3. UX polish as you flag issues
4. Stop on Phase 11 (Channel sync) — needs your schema input
