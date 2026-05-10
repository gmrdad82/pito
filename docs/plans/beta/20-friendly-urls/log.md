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

## 2026-05-10 — `/games/<id>` bug report follow-up: Channel wiring + JSON-format redirect fix

User reported `/games/6` (integer ID URL) showing up instead of the slug URL.
Investigation found:

- `Game.rb` and `Video.rb` already had Phase 20 friendly_id wiring at HEAD
  (`extend FriendlyId; friendly_id :natural_column, use: :finders` + `to_param`
  override with `id.to_s` fallback). The `/games/6` URL is the documented
  fallback when a Game row has no `igdb_slug` (legacy / unsynced). Behaviour
  is by spec (master decision: fallback to integer when slug missing).
- `Channel.rb` had NO friendly_id wiring at all, yet the controller already
  called `Channel.friendly.find(...)`. That call would have raised
  `NoMethodError` on any non-bypassed code path. The earlier attempt to
  declare `friendly_id :url_slug, use: :finders` was broken — friendly_id's
  `:finders` module queries against a DB column, but `url_slug` is a derived
  method (UC-id extracted from `channel_url`). This session swapped to a
  custom `Channel.friendly` finder modeled on `Footage.friendly`, doing a
  `LIKE '%/channel/<slug>'` lookup on `channel_url` with integer-id and
  `channel-<id>` fallbacks.
- `FriendlyRedirect#redirect_to_canonical_slug!` compared `request.path`
  (which includes any `.json` / `.csv` format extension) against
  `model_path(record)` (which does not). JSON requests for a slugged
  resource were being 301-redirected to the HTML path, breaking the JSON
  body in transit. Switched the comparison to `params[:id]` vs `record.to_param`
  so format-bearing requests stay on their own format.
- `ChannelsController#panes` and `VideosController#panes` redirected single-id
  callers via `model_path(ids.first)` where `ids.first` is the raw user input
  (integer or slug string). After Phase 20, the single-pane redirect should
  resolve the input to its canonical slug URL, not echo whatever the caller
  passed. Both controllers now route through `Model.friendly.find(...)` and
  redirect via `model_path(record)`.
- `spec/requests/channels_spec.rb:247` ("open link points to show page")
  asserted `/channels/#{channel.id}` (integer-id URL). Updated to assert
  `/channels/#{channel.to_param}` per the Phase 20 contract.

Files touched:

- `app/models/channel.rb` — `url_slug`, `to_param`, custom `Channel.friendly`
  / `Channel::FriendlyFinder` class.
- `app/controllers/concerns/friendly_redirect.rb` — `params[:id]` vs
  `to_param` comparison.
- `app/controllers/channels_controller.rb` — `panes` single-id redirect via
  `Channel.friendly.find`.
- `app/controllers/videos_controller.rb` — `panes` single-id redirect via
  `Video.friendly.find`.
- `spec/requests/channels_spec.rb` — assertion updated to `channel.to_param`.

Quality gates:

- `bundle exec rspec spec/requests/games_spec.rb spec/requests/channels_spec.rb
  spec/requests/videos_spec.rb spec/requests/bundles_spec.rb
  spec/requests/projects_spec.rb spec/requests/collections_spec.rb
  spec/models/*friendly* spec/mcp/tools/friendly_url_inputs_spec.rb
  spec/requests/friendly_url_redirects_spec.rb`: green except for 5
  pre-existing slug-collision failures in `*_friendly_url_spec.rb` for the
  renameable resources (Project / Bundle / Collection / MilestoneRule),
  confirmed to fail on `HEAD` too (out of this session's scope).
- `bin/brakeman -q -w2`: clean, 0 warnings.
- 4 pre-existing MCP `delete_records` / `sync_records` failures in
  `spec/mcp/tools/`, also confirmed to fail on HEAD, also out of scope.

Open issues (deferred to a follow-up agent):

1. `*_friendly_url_spec.rb` "resolves slug collisions with -2 / -3 suffixes"
   for Project / Bundle / Collection / MilestoneRule (5 examples) — the
   `slug_candidates` / `resolve_friendly_id_conflict` interplay produces a
   UUID-suffixed fallback rather than the expected numeric `-2` suffix.
2. `delete_records` / `sync_records` MCP tools return `not_found_ids` as
   strings (`"99999"`) but the specs assert integers. Either the spec or
   the tool should be aligned.

Next step: master agent reviews this fix-set and decides whether to commit
or to dispatch a follow-up agent for the pre-existing failures.
