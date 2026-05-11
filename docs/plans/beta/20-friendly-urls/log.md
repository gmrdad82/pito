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
- `friendly_id` `:history` module enabled on user-renameable resources (Project,
  Bundle, Collection, MilestoneRule) so old slugs redirect after a rename.
  Disabled on identifier-style ones (Channel, Video, Game, Footage).
- Backwards compat preserved: `Model.friendly.find(param)` accepts both slug and
  integer ID; existing `/foos/42` URLs continue to resolve.
- MCP tools and the `pito` CLI accept both slug and integer ID at the boundary;
  test sweep covers both inputs.
- `CalendarEntry` skipped for now (no current URL surface that exposes it
  heavily); revisit when Video Workflow Features lands.
- Doorkeeper applications keep integer IDs (token ID surfaces are sensitive).
- No per-User slugs (no public profile pages).

Spec written:
`docs/plans/beta/20-friendly-urls/specs/01-friendly-urls-app-wide.md`.

Implementation has not started. Next step: master dispatches rails-impl to land
the gem, the migrations, the model wiring, the controller updates, and the test
sweep, plus mcp-impl and cli-impl for the boundary updates.

## 2026-05-10 — `/games/<id>` bug report follow-up: Channel wiring + JSON-format redirect fix

User reported `/games/6` (integer ID URL) showing up instead of the slug URL.
Investigation found:

- `Game.rb` and `Video.rb` already had Phase 20 friendly_id wiring at HEAD
  (`extend FriendlyId; friendly_id :natural_column, use: :finders` + `to_param`
  override with `id.to_s` fallback). The `/games/6` URL is the documented
  fallback when a Game row has no `igdb_slug` (legacy / unsynced). Behaviour is
  by spec (master decision: fallback to integer when slug missing).
- `Channel.rb` had NO friendly_id wiring at all, yet the controller already
  called `Channel.friendly.find(...)`. That call would have raised
  `NoMethodError` on any non-bypassed code path. The earlier attempt to declare
  `friendly_id :url_slug, use: :finders` was broken — friendly_id's `:finders`
  module queries against a DB column, but `url_slug` is a derived method (UC-id
  extracted from `channel_url`). This session swapped to a custom
  `Channel.friendly` finder modeled on `Footage.friendly`, doing a
  `LIKE '%/channel/<slug>'` lookup on `channel_url` with integer-id and
  `channel-<id>` fallbacks.
- `FriendlyRedirect#redirect_to_canonical_slug!` compared `request.path` (which
  includes any `.json` / `.csv` format extension) against `model_path(record)`
  (which does not). JSON requests for a slugged resource were being
  301-redirected to the HTML path, breaking the JSON body in transit. Switched
  the comparison to `params[:id]` vs `record.to_param` so format-bearing
  requests stay on their own format.
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

- `app/models/channel.rb` — `url_slug`, `to_param`, custom `Channel.friendly` /
  `Channel::FriendlyFinder` class.
- `app/controllers/concerns/friendly_redirect.rb` — `params[:id]` vs `to_param`
  comparison.
- `app/controllers/channels_controller.rb` — `panes` single-id redirect via
  `Channel.friendly.find`.
- `app/controllers/videos_controller.rb` — `panes` single-id redirect via
  `Video.friendly.find`.
- `spec/requests/channels_spec.rb` — assertion updated to `channel.to_param`.

Quality gates:

