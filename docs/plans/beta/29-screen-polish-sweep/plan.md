# Phase 29 — Screen Polish Sweep — Lane A

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-screen specs land under `specs/` only after a `pito-reviewer` audit exists
> in `audits/` AND the user has triaged it.

---

## Goal

Step 1 of the beta-2 nine-step roadmap. Analyze, fix, and polish the web app
across the existing working screens — one screen at a time — using the
audit-first lifecycle declared in `roadmap.md`. The output is a denser, more
consistent, more accessible web app with no functional regressions and a
regression spec set that locks the polish in.

This phase is scoped to the **web** surface only. MCP / TUI / CLI parity work is
paused (per `CLAUDE.md` follow-ups + auto-memory). Any cross-surface consequence
of a polish change is deferred and noted in the per-screen spec.

---

## Scope statement

In scope:

- Per-screen polish across the existing working web surfaces (channels,
  projects, games, bundles, videos, notes / footage / timelines, settings
  sub-surfaces, security / sessions / tokens / oauth).
- Punch-list audits authored by `pito-reviewer` per screen.
- Polish specs authored by `pito-architect` per screen, including the regression
  spec mandate restated below.
- Regression specs landed in the same commit as each polish change.
- **Unit A0 — Channel read-only conversion** (see below) — runs first, ahead of
  the channel polish audit.

Out of scope:

- Net-new features (those belong in other lanes / phases).
- Cross-surface consequences (MCP / TUI / CLI). Deferred per pause.
- Design vocabulary consolidation across screens. That is Lane H
  (`35-design-consolidation/`) and runs after this lane closes.
- Cloudflare website (`extras/website/`).

---

## Unit A0 — Channel read-only conversion

> Placeholder at the plan level. The actual A0 spec is written by
> `pito-architect` only on per-lane greenlight — no implementation spec is
> authored here. See the roadmap's "Scope amendment — 2026-05-14: channel is a
> read-only mirror" section for the full Cut / Stays / Not-touched / Deferred
> lists.

Per the 2026-05-14 scope decision, the channel becomes a strictly one-way,
read-only mirror — YouTube to pito. pito never writes channel attributes back to
YouTube. Unit A0 removes the now-dead write-side machinery from the channel
surface. It runs **before** the channel polish audit (A-channels), so the
audit-first flow audits the post-cut surface.

**Scope — the cut (fat to remove from the channel surface):**

- `ChannelPreviewComponent` + `Channels::PreviewsController` + the
  `/channels/:id/preview` route — the entire live-preview machinery.
- Editable channel fields on `app/views/channels/edit.html.erb` and
  `app/views/channels/_form.html.erb` — title, handle, description, banner,
  avatar.
- `app/views/channels/_banner_upload.html.erb`,
  `app/views/channels/banner_updated.turbo_stream.erb`.
- The channel diff reconciliation surface: `app/views/channels/diff.html.erb`,
  `app/views/channels/_open_diff_banner.html.erb`, the `diff` action +
  `diff_channel_path` route, the `ChannelDiff` model + its table (a drop
  migration). `app/views/channels/_in_sync_banner.html.erb` is part of the same
  diff-banner family — flag it for review during A0 (likely also removed).

**Stays** (do not remove): the one-way sync pull, the `star` toggle,
URL-locked-after-create, per-channel analytics, the Google connection panel +
revoke flow, links display, the videos table, and **`ChannelChangeLog` / the
`/channels/:id/history` surface** — the read-only mirror's audit trail, kept
deliberately and distinct from the cut `ChannelDiff`.

**Not in scope:** the video thumbnail preview is a video-side surface — A0 does
not touch it.

**Deferred (MCP paused):** `channel_diff_show` / `channel_diff_apply` MCP tools
go dead and `update_channel` shrinks to star-only on a future MCP un-pause. A0
touches no MCP code.

**Lifecycle — NOT audit-first.** A0 is a straight `pito-architect` spec →
`pito-rails` impl. No `pito-reviewer` audit precedes it. On greenlight:

