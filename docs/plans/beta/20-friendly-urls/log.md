# Phase 20 — Friendly URLs — Log

> Append-only session log for the Phase 20 friendly URLs work. Newest entries at
> the bottom. Each entry: date, what was discussed, what landed, files touched,
> links to spec / decisions.

---

## 2026-05-10 — Phase opened, spec drafted

Discussed the user directive to drop integer IDs from the address bar app-wide
and to favour a reusable mechanism (gem or shared concern) over per-resource
ad-hoc slug code. Master agent locked the high-level decisions:

- Use the `friendly_id` gem (over a hand-rolled `Sluggable` concern).
- Resources with an existing natural URL-safe identifier reuse it
  (`Channel#channel_url` UC-id portion, `Video#youtube_video_id`,
  `Game#igdb_slug`, `Footage#local_path` basename). Resources without
  (`Project`, `Bundle`, `Collection`, `MilestoneRule`) get a new `slug` column.
- `friendly_id` `:history` module enabled on user-renameable resources
  (Project, Bundle, Collection, MilestoneRule) so old slugs redirect after a
  rename. Disabled on identifier-style ones (Channel, Video, Game, Footage).
- Backwards compat preserved: `Model.friendly.find(param)` accepts both slug
  and integer ID; existing `/foos/42` URLs continue to resolve.
- MCP tools and the `pito` CLI accept both slug and integer ID at the boundary;
  test sweep covers both inputs.
- `CalendarEntry` skipped for now (no current URL surface that exposes it
  heavily); revisit when Video Workflow Features lands.
- Doorkeeper applications keep integer IDs (token ID surfaces are sensitive).
- No per-User slugs (no public profile pages).

Spec written:
`docs/plans/beta/20-friendly-urls/specs/01-friendly-urls-app-wide.md`.

Implementation has not started. Next step: master dispatches rails-impl to
land the gem, the migrations, the model wiring, the controller updates, and
the test sweep, plus mcp-impl and cli-impl for the boundary updates.
