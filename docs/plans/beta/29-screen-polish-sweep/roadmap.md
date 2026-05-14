# Beta-2 Web-App Roadmap — Umbrella

> Source-of-truth user note:
> `docs/notes/2026-05-11-21-58-29-beta-phase-roadmap.md`.
>
> This is the umbrella roadmap for the beta-2 wave of web-app work. It is
> deliberately a scaffold: no per-screen audits, no per-feature implementation
> specs, no impl details land here. Each lane below kicks off only on explicit
> user greenlight. The master agent waits.

---

## The 9-step plan (verbatim)

1. **Analyze, fix, polish** the web app across the existing working screens.
2. **Implement YouTube syncs** — previews, publish video, publish channel.
3. **Revisit and revamp the calendar.**
4. **Visit and polish the video edit page.**
5. **Simplify and spread the settings page** for easier interaction.
6. **Add a `[help]` affordance on each screen** with feature explanations.
7. **Revisit home** to bring back real charts.
8. **Consolidate design** for a unified experience across the web app.
9. **Freeze the web app.**

---

## Scope amendment — 2026-05-14: channel is a read-only mirror

On 2026-05-14 the user cut channel scope: the **channel is now a strictly
one-way, read-only mirror — YouTube to pito**. pito never writes channel
attributes back to YouTube. There is no channel publish, no channel
reconciliation, no channel edit form. The channel surface only ever pulls.

When the cut unit (Lane A unit A0 below) is specced, an ADR under
`docs/decisions/` should be authored: the one-way channel model is a structural
commitment per `CLAUDE.md`'s ADR criteria, not a routine in-flow choice.

### Cut — fat to remove from the channel surface

- `ChannelPreviewComponent` + `Channels::PreviewsController` + the
  `/channels/:id/preview` route — the entire live-preview machinery (avatar,
  title, handle, description, banner previews all live in this one component).
- Editable channel fields on `app/views/channels/edit.html.erb` and
  `app/views/channels/_form.html.erb` — title, handle, description, banner,
  avatar.
- `app/views/channels/_banner_upload.html.erb`,
  `app/views/channels/banner_updated.turbo_stream.erb`.
- The channel **diff reconciliation** surface:
  `app/views/channels/diff.html.erb`,
  `app/views/channels/_open_diff_banner.html.erb`, the `diff` action +
  `diff_channel_path` route, the `ChannelDiff` model + its table (a drop
  migration). `app/views/channels/_in_sync_banner.html.erb` is part of the same
  diff-banner family — flag it for review during the cut unit (likely also
  removed).

### Stays on the channel

- The one-way sync **pull** (overwrite local cache, no reconciliation step).
- The `star` toggle.
- URL-locked-after-create.
- Per-channel analytics.
- The Google connection panel + revoke flow.
- Links display.
- The videos table.
- **`ChannelChangeLog` / the `/channels/:id/history` surface** — the user
  explicitly chose to keep it. It is the read-only mirror's **audit trail**,
  distinct from the now-cut `ChannelDiff` (which was a pending-reconciliation
  surface). A future reader must not cut history by mistake: `ChannelChangeLog`
  stays, `ChannelDiff` goes.

### Not in scope — do not touch

- The video **thumbnail preview** is a video-side surface, unrelated to
  channels. No downstream agent touches it as part of this amendment or the A0
  cut unit.

### Deferred — MCP is paused

- `channel_diff_show` and `channel_diff_apply` MCP tools become dead on MCP
  un-pause; `update_channel` shrinks to star-only. **No MCP code is touched
  now** — these are recorded here as deferred-cut items for the future MCP
  un-pause wave.

---

## Lane table

| Step | Lane name            | Phase folder                  | Primary agent                                     | Depends on    | Status                                                                                           |
| ---- | -------------------- | ----------------------------- | ------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------ |
| 1    | Screen polish sweep  | `29-screen-polish-sweep/`     | `pito-reviewer` + `pito-architect` + `pito-rails` | none          | not-started — A0 (channel read-only conversion) runs first, then A-channels audit, then the rest |
| 2    | YouTube syncs        | `30-youtube-syncs/`           | `pito-architect` + `pito-rails`                   | none          | not-started — B1 (channel sync pull) + B2 (publish-video workflow)                               |
| 3    | Calendar revamp      | `31-calendar-revamp/`         | `pito-architect` + `pito-rails`                   | none          | not-started                                                                                      |
| 4    | Video edit polish    | `11-video-workflow-features/` | `pito-architect` + `pito-rails`                   | none          | partially-shipped — 01a done, 01b-01f queued                                                     |
| 5    | Settings spread      | `32-settings-spread/`         | `pito-architect` + `pito-rails`                   | none          | not-started                                                                                      |
| 6    | Help affordance      | `33-help-affordance/`         | `pito-architect` + `pito-rails`                   | none          | not-started                                                                                      |
| 7    | Home charts          | `34-home-charts/`             | `pito-architect` + `pito-rails`                   | none          | not-started                                                                                      |
| 8    | Design consolidation | `35-design-consolidation/`    | `pito-architect` + `pito-rails`                   | A, D, E, F, G | not-started                                                                                      |
| 9    | Web-app freeze       | `36-web-app-freeze/`          | `pito-architect` + `pito-reviewer`                | H             | not-started                                                                                      |

