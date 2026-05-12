# Phase 29 — Screen Polish Sweep — Lane A

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-screen specs land under `specs/` only after a `pito-reviewer` audit
> exists in `audits/` AND the user has triaged it.

---

## Goal

Step 1 of the beta-2 nine-step roadmap. Analyze, fix, and polish the web app
across the existing working screens — one screen at a time — using the
audit-first lifecycle declared in `roadmap.md`. The output is a denser, more
consistent, more accessible web app with no functional regressions and a
regression spec set that locks the polish in.

This phase is scoped to the **web** surface only. MCP / TUI / CLI parity work
is paused (per `CLAUDE.md` follow-ups + auto-memory). Any cross-surface
consequence of a polish change is deferred and noted in the per-screen spec.

---

## Scope statement

In scope:

- Per-screen polish across the existing working web surfaces (channels,
  projects, games, bundles, videos, notes / footage / timelines, settings
  sub-surfaces, security / sessions / tokens / oauth).
- Punch-list audits authored by `pito-reviewer` per screen.
- Polish specs authored by `pito-architect` per screen, including the
  regression spec mandate restated below.
- Regression specs landed in the same commit as each polish change.

Out of scope:

- Net-new features (those belong in other lanes / phases).
- Cross-surface consequences (MCP / TUI / CLI). Deferred per pause.
- Design vocabulary consolidation across screens. That is Lane H
  (`35-design-consolidation/`) and runs after this lane closes.
- Cloudflare website (`extras/website/`).

---

## Dependencies (which lanes block this)

None. Lane A is greenlit-first per `roadmap.md`. It runs in parallel with
Lanes B, C, E, F, G when they greenlight.

---

## Entry conditions

- User greenlight on Lane A in conversation (master agent does not self-open).
- Roadmap at `roadmap.md` exists and matches the current direction.
- `pito-reviewer` is available; `pito-architect` and `pito-rails` are
  available for sequential dispatch.

---

## Exit conditions

- Every targeted screen has:
  - An audit in `audits/<screen>.md` triaged by the user.
  - A polish spec in `specs/<screen>.md` referencing the audit.
  - A landed implementation with regression specs green in CI.
- Lane log (`log.md`) carries a session entry per screen close.
- No remaining open audit items the user wants addressed in this lane.

---

## Expected agents

- `pito-reviewer` — per-screen audit author. Read-only against the codebase;
  writes punch lists to `audits/`.
- `pito-architect` — per-screen polish spec author. Writes to `specs/` only.
- `pito-rails` — per-screen implementation, including the regression specs.

Master agent coordinates dispatch, reviews report-backs, and commits after
user validation.

---

## Regression spec mandate (restated for this lane)

Every polish unit ships its regression specs in the same commit. The per-screen
architect spec MUST enumerate the regression spec list before any
`pito-rails` impl runs.

| Layer of change                | Required regression spec type                                                                |
| ------------------------------ | -------------------------------------------------------------------------------------------- |
| View / page change             | RSpec **system spec** (Capybara) exercising the polished interaction                         |
| ViewComponent change           | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic         | RSpec **request spec** or focused **view spec**                                              |
| Routing / controller behavior  | RSpec **request spec**                                                                       |
| Stimulus controller behavior   | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                      |

A change crossing layers carries the specs for **every** layer touched.
Additive, never substitutive. The impl agent reports back with green specs
before the master agent commits.

---

## Audit-first flow (restated for this lane)

1. **Audit** — `pito-reviewer` writes `audits/<screen>.md`. Covers alignment,
   density, copy, empty states, dead code, ViewComponent extraction candidates,
   a11y issues, naming inconsistencies, missing regression coverage.
2. **Triage** — user reviews the punch list, decides what moves into the spec.
3. **Spec** — `pito-architect` writes `specs/<screen>.md` with the regression
   spec list.
4. **Implement** — `pito-rails` implements the polish AND writes the
   regression specs in the same commit.

---

## Checkboxes

> Per-screen audits and specs land here as they are produced. None pre-written
> per the scaffold rule.

- [ ] Specs to be added on lane kickoff (per-screen audits and polish specs land
      here once the user greenlights the lane and triages each audit).

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/notes/2026-05-11-21-58-29-beta-phase-roadmap.md` — source user note.
- `CLAUDE.md` — project rules, hard rules, surface pause directives.
- `docs/agents/architect.md` — spec pyramid rule D, bracketed-link rule A.
- `docs/design.md` — design vocabulary referenced by audits.
