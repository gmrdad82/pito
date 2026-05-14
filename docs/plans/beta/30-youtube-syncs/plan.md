# Phase 30 — YouTube Syncs — Lane B

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-feature specs land under `specs/` only after user greenlight on the
> architect dispatch.

---

## Goal

Step 2 of the beta-2 nine-step roadmap. Implement the real YouTube sync flows
for pito's channel and video rows. Per the 2026-05-14 scope amendment in the
roadmap (channel is a read-only mirror — YouTube to pito), Lane B is two units:

- **B1 — Channel sync pull.** Turn the placeholder `ChannelSync` job into a real
  one-way YouTube → pito pull: fetch current YouTube channel state and overwrite
  the local cache. **No reconciliation / diff step** — the channel is a
  read-only mirror, so the pull just refreshes the local copy.
- **B2 — Publish-video workflow.** Push a video row's editable surface to
  YouTube (thumbnail, title, description, tags, end-screens, chapters as
  supported by the YouTube Data API), with action confirmation, retry, and error
  surfaces.

B1 replaces the placeholder `ChannelSync` job with a real Google API pull. B2
replaces the current "local-only" video edit form with a real Google API
round-trip, guarded by the existing OAuth identity infrastructure landed in
Phase 7 / 9 / 24.

The folder name `30-youtube-syncs/` and the lane name "YouTube syncs" still fit
— both B1 and B2 are YouTube sync flows; only the scope text changes.

---

## Removed from this lane

The original Lane B scope was "YouTube syncs — previews, publish video, publish
channel." Two of those are **struck**:

- **Channel previews** — struck. The channel preview machinery is being cut
  entirely (Phase 29 unit A0). A read-only mirror has nothing to preview before
  applying.
- **Publish channel** — struck. pito never writes channel attributes back to
  YouTube. There is no channel push.

Rationale and the full Cut / Stays / Deferred lists live in the roadmap's "Scope
amendment — 2026-05-14: channel is a read-only mirror" section.

---

## Scope statement

In scope:

- **B1** — a real one-way channel sync pull: a service / job surface that
  fetches YouTube channel state and overwrites the local cache. No diff, no
  reconciliation, no apply step.
- **B2** — a service / job surface for pushing video changes to YouTube.
- UI affordances on existing screens (Video edit, Video show) to invoke the
  publish-video workflow; channel screens get the pull trigger only.
- Action confirmation pages for destructive / significant pushes per `CLAUDE.md`
  hard rules (no JS `confirm`).
- Error surfaces — auth errors, rate-limit responses, quota exhaustion,
  validation failures from YouTube.
- Regression specs per the mandate below.

Out of scope:

- Channel previews and publish-channel (cut — see "Removed from this lane").
- New schema for tracking publish history beyond what already exists. If needed,
  it surfaces as an open question in the architect spec and gets triaged by the
  user before dispatch.
- MCP / TUI / CLI parity. Paused.
- Cloudflare website surface.

---

## Dependencies (which lanes block this)

B1 (channel sync pull) is cleanest after Phase 29 unit A0 (channel read-only
conversion) lands, since A0 removes the channel diff surface B1 would otherwise
have to reconcile against. The architect spec confirms ordering on greenlight.
Otherwise Lane B can dispatch in parallel with A / C / E / F / G.

---

## Entry conditions

- User greenlight on Lane B in conversation.
- Phase 7 (`07-google-oauth-youtube-foundation/`) OAuth flow stable.
- Phase 24 (`24-google-management-on-channels/`) Google management UI on
  channels stable.
- YouTube credentials present in `AppSetting` (see ADR 0007).

---

## Exit conditions

- B1: the channel sync pull fetches current YouTube state and overwrites the
  local cache, with retry + error surfaces wired in. No diff surface.
- B2: publish video persists changes to YouTube via the Data API, with retry +
  error surfaces wired in.
- Regression specs green in CI.
- Lane log carries session entries per sub-spec close.

---

## Expected agents

- `pito-architect` — writes the Lane B spec set (B1 channel sync pull, B2
  publish-video workflow — sub-specs as the architect decides).
- `pito-rails` — implements the Rails surface and the regression specs.

Master agent coordinates dispatch and commits after user validation.

---

## Regression spec mandate (restated for this lane)

Every sync unit ships its regression specs in the same commit. The architect
spec MUST enumerate the regression spec list before any `pito-rails` impl runs.

| Layer of change               | Required regression spec type                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| View / page change            | RSpec **system spec** (Capybara) exercising the polished interaction                                           |
| ViewComponent change          | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic        | RSpec **request spec** or focused **view spec**                                                                |
| Routing / controller behavior | RSpec **request spec**                                                                                         |
| Stimulus controller behavior  | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                                        |

In addition for this lane, every new service / job / wire-format hook ships its
own spec per the standard pito pyramid (model / service / job / component /
helper / request / system) — the layer table above is the regression-only floor.
WebMock stubs the YouTube Data API; no live calls in CI.

---

## Checkboxes

> Per-feature specs land here as the architect produces them. None pre-written.

- [ ] B1 — channel sync pull (one-way YouTube → pito, overwrite local cache, no
      reconciliation). Spec written on greenlight.
- [ ] B2 — publish-video workflow (push video edits to YouTube via the Data
      API). Spec written on greenlight.

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella,
  including the 2026-05-14 channel read-only scope amendment.
- `docs/plans/beta/07-google-oauth-youtube-foundation/plan.md` — OAuth
  foundation.
- `docs/plans/beta/24-google-management-on-channels/plan.md` — Google management
  UI on channels.
- `docs/decisions/` — ADR 0006 (OAuth identity rename), ADR 0007 (YouTube
  credentials in AppSetting).
- `CLAUDE.md` — hard rules (no JS confirm, yes/no boundary, secrets in
  credentials).