Lane D (Video edit polish) is **not duplicated** under a new phase number. It
continues to track at `docs/plans/beta/11-video-workflow-features/` with its
existing 01a-01f sub-spec set. The lane is referenced from this roadmap purely
to make the beta-2 wave legible end-to-end.

---

## Regression spec mandate

Every polish unit in every lane ships its regression specs in the same commit as
the change. No exceptions. The architect spec for each unit MUST enumerate the
regression spec list before any `pito-rails` impl runs; the impl agent reports
back green specs before the master agent commits.

Coverage rules by layer:

| Layer of change               | Required regression spec type                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| View / page change            | RSpec **system spec** (Capybara) exercising the polished interaction                                           |
| ViewComponent change          | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic        | RSpec **request spec** or focused **view spec**                                                                |
| Routing / controller behavior | RSpec **request spec**                                                                                         |
| Stimulus controller behavior  | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                                        |

A change that crosses layers (e.g. a controller change plus a ViewComponent
change plus a Stimulus controller) carries the regression specs for **every**
layer touched. Specs are additive — never substitute a system spec for a
component spec or vice versa just because they overlap.

The mandate restates in each lane's `plan.md` so a lane-scoped dispatch can
honor it without cross-reading.

---

## Lane A audit-first flow

Lane A (screen polish sweep) introduces an audit-first lifecycle per screen.
Every A-unit follows the same four steps:

1. **Audit** — `pito-reviewer` produces a punch list for the screen. The audit
   covers alignment, density, copy, empty states, dead code, ViewComponent
   extraction candidates, a11y issues, naming inconsistencies, and missing
   regression coverage. Output lands at
   `docs/plans/beta/29-screen-polish-sweep/audits/<screen>.md`.
2. **Triage** — the user reviews the punch list and decides which items move
   into the polish spec. This is the human checkpoint; the architect does not
   pre-empt it.
3. **Spec** — `pito-architect` writes the polish spec at
   `docs/plans/beta/29-screen-polish-sweep/specs/<screen>.md`. The spec
   enumerates the regression spec list (per the mandate above) before any
   implementation runs.
4. **Implement** — `pito-rails` implements the polish AND writes the regression
   specs in the same commit. Specs MUST be green before report-back.

The reviewer's audit and the architect's spec are separate artifacts. The
reviewer does not produce a spec; the architect does not skip the audit. Master
agent dispatches in sequence, waiting on user direction between Audit and Spec.

### Unit A0 — Channel read-only conversion (NOT audit-first)

Per the 2026-05-14 scope amendment above, Lane A has a dedicated **unit A0 —
Channel read-only conversion** that runs **first**, before any channel polish
audit. A0 does **not** follow the audit-first flow. Its lifecycle is a straight
**`pito-architect` spec → `pito-rails` impl**:

1. **Spec** — `pito-architect` writes the A0 cut spec (on greenlight only).
2. **Implement** — `pito-rails` removes the cut surface (see the amendment's Cut
   list) and ships regression specs proving the channel is read-only: no edit
   form, no preview routes, no diff routes, the `ChannelDiff` table drop
   migration applied.

The channel polish audit (audit-first flow) becomes **A-channels** and runs
**after A0 lands** — it audits the post-cut channel surface, not the pre-cut
one. Every other Lane A audit screen is still day-1 parallel; only the channels
audit is gated on A0.

---

## Day-1 fan-out plan (held)

> **ON HOLD — awaiting user greenlight.** Nothing in this section ships until
> the user explicitly opens the lane.

On greenlight, the master agent dispatches the following work in parallel where
possible:

