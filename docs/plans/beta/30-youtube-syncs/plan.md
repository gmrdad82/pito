# Phase 30 — YouTube Syncs — Lane B

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after user greenlight on the
> architect dispatch.

---

## Goal

Step 2 of the beta-2 nine-step roadmap. Implement the real YouTube sync flows
that turn pito's video and channel rows into round-trippable artifacts:

- **Preview sync** — pull current YouTube state for a video / channel and
  present a diff against the local row before applying.
- **Publish video** — push a video row's editable surface to YouTube
  (thumbnail, title, description, tags, end-screens, chapters as supported by
  the YouTube Data API).
- **Publish channel** — push the channel-level editable surface (banner,
  watermark, description, links) to YouTube.

These flows replace the placeholder `ChannelSync` job and the current
"local-only" video edit form with real Google API round-trips, guarded by the
existing OAuth identity infrastructure landed in Phase 7 / 9 / 24.

---

## Scope statement

In scope:

- New service surface for previewing remote state against local rows.
- New service / job surface for pushing video and channel changes.
- UI affordances on existing screens (Video edit, Channel edit, Video show,
  Channel show) to invoke preview + publish.
- Action confirmation pages for destructive / significant pushes per
  `CLAUDE.md` hard rules (no JS `confirm`).
- Error surfaces — auth errors, rate-limit responses, quota exhaustion,
  validation failures from YouTube.
- Regression specs per the mandate below.

Out of scope:

- New schema for tracking publish history beyond what already exists. If
  needed, it surfaces as an open question in the architect spec and gets
  triaged by the user before dispatch.
- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.

---

## Dependencies (which lanes block this)

None. Lane B can dispatch in parallel with A / C / E / F / G on greenlight.

---

## Entry conditions

- User greenlight on Lane B in conversation.
- Phase 7 (`07-google-oauth-youtube-foundation/`) OAuth flow stable.
- Phase 24 (`24-google-management-on-channels/`) Google management UI on
  channels stable.
- YouTube credentials present in `AppSetting` (see ADR 0007).

---

## Exit conditions

- Preview sync renders a diff for a video and a channel against current
  YouTube state.
- Publish video persists changes to YouTube via the Data API, with retry +
  error surfaces wired in.
- Publish channel persists channel-level edits via the Data API.
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the YouTube syncs spec set (preview, publish
  video, publish channel — sub-specs as the architect decides).
- `pito-rails` — implements the Rails surface and the regression specs.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every sync unit ships its regression specs in the same commit. The architect
spec MUST enumerate the regression spec list before any `pito-rails` impl
runs.

| Layer of change                | Required regression spec type                                                                |
| ------------------------------ | -------------------------------------------------------------------------------------------- |
| View / page change             | RSpec **system spec** (Capybara) exercising the polished interaction                         |
| ViewComponent change           | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic         | RSpec **request spec** or focused **view spec**                                              |
| Routing / controller behavior  | RSpec **request spec**                                                                       |
| Stimulus controller behavior   | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                      |

In addition for this lane, every new service / job / wire-format hook ships
its own spec per the standard pito pyramid (model / service / job / component
/ helper / request / system) — the layer table above is the regression-only
floor. WebMock stubs the YouTube Data API; no live calls in CI.

---

## Checkboxes

> Per-feature specs land here as the architect produces them. None pre-written.

- [ ] Specs to be added on lane kickoff (preview sync, publish video, publish
      channel — exact carving decided by the architect).

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella.
- `docs/plans/beta/07-google-oauth-youtube-foundation/plan.md` — OAuth
  foundation.
- `docs/plans/beta/24-google-management-on-channels/plan.md` — Google
  management UI on channels.
- `docs/decisions/` — ADR 0006 (OAuth identity rename), ADR 0007 (YouTube
  credentials in AppSetting).
- `CLAUDE.md` — hard rules (no JS confirm, yes/no boundary, secrets in
  credentials).
