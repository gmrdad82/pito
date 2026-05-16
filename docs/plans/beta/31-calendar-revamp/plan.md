# Phase 31 — Calendar Revamp — Lane C

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after user greenlight on the
> architect dispatch.
>
> The original calendar phase (`docs/plans/beta/15-calendar/`) stays in place as
> historical reference. This phase is the revamp; it supersedes, rather than
> continues, the original surface.

---

## Goal

Step 3 of the beta-2 nine-step roadmap. Revisit the calendar — built in Phase 15
— and revamp it. The original delivered a data model + month / week / day views
over recording, publishing, and gameplay sessions, but the surface has aged
against the rest of the web app: density, interaction patterns, integration with
channel / video / game rows, and visual consistency all want a fresh pass.

The revamp produces an updated calendar surface that fits beta-2's design
direction, consolidates with channel reminders and post-publish hooks where they
overlap, and ships its own regression spec set.

---

## Scope statement

In scope:

- Revisiting the calendar's data model only where the existing model proves
  insufficient for the revamped UX. Schema-conservative by default — the
  architect spec flags any new column / table as an open question.
- Revamping the visual surface (month / week / day views, event tiles, filter /
  scope chips, empty states).
- Stitching the calendar into adjacent surfaces (channel reminders, video
  publish hooks, game release tracking) where the integrations matter.
- Regression specs per the mandate below.

Out of scope:

- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.
- Reverse-migrating off the Phase 15 calendar schema. The revamp builds on it.

---

## Dependencies (which lanes block this)

None. Lane C can dispatch in parallel with A / B / E / F / G on greenlight.
Note: if Lane B (YouTube syncs) introduces post-publish workflow hooks that the
calendar wants to surface, that interaction is captured in the architect spec as
an open question. Lanes do not auto-block each other unless the architect
surfaces the dependency.

---

## Entry conditions

- User greenlight on Lane C in conversation.
- Phase 15 calendar still functional (the revamp builds on its data model).

---

## Exit conditions

- Calendar surface revamp shipped; the existing routes continue to work
  end-to-end.
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the calendar revamp spec set.
- `pito-rails` — implements the Rails surface and the regression specs.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every revamp unit ships its regression specs in the same commit. The architect
spec MUST enumerate the regression spec list before any `pito-rails` impl runs.

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

- [ ] Specs to be added on lane kickoff (carving decided by the architect).

---

## References

- `docs/plans/beta/15-calendar/specs/01-calendar-data-model.md` — original data
  model.
- `docs/plans/beta/15-calendar/specs/02-calendar-views.md` — original views.
- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/plans/beta/30-youtube-syncs/plan.md` — adjacent post-publish hooks.
- `CLAUDE.md` — hard rules.
