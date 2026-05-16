# Phase 36 — Web-App Freeze — Lane I

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after Lane H (Phase 35) has landed
> AND the user greenlights this lane.

---

## Goal

Step 9 of the beta-2 nine-step roadmap. Freeze the web app. After Lanes A
through H have shipped, the web app gets a formal final gate: a sweep over the
entire surface to flush any residual gaps, a security + dependency hygiene pass,
a regression spec audit, and a documented "no further web changes without
explicit re-open" rule.

The freeze is intentionally narrow — it does not produce net-new surface. It
produces a clean, well-spec'd, well-documented state of the web app that the
next phase wave (deployment, MCP / TUI / CLI un-pause, etc.) can build on
without re-doing polish work.

---

## Scope statement

In scope:

- Full-surface gap sweep — any residual issues caught only by looking at the
  whole web app post-consolidation.
- Security + dependency hygiene pass: brakeman, bundler-audit, rubocop, and any
  Dependabot triage still open.
- Regression spec audit — confirm every polished surface from Lanes A-H has the
  mandated regression specs in place; backfill any gaps.
- A "freeze rule" landed in `CLAUDE.md` (via `pito-docs`) declaring that further
  web changes require explicit user re-open until the next wave.

Out of scope:

- Net-new web features. The freeze halts new web surface; that's its point.
- MCP / TUI / CLI parity. Still paused — the un-pause is a separate phase wave,
  not part of the freeze.
- Cloudflare website surface.
- Deployment infrastructure changes.

---

## Dependencies (which lanes block this)

Lane I is **blocked on the close of Lane H (Phase 35 — design consolidation)**.
Indirectly, Lane I is blocked on Lanes A, B, C, D, E, F, G (since Lane H depends
on the polish lanes). The freeze runs over the whole-web state, so every lane
that touches the web app must have shipped first.

---

## Entry conditions

- Lane H closed; consolidated design vocabulary applied.
- All other web lanes (A, B, C, D, E, F, G) closed.
- User greenlight on Lane I in conversation.

---

## Exit conditions

- Gap sweep complete; residual issues fixed.
- Hygiene pass clean (brakeman / bundler-audit / rubocop).
- Regression spec audit clean — every polished surface has the mandated specs.
- Freeze rule landed in `CLAUDE.md` (via `pito-docs`).
- Lane log carries session entries per sub-spec close, with a final "Freeze
  entered" entry on close.

---

## Expected agents

- `pito-architect` — writes the freeze sweep spec set.
- `pito-reviewer` — runs the full-surface gap sweep.
- `pito-rails` — implements remediation and regression spec backfill.
- `pito-security` — runs the security + dependency hygiene pass.
- `pito-docs` — lands the freeze rule in `CLAUDE.md`.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every freeze unit ships its regression specs in the same commit. The architect
spec MUST enumerate the regression spec list before any `pito-rails` impl runs.
Additionally, the regression spec audit is itself a deliverable of this lane —
by the close of Phase 36 every polished surface across Lanes A-H must carry the
mandated specs.

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

- [ ] Specs to be added on lane kickoff (gap sweep, hygiene pass, regression
      audit, freeze rule — carving decided by the architect).

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/plans/beta/35-design-consolidation/plan.md` — Lane H (blocker).
- `CLAUDE.md` — project rules; freeze rule lands here on close.
- `docs/orchestration/follow-ups.md` — backlog to reconcile against the freeze.
