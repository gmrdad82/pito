# Phase 35 — Design Consolidation — Lane H

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after Lanes A, D, E, F, G have
> landed AND the user greenlights this lane.

---

## Goal

Step 8 of the beta-2 nine-step roadmap. Consolidate the design across the
polished web app for a unified experience. The point of running this lane after
the polish lanes (A, D, E, F, G) is to reconcile residual inconsistencies that
only surface once all the screens have been touched: recurring component
patterns that drifted, copy patterns that diverged, spacing / density that did
not converge, color tokens used inconsistently, empty-state idioms that vary
across surfaces.

The deliverable is a unified design vocabulary applied across the web app —
likely a refresh of `docs/design.md`, a sweep of component reuse, and targeted
polish where consolidation requires it.

---

## Scope statement

In scope:

- A consolidation pass across the polished surfaces — components, copy, spacing,
  color tokens, empty-state idioms.
- Updates to `docs/design.md` reflecting the consolidated vocabulary (routed
  through `pito-docs` per the agent role split — not authored by the architect
  directly).
- Targeted polish where reconciliation needs an implementation change.
- Regression specs per the mandate below.

Out of scope:

- Net-new features. Lane H is consolidation, not new surface.
- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.

---

## Dependencies (which lanes block this)

Lane H is **blocked on the close of Lanes A, D, E, F, G**. Running before these
land would re-do work as the surfaces continue to shift.

- Lane A — `docs/plans/beta/29-screen-polish-sweep/`
- Lane D — `docs/plans/beta/11-video-workflow-features/` (01b-01f)
- Lane E — `docs/plans/beta/32-settings-spread/`
- Lane F — `docs/plans/beta/33-help-affordance/`
- Lane G — `docs/plans/beta/34-home-charts/`

Lanes B (YouTube syncs) and C (Calendar revamp) do not strictly block Lane H —
their surfaces are visited in Lane A's audit pass. The architect verifies the
dependency surface before dispatch.

---

## Entry conditions

- Lanes A, D, E, F, G all closed.
- User greenlight on Lane H in conversation.

---

## Exit conditions

- Design vocabulary consolidated across the polished surfaces.
- `docs/design.md` updated (via `pito-docs`).
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the consolidation spec set.
- `pito-rails` — implements the Rails surface and the regression specs.
- `pito-docs` — updates `docs/design.md` to reflect the consolidated vocabulary
  (architect-out-of-scope per role split).

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every consolidation unit ships its regression specs in the same commit. The
architect spec MUST enumerate the regression spec list before any `pito-rails`
impl runs.

| Layer of change               | Required regression spec type                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| View / page change            | RSpec **system spec** (Capybara) exercising the polished interaction                                           |
| ViewComponent change          | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic        | RSpec **request spec** or focused **view spec**                                                                |
| Routing / controller behavior | RSpec **request spec**                                                                                         |
| Stimulus controller behavior  | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                                        |

A change crossing layers carries the specs for **every** layer touched.

---

## Checkboxes

> Per-feature specs land here as the architect produces them. None pre-written.

- [ ] Specs to be added on lane kickoff (consolidation carving decided by the
      architect after Lanes A / D / E / F / G have closed).

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/design.md` — design vocabulary (to be refreshed by `pito-docs` as part
  of this lane).
- `CLAUDE.md` — hard rules.
