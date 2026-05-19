# Phase 37 — `/channels` revamp

Source of truth for this phase: the
`docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md` document
(read end-to-end before working any wave). The wave breakdown below mirrors that
handoff's "Implementation plan" section; this `plan.md` is the in-phase pointer
+ checklist surface.

## Way of work (locked)

- **Layout-first with mocked data.** Real-shape values via
  `Channels::MockData.*`. Real-data swap happens ONLY after the user signs off
  on visuals.
- **No RSpec during layout.** Specs are a dedicated consolidation pass (Wave F).
  Iteration agents write code only.
- **No write operations on channels.** `/channels` is a read-only mirror this
  phase. Sole exception: bulk revoke via `Channels::BulkRevokesController`.

## Phase folder convention

- Specs live in `docs/plans/beta/37-channels-revamp/specs/`.
- Session log lives in `docs/plans/beta/37-channels-revamp/log.md` (appended
  after user validation per the project log convention).

## Wave checklist

### Wave A — Mocked dashboard layout

- [x] A1 — `/channels` dashboard shell + title bar + filter chips + avatar shelf
      + ID-card shelf (shipped 2026-05-19)
- [ ] A2 — Filter-chip → controller wiring + Basics section (this spec:
      `specs/02-wave-a2-chip-wiring-basics.md`)
- [ ] A3 — Top Content section (union-merged ranked list, channel-of-origin
      badges)
- [ ] A4 — Window summaries section (tabs across 7d / 28d / 3m / 365d /
      alltime)
- [ ] A5 — Trend indicators section (subs / views / watch time deltas)
- [ ] A6 — Audience geography
- [ ] A7 — Audience demographics (age × gender)
- [ ] A8 — Device Type breakdown
- [ ] A9 — Viewer time heatmap (day × hour)
- [ ] A10 — Traffic sources (find-your-videos + external + search terms)
- [ ] A11 — Latest content shelf (5 latest uploads merged, badged)
- [ ] A12 — Sync buttons + sync state per channel
- [ ] A13 — Multi-channel picker modal (`[+]` target)
- [ ] A14 — Revoke flow UI wiring (`[-]` target →
      `Channels::BulkRevokesController`)
- [ ] A15 — User validation gate

### Wave B — Real API wiring

See the handoff doc §"Implementation plan" → Wave B (B1–B16). Locked once Wave A
is signed off.

### Wave C — Channel-rollup tables

See the handoff doc §"Implementation plan" → Wave C.

### Wave D — Cross-report queries (ADR 0011)

See the handoff doc §"Implementation plan" → Wave D.

### Wave E — Trend deltas

See the handoff doc §"Implementation plan" → Wave E.

### Wave F — Spec reactivation + factory updates + system-spec debt sweep

See the handoff doc §"Implementation plan" → Wave F.

### Wave G — Navbar + keybindings reactivation + closeout

See the handoff doc §"Implementation plan" → Wave G.

## Cross-cutting design-time decisions (carried from handoff §"Design-time decisions flagged for Wave A architect")

1. Aggregation rules per metric — discover during layout iteration.
2. Channel filter URL shape — locked to `?channels=id1,id2,id3` (csv).
3. Section combine-vs-split-vs-both — per-section decision at layout time.
4. Top shelf chip design — locked: avatar + checkbox (no name label inside the
   chip). Names live on the ID-card shelf.
5. `[+]` button position — locked: title bar, immediately after the "channels"
   label.
6. Trend indicator display — locked: glyph (▲ / – / ▼) + numeric delta percent;
   exact percent style decided per-section as Wave E lands.
