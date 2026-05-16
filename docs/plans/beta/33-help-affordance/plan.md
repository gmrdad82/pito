# Phase 33 — Help Affordance — Lane F

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after user greenlight on the
> architect dispatch.

---

## Goal

Step 6 of the beta-2 nine-step roadmap. Add a `[help]` affordance on each screen
that surfaces feature explanations in-context. The user wants per-screen help —
short, scannable, screen-relevant — so the web app stops being a
discovery-by-clicking experience for surfaces with non-obvious affordances.

The deliverable is a help affordance pattern (bracketed-link, per design
vocabulary), a content authoring model (where help copy lives, who edits it),
and the screen-by-screen integration.

---

## Scope statement

In scope:

- Help affordance UI pattern — placement, click behavior, dismissal, keyboard
  reachability.
- Content authoring model — markdown / partial / locale file / dedicated
  `HelpEntry` records. The architect spec decides and surfaces it as an open
  question for the user before implementation.
- Per-screen integration. Every screen that ships a `[help]` link ships its help
  copy in the same commit.
- Regression specs per the mandate below.

Out of scope:

- A separate "help center" / docs site. The affordance is in-context per screen,
  not a global help destination.
- Translating help into multiple locales. Locale-friendly storage is acceptable
  but not in scope to populate.
- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.

---

## Dependencies (which lanes block this)

None for the pattern. Per-screen integration benefits from Lane A's screen
polish landing first (so help copy doesn't immediately go stale), but the
architect spec can be drafted in parallel.

---

## Entry conditions

- User greenlight on Lane F in conversation.

---

## Exit conditions

- Help affordance pattern shipped and used on every targeted screen.
- Help copy authored for each screen.
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the help affordance spec set (pattern + per-screen
  content carving).
- `pito-rails` — implements the Rails surface and the regression specs.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every affordance unit ships its regression specs in the same commit. The
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

- [ ] Specs to be added on lane kickoff (pattern spec plus per-screen
      integration specs — carving decided by the architect).

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/design.md` — bracketed-link convention (the `[help]` link uses the
  standard `[label]` form per `docs/agents/architect.md` rule A).
- `CLAUDE.md` — hard rules.
