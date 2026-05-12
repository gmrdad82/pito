# Phase 32 — Settings Spread — Lane E

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after user greenlight on the
> architect dispatch.

---

## Goal

Step 5 of the beta-2 nine-step roadmap. The settings page has accreted into
a dense list of sub-surfaces (auth tokens, OAuth apps, sessions,
YouTube credentials, AppSetting toggles, channel-level identity management,
appearance / theme, etc.). The revamp's job is to simplify the entry point
and spread the sub-surfaces across a more navigable layout — denser where
density helps, sparser where the user keeps getting lost.

The deliverable is a settings index that fronts a clearer top-level grouping
and per-sub-surface detail pages tuned for ergonomic interaction.

---

## Scope statement

In scope:

- Re-laying out the settings index page and its top-level grouping.
- Per-sub-surface ergonomic polish (form density, copy, confirmation flows,
  empty states) where it intersects the spread.
- Stitching together any sub-surfaces that the architect determines should
  collapse or fan out further.
- Regression specs per the mandate below.

Out of scope:

- Net-new settings (new toggles, new providers). If a setting needs to be
  added to support another lane, it ships in that lane's spec, not here.
- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.

---

## Dependencies (which lanes block this)

None. Lane E can dispatch in parallel with A / B / C / F / G on greenlight.

---

## Entry conditions

- User greenlight on Lane E in conversation.

---

## Exit conditions

- Settings index reorganized; each sub-surface remains reachable.
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the settings spread spec set.
- `pito-rails` — implements the Rails surface and the regression specs.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every spread unit ships its regression specs in the same commit. The architect
spec MUST enumerate the regression spec list before any `pito-rails` impl
runs.

| Layer of change                | Required regression spec type                                                                |
| ------------------------------ | -------------------------------------------------------------------------------------------- |
| View / page change             | RSpec **system spec** (Capybara) exercising the polished interaction                         |
| ViewComponent change           | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic         | RSpec **request spec** or focused **view spec**                                              |
| Routing / controller behavior  | RSpec **request spec**                                                                       |
| Stimulus controller behavior   | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                      |

A change crossing layers carries the specs for **every** layer touched.

---

## Checkboxes

> Per-feature specs land here as the architect produces them. None pre-written.

- [ ] Specs to be added on lane kickoff (carving decided by the architect).

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/design.md` — design vocabulary referenced by the spread.
- `CLAUDE.md` — hard rules (secrets in credentials, no JS confirm).