- `bundle exec rspec spec/requests/games_spec.rb spec/requests/channels_spec.rb spec/requests/videos_spec.rb spec/requests/bundles_spec.rb spec/requests/projects_spec.rb spec/requests/collections_spec.rb spec/models/*friendly* spec/mcp/tools/friendly_url_inputs_spec.rb spec/requests/friendly_url_redirects_spec.rb`:
  green except for 5 pre-existing slug-collision failures in
  `*_friendly_url_spec.rb` for the renameable resources (Project / Bundle /
  Collection / MilestoneRule), confirmed to fail on `HEAD` too (out of this
  session's scope).
- `bin/brakeman -q -w2`: clean, 0 warnings.
- 4 pre-existing MCP `delete_records` / `sync_records` failures in
  `spec/mcp/tools/`, also confirmed to fail on HEAD, also out of scope.

Open issues (deferred to a follow-up agent):

1. `*_friendly_url_spec.rb` "resolves slug collisions with -2 / -3 suffixes" for
   Project / Bundle / Collection / MilestoneRule (5 examples) — the
   `slug_candidates` / `resolve_friendly_id_conflict` interplay produces a
   UUID-suffixed fallback rather than the expected numeric `-2` suffix.
2. `delete_records` / `sync_records` MCP tools return `not_found_ids` as strings
   (`"99999"`) but the specs assert integers. Either the spec or the tool should
   be aligned.

Next step: master agent reviews this fix-set and decides whether to commit or to
dispatch a follow-up agent for the pre-existing failures.

## 2026-05-10 — Full implementation pass: gem, migrations, models, controllers, MCP, specs

Rails-impl agent landed the rest of the Phase 20 work after Channel +
JSON-format fixes shipped. Locked answers were applied verbatim per the parent
dispatch.

What landed in this session:

- `Gemfile` — `gem "friendly_id", "~> 5.5"` (resolves to 5.7.0 latest 5.x).
  `bundle install` clean.
- `bin/rails generate friendly_id` produced `config/initializers/friendly_id.rb`
  (default config retained) and
  `db/migrate/20260510192743_create_friendly_id_slugs.rb`. All five migrations
  applied to dev DB; `db/migrate:status` reports no `down` rows remain.
- Four `slug` column migrations + backfill, one per renameable model:
  `add_slug_to_projects`, `add_slug_to_bundles`, `add_slug_to_collections`,
  `add_slug_to_milestone_rules`. Each adds `slug :string`, backfills via
  `find_each` using `Pito::SlugBuilder`, then enforces NOT NULL + a unique
  index. All four ran cleanly against the dev DB.
- New shared helper at `app/lib/pito/slug_builder.rb` — transliteration + hyphen
  collapsing + 80-char truncation on a hyphen boundary. Shared between
  migrations (anonymous `Class.new(ActiveRecord::Base)` table-stubs) and runtime
  model `normalize_friendly_id` callbacks so backfilled slugs and live slugs
  match byte-for-byte.
- Renameable models (Project, Bundle, Collection, MilestoneRule) wire
  `extend FriendlyId; friendly_id :name, use: %i[slugged history finders]` plus
  per-model overrides:
  - `normalize_friendly_id` routes through `Pito::SlugBuilder` (80-char cap,
    transliteration, hyphen boundary truncation, typed-prefix fallback
    `<type>-<id>` for empty input).
  - `resolve_friendly_id_conflict` returns `<base>-2` / `<base>-3` / ... so
    renames + collisions land the user-friendly numeric suffix from locked
    decision #2 instead of friendly_id's default UUID suffix.
  - `should_generate_new_friendly_id?` fires on `name` change so renames
    regenerate the slug (default friendly_id behaviour only regenerates on a
    blank `slug` column).
- Identifier-style models split across two patterns:
  - Video / Game use `extend FriendlyId; friendly_id :<col>, use: :finders`
    (`youtube_video_id` / `igdb_slug`) — the gem's `:finders` integration is a
    clean 1:1 column lookup.
  - Channel / Footage ship a custom `Model.friendly` finder. The slug is derived
    from `channel_url` (UC-id portion) / `local_path` basename respectively, so
    a column-bound friendly_id integration doesn't fit; the custom finder
    accepts slug, integer id, and the fallback shapes (`channel-<id>`,
    `<basename>-<id>`).
- `Note` controller switched to `Note.find_by!(path:)` via a `*path` glob route;
  `Note#to_param` returns `path` verbatim. The controller's new
  `restore_html_format` before_action keeps `.md`-suffixed URLs from being
  parsed as a non-registered Rails format (the implicit HTML render would
  otherwise 406).
- All controllers that look up slugged resources switched to
  `Model.friendly.find(params[:id])` (plus `params[:<resource>_id]` for nested
  routes). New `FriendlyRedirect` controller concern emits 301s from integer-ID
  GETs to the canonical slug URL.
- MCP tools (15 touched) accept slug-or-id at every slugged-resource argument.
  `delete_records` / `sync_records` array shapes preserve the caller's input
  type in `not_found_ids` so existing integer-id callers keep round-tripping
  integers.
- Bulk URL pattern (`/<action>s/:type/:ids`) unchanged per locked decision #4 —
  `:ids` accepts integers and slugs interchangeably.

Test sweep (per the user's "fully specced" directive):

- `spec/lib/friendly_id_setup_spec.rb` — gem wiring matrix (which model opts
  into `:history`, which uses the custom finder, etc.).
- `spec/support/friendly_url_shared_examples.rb` — generic contract: slug
  generation on create, suffix collision, `to_param`, `friendly.find` by slug +
  integer + integer-string, rename, history, blank-name fallback, unicode
  transliteration, long-name truncation, edge-character stripping.
- Per-model `<model>_friendly_url_spec.rb` for all eight slugged models + Note's
  path-based lookup.
- `spec/requests/friendly_url_redirects_spec.rb` — cross-resource 301 matrix.
- `spec/mcp/tools/friendly_url_inputs_spec.rb` — MCP slug-or-id matrix.
- `spec/system/friendly_url_lifecycle_spec.rb` — system spec covering the
  canonical journey: visit, integer-id-301, rename, history-301, 404 on
  never-existed slug.

Quality gates:

- `bundle exec rspec` (Phase 20 specs alone): 161 examples, 0 failures.
- Full suite
  (`bundle exec rspec --exclude-pattern spec/system/calendar_edit_delete_spec.rb`):
  4232 examples, 2 pre-existing flaky failures
  (`spec/requests/calendar/month_spec.rb:90` and
  `spec/requests/composites_spec.rb:28`) that pass in isolation and also fail on
  `HEAD` without Phase 20 changes. Not regressions.
- `bundle exec rubocop`: 828 files, 0 offenses.
- `bin/brakeman -q -w2`: 41 controllers, 52 models, 0 warnings.
- `bundle exec bundler-audit check --update`: no vulnerabilities found.

Files touched (high level):

- `Gemfile`, `Gemfile.lock` — friendly_id ~> 5.5 added.
- `config/initializers/friendly_id.rb` — generator output.
- `config/routes.rb` — `/notes/*path` glob route added.
- Five `db/migrate/2026051019274{3..7}_*.rb` migrations + dev-DB applied.
- `app/lib/pito/slug_builder.rb` — new shared helper.
- `app/models/{channel,video,game,footage,project,bundle,collection,milestone_rule,note}.rb`
  — friendly_id wiring per the locked matrix.
- `app/controllers/concerns/friendly_redirect.rb` — new shared concern.
- 11 controllers updated for `Model.friendly.find` (channels, videos, projects,
  games, footages, bundles, collections, notes, timelines, bundle_members,
  video_game_links + 4 nested analytics controllers + 1 api controller).
- 15+ MCP tools updated for slug-or-id boundary.
- New specs: friendly_id setup, shared examples, 10 per-model files, request
  redirects, MCP inputs, system lifecycle.

Blockers: none. Open follow-ups: the calendar_edit_delete_spec system spec
failure was pre-existing (no link "note" expected on a derived calendar entry,
but the view no longer renders that link). Unrelated to Phase 20.