1. `pito-architect` writes the A0 cut spec under `specs/`.
2. `pito-rails` implements the cut and ships the regression specs in the same
   commit.

When the A0 spec is authored, an ADR under `docs/decisions/` should also be
authored — the one-way channel model is a structural commitment per
`CLAUDE.md`'s ADR criteria.

**Regression-spec requirement specific to A0** (in addition to the lane mandate
below):

- **System specs** asserting the channel edit form is gone, the preview routes
  are gone or return 404, and the diff routes are gone or return 404.
- A **model spec / migration spec** covering the `ChannelDiff` table drop — the
  table no longer exists, the model is removed.
- **Request specs** for every removed route (`/channels/:id/preview`, the `diff`
  action, the banner-upload / banner-updated endpoints) asserting they no longer
  resolve.

The channel polish audit (A-channels, audit-first flow) is **gated on A0 landing
first**. Every other Lane A audit screen is day-1 parallel.

---

## Dependencies (which lanes block this)

None. Lane A is greenlit-first per `roadmap.md`. It runs in parallel with Lanes
B, C, E, F, G when they greenlight. Internal to Lane A: the A-channels audit is
gated on unit A0 landing.

---

## Entry conditions

- User greenlight on Lane A in conversation (master agent does not self-open).
- Roadmap at `roadmap.md` exists and matches the current direction.
- `pito-reviewer` is available; `pito-architect` and `pito-rails` are available
  for sequential dispatch.

---

## Exit conditions

- Unit A0 has landed: the channel is a read-only mirror, its cut surface
  removed, A0 regression specs green in CI.
- Every targeted screen has:
  - An audit in `audits/<screen>.md` triaged by the user.
  - A polish spec in `specs/<screen>.md` referencing the audit.
  - A landed implementation with regression specs green in CI.
- Lane log (`log.md`) carries a session entry per screen close.
- No remaining open audit items the user wants addressed in this lane.

---

## Expected agents

- `pito-reviewer` — per-screen audit author. Read-only against the codebase;
  writes punch lists to `audits/`. Does **not** audit unit A0 (A0 is not
  audit-first).
- `pito-architect` — per-screen polish spec author, and the A0 cut spec author.
  Writes to `specs/` only.
- `pito-rails` — per-screen implementation and the A0 implementation, including
  the regression specs.

Master agent coordinates dispatch, reviews report-backs, and commits after user
validation.

---

## Regression spec mandate (restated for this lane)

Every polish unit ships its regression specs in the same commit. The per-screen
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
Additive, never substitutive. The impl agent reports back with green specs
before the master agent commits.

---

## Audit-first flow (restated for this lane)

> Applies to every Lane A unit **except A0**. A0 is a straight architect-spec →
> rails-impl unit — see the "Unit A0" section above.

1. **Audit** — `pito-reviewer` writes `audits/<screen>.md`. Covers alignment,
   density, copy, empty states, dead code, ViewComponent extraction candidates,
   a11y issues, naming inconsistencies, missing regression coverage.
2. **Triage** — user reviews the punch list, decides what moves into the spec.
3. **Spec** — `pito-architect` writes `specs/<screen>.md` with the regression
   spec list.
4. **Implement** — `pito-rails` implements the polish AND writes the regression
   specs in the same commit.

---

## Checkboxes

> Per-screen audits and specs land here as they are produced. None pre-written
> per the scaffold rule.

- [ ] A0 — Channel read-only conversion (architect-spec → rails impl, NOT
      audit-first; runs before the A-channels audit). Spec written on
      greenlight.
- [ ] A-channels polish audit + spec (audit-first; gated on A0 landing).
- [ ] Remaining per-screen audits and polish specs land here once the user
      greenlights the lane and triages each audit.

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella,
  including the 2026-05-14 channel read-only scope amendment.
- `docs/notes/2026-05-11-21-58-29-beta-phase-roadmap.md` — source user note.
- `CLAUDE.md` — project rules, hard rules, surface pause directives.
- `docs/agents/architect.md` — spec pyramid rule D, bracketed-link rule A.
- `docs/design.md` — design vocabulary referenced by audits.