- **Lane A unit A0** (`pito-architect` spec → `pito-rails` impl, NOT
  audit-first): Channel read-only conversion. Runs **first**. The channels audit
  below is gated on A0 landing.
- **Lane A audits** (parallel, one `pito-reviewer` per screen):
  - **A-channels** (index / show / edit / picker / workspace panes) — **gated on
    A0 landing first**; not day-1 parallel. Audits the post-cut, read-only
    channel surface.
  - Projects (index / show / edit / picker)
  - Games (index / show / edit / picker / shelves / filter row)
  - Bundles (index / show / edit)
  - Videos index + show (workspace panes, picker, single-record show)
  - Notes / Footage / Timelines trio (notes index + show / edit, footage index
    - show, timelines index + show)

  - Settings sub-surfaces (the existing settings index and each detail panel)
  - A7 — Security surfaces: sessions, tokens, oauth applications, doorkeeper
    authorizations, login security pending-approval flow

- **Lane B** (`pito-architect` writes spec): YouTube syncs — B1 channel sync
  pull + B2 publish-video workflow (channel previews and publish-channel are cut
  per the scope amendment).
- **Lane C** (`pito-architect` writes spec): Calendar revamp
- **Lane E** (`pito-architect` writes spec): Settings spread
- **Lane F** (`pito-architect` writes spec): Help affordance per screen
- **Lane G** (`pito-architect` writes spec): Home real charts revival

Lane D (Phase 11 video edit polish) continues its existing 01b → 01f dispatch
queue inside `docs/plans/beta/11-video-workflow-features/`; nothing in the day-1
fan-out changes for it.

The fan-out is parallel by lane and by audit-screen, with the single exception
that the A-channels audit waits on A0. Each lane that produces an architect spec
waits for user open-question resolution before its `pito-rails` dispatch.

---

## Lane H consolidation

Lane H (design consolidation) only kicks off **after** Lanes A, D, E, F, and G
have landed. The point of Lane H is to reconcile the polished surfaces into a
single unified design vocabulary — component reuse, layout consistency, copy
patterns, color tokens, density. Running it before the polish lanes land would
re-do work as the surfaces continue to shift.

Lane H's regression spec mandate matches the global one: every consolidation
unit ships its specs in the same commit.

---

## Lane I freeze

Lane I (web-app freeze) is the final gate. It assumes Lane H has consolidated
the design vocabulary and Lanes A-G have shipped their polish. The freeze is a
formal milestone: a sweep over the entire web surface checking for residual
gaps, a brakeman + bundler-audit + rubocop sweep, a regression spec audit, and a
documented "no further web changes without explicit re-open" rule until the next
wave.

After Lane I, web-app work pauses and the next phase wave begins (MCP / TUI /
CLI un-pause, deployment, etc. — out of scope for this roadmap).

---

## Surface pause status

Per `CLAUDE.md` "Active follow-ups" and the auto-memory pause directive, the
following surfaces are paused for the duration of Lanes A-I:

- **MCP** — no new MCP tool work as part of beta-2 polish.
- **TUI / CLI (`pito` Rust binary)** — no parity work.
- **Cloudflare website (`extras/website/`)** — not in scope.

Any MCP / CLI consequence of a polish change (e.g. a new wire-format field, a
renamed boundary parameter) is **deferred** to a future un-pause. The polish
spec notes the deferred surface; the impl spec does not implement it. When the
pause lifts, those deferred items get their own architect specs against the
fresh state.

The channel read-only conversion (unit A0) has its own deferred MCP items —
`channel_diff_show` / `channel_diff_apply` go dead and `update_channel` shrinks
to star-only — recorded in the scope-amendment section above.

---

## Greenlight protocol

The master agent does **not** dispatch any lane work without explicit user
greenlight per lane. The greenlight unblocks the day-1 fan-out for that lane
only. Lanes do not auto-cascade — landing Lane A does not auto-trigger Lane B.
Each lane completion returns to the user for the next greenlight.

---

## References

- `docs/notes/2026-05-11-21-58-29-beta-phase-roadmap.md` — source-of-truth user
  note.
- `CLAUDE.md` — project rules, hard rules, active follow-ups (Phase 11 queue +
  pause directives).
- `docs/orchestration/follow-ups.md` — full open backlog.
- `docs/agents/architect.md` — spec pyramid rule D, bracketed-link rule A,
  yes/no boundary rule E.
- `docs/design.md` — design vocabulary referenced by Lane H consolidation.
- `docs/plans/beta/11-video-workflow-features/plan.md` — Lane D phase plan
  (referenced, not duplicated).
