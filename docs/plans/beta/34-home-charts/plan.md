# Phase 34 — Home Charts — Lane G

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after user greenlight on the
> architect dispatch.

---

## Goal

Step 7 of the beta-2 nine-step roadmap. Revisit the home page and bring back
real charts. Earlier phases shipped a Chartkick + Groupdate + Chart.js stack and
a placeholder home; the revival's job is to land genuine, useful charts on the
home page sourced from real data (channel + video analytics, queues, recording /
publishing cadence) rather than fixtures.

The deliverable is a polished home with the chart set the user actually wants to
see at a glance.

---

## Scope statement

In scope:

- Selecting the chart set for the home page (analytics, cadence, queues — exact
  set decided by the architect after user discussion).
- Wiring the chart data sources from the existing analytics tables / query
  objects (`channel_window_summaries`, `video_window_summaries`, daily basics,
  etc.).
- Honoring the design rules — no animation, no red, crosshair on line charts,
  bracketed colored legend labels (per `docs/design.md`).
- Regression specs per the mandate below.

Out of scope:

- New analytics ingestion pipelines. Charts reuse existing tables.
- The unresolved click-rate ratio gap (`docs/orchestration/follow-ups.md` item 7
  — `DAILY_BASIC_METRICS` / `WINDOW_RATIO_METRICS` NULLs). If a chart needs the
  missing columns, the architect surfaces it as an open question.
- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.

---

## Dependencies (which lanes block this)

None. Lane G can dispatch in parallel with A / B / C / E / F on greenlight.

---

## Entry conditions

- User greenlight on Lane G in conversation.
- Analytics data backing the chosen charts is available (Phase 13 analytics
  surface should be sufficient; the architect verifies).

---

## Exit conditions

- Home page renders the agreed chart set sourced from real data.
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the home charts spec set.
- `pito-rails` — implements the Rails surface and the regression specs.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every chart unit ships its regression specs in the same commit. The architect
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

- [ ] Specs to be added on lane kickoff (chart set decided by the architect with
      user input).

---

## References

- `docs/plans/beta/13-analytics-sync-engine/specs/03-analytics-dashboard.md` —
  analytics surface that backs the home charts.
- `docs/design.md` — chart rules (no animation, no red, crosshair, bracketed
  legend labels).
- `docs/orchestration/follow-ups.md` — item 7 (click-rate ratio gap).
- `CLAUDE.md` — hard rules.
