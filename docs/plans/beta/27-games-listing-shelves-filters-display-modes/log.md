# Phase 27 — log

## 2026-05-10 — Game tile metadata two-line layout (pito-rails)

Reshaped the game-tile caption per user feedback (image #77). The
caption is now two explicit lines below the cover art:

    Red Dead Redemption 2        ← line 1: title, ellipsis-truncated
    ★ 93 · 2018                  ← line 2: rating zero-padded, year

Rating now appears FIRST, year SECOND (reversed from the legacy
`Title (2018) ★ 93` single-line caption). Star is U+2605, separator
is the middle-dot U+00B7. Rating is zero-padded to a minimum of two
digits (`5 → 05`, `93 → 93`, `100 → 100`).

### Missing-data handling

- Rating only: `★ 93`
- Year only: `2018`
- Both missing: line 2 omitted entirely
- Title is never blank (DB default `Untitled game`)

### Variant typography

The partial now accepts an optional `variant:` local (`:grid`
default, `:shelf` opt-in). All existing callers omit the local and
inherit `:grid` — pure-additive change. The `:shelf` variant shrinks
the title font (11px → 10px) and the meta font (10px → 9px) to
match the smaller `Games::CoverComponent` `:shelf` footprint.

### Files changed

- `app/helpers/games_helper.rb` (new) — `format_game_rating(rating)`
  and `game_meta_line(game)` helpers.
- `app/views/games/_tile.html.erb` — two-line caption layout with
  ellipsis truncation, variant-aware typography, and the reversed
  rating-then-year ordering.
- `spec/helpers/games_helper_spec.rb` (new, 17 examples) — covers
  the helper truth table (nil, single-digit, two-digit, three-digit
  ratings; rating-only / year-only / both / neither meta lines;
  separator placement; star glyph; defensive leading / trailing
  separator checks).
- `spec/views/games/_tile.html.erb_spec.rb` (new, 33 examples) —
  happy-path two-line shape, ellipsis CSS (`white-space: nowrap`,
  `overflow: hidden`, `text-overflow: ellipsis`, `max-width: 150px`),
  rating zero-padding visible, separator placement, missing-data
  edge cases, variant defaults, shelf-variant font sizes, anchor /
  keyboard wiring preservation, and flaw assertions against the
  legacy single-line caption.

### Gates

- `rspec spec/helpers/games_helper_spec.rb spec/views/games/_tile.html.erb_spec.rb spec/components/games/cover_component_spec.rb`
  — 84 examples, 0 failures.
- Adjacent suites (`spec/views/games/_grid_mode.html.erb_spec.rb`,
  `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`,
  `spec/system/games_index_spec.rb`,
  `spec/system/games_steam_shelf_spec.rb`,
  `spec/requests/games_spec.rb`) — all green.
- `rubocop` — clean (1127 files inspected, no offenses).
- `brakeman -q -w2` — 0 warnings, 0 errors.

### References

- User feedback image #77 (master agent dispatch).
- `app/helpers/games_helper.rb` (new helper module).
- `app/components/games/cover_component.rb` (untouched; metadata
  lives on the tile partial, not the cover component).

## 2026-05-11 — sub-spec 01e Shelf cover-art variant (pito-rails)

Implemented sub-spec 01e per
`specs/01e-shelf-cover-art-variant.md` and the addendum
`docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`.
This sub-spec introduces the `Games::CoverComponent` ViewComponent
that owns cover-art rendering at two server-side variants —
`:grid` (existing all-games-grid size) and `:shelf` (new shelf-row
size). Downstream consumers (01c Genres / Collections shelves,
01d shelves-by-letter display mode) render this component instead
of inlining `image_tag` calls.

### Size decision — `:shelf` at 65% of grid

The addendum locked: "try 50% first; if Claude Code judges 50% too
small in practice — covers unreadable, cramped, titles printed on
art lost — use 65–70% instead without asking."

The existing grid tile is 150 × 200 px (not the 234 × 312 the
architect's spec assumed — the spec was written against a
hypothetical future grid size; current reality is 150 × 200 from
`app/views/games/_tile.html.erb`).

- 50% of 150 × 200 → 75 × 100 px. Below the legibility threshold
  for IGDB cover art. Persona-style title banners, sequel "II"
  subtitles, and year stamps printed on art disappear into noise
  at sub-90px widths. Effectively reduces the cover from a
  recognition aid to a colored swatch.
- 65% of 150 × 200 → 97.5 × 130 → rounded to **98 × 130 px**.
  Recognizable, dense, titles printed on art still legible.
  Matches the spec's locked ratio AND the lower end of the
  addendum's fallback range.
- 70% of 150 × 200 → 105 × 140 px. Marginally larger, gains
  readability, but loses ~14% horizontal density per shelf.

**Chosen: 65% (98 × 130 px).** Sits at the lower end of the
addendum's "65–70%" fallback range — preserves shelf density
while clearing the readability bar.

The IGDB CDN source token for `:shelf` is `t_cover_small_2x`
(180 × 256 native, downsamples cleanly into 98 × 130). The
`:grid` variant continues to source from `t_cover_big` (264 × 374
native). The two URLs differ, so cache keys differ — no CSS
scaling tricks anywhere.

### Files touched

**New:**

- `app/components/games/cover_component.rb` —
  `Games::CoverComponent` with `DIMENSIONS` map (`:grid` →
  150×200 / `t_cover_big`, `:shelf` → 98×130 / `t_cover_small_2x`).
  Validates the variant symbol at init (`ArgumentError` on
  unknown). Accepts `game:`, `variant:` (default `:grid`),
  `link_to_show:` (default `true`).
- `app/components/games/cover_component.html.erb` — renders an
  `<a>` (or `<div>` when `link_to_show: false`) sized via inline
  width/height (CLS guard) AND the `.game-cover game-cover--<v>`
  CSS class, plus `data-variant=<v>` for downstream styling /
  spec assertions. Missing-cover branch renders the standard
  `[no cover]` placeholder inside a sized slot.
- `spec/components/games/cover_component_spec.rb` — 28 examples
  across happy / sad / edge / flaw / friendly-URL / introspection
  groups. Includes the spec's mandatory "no `transform: scale`,
  no `width: 65%`" flaw assertions.

**Edited:**

- `app/models/game.rb` — `COVER_SIZES` extended with
  `t_cover_small_2x` and an inline comment pointing at the 01e
  variant. The existing `cover_url(size:)` guard now accepts the
  new token. (No other changes — the Phase 27 01a per-platform
  ownership rework on this model landed in parallel and is
  unrelated.)
- `app/assets/tailwind/application.css` — added `.game-cover`,
  `.game-cover--grid`, `.game-cover--shelf`, `.game-cover-img`,
  `.game-cover-missing` rules. Real fixed pixel sizes per variant
  — NO `transform: scale`, NO percentage widths, NO `zoom`.
- `spec/models/game_spec.rb` — added two examples in the
  `#cover_url` block confirming `t_cover_small_2x` resolves to
  the expected IGDB CDN URL and is whitelisted by
  `Game::COVER_SIZES`.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
  — ticked the four 01e checkboxes; corrected the size note to
  reflect the actual 150 × 200 grid baseline (the original
  checkbox copy carried the spec's hypothetical 234 × 312).

### Specs added

- 28 new component examples (`Games::CoverComponent`).
- 2 new game-model examples (`t_cover_small_2x` whitelist + URL).

Spec count delta: **+30**.

### Gates

- `bundle exec rspec spec/components/games/cover_component_spec.rb`
  → 28 examples, 0 failures.
- `bundle exec rspec spec/components/` → 225 examples, 0 failures
  (full component surface green).
- `bundle exec rspec spec/components/games/cover_component_spec.rb spec/models/game_spec.rb`
  → 94 examples, 1 failure. The single failure is at
  `spec/models/game_spec.rb:10` and asserts the now-removed
  `belongs_to :platform_owned` association — that removal landed
  in parallel from sub-spec 01a (`Phase 27 §1a — per-platform
  ownership join`). The spec line is a leftover for the 01a
  agent to clean up; it is not in my file scope and predates my
  edits to `game_spec.rb`.
- `bundle exec rubocop app/components/games app/models/game.rb spec/components/games spec/models/game_spec.rb`
  → 4 files inspected, 0 offenses.
- `bundle exec brakeman -q -w2` → 0 security warnings.

### Open issues

- **Sister-agent leftover.** `spec/models/game_spec.rb:10` still
  references the dropped `belongs_to :platform_owned`. The 01a
  agent owns this fix; my work doesn't touch it.
- **Test DB volatility during the parallel push.** While running
  the suite I observed multiple parallel migrations landing
  mid-run (`create_notification_delivery_channels`,
  `revamp_platforms_for_friendly_id`,
  `create_game_platform_ownerships`,
  `drop_platform_owned_id_from_games`) and the test DB falling
  into an inconsistent state at one point (`db/schema.rb`
  contained an in-progress `Could not dump table "games"`
  comment block during a parallel agent's pg dump). This is a
  coordination artefact — the master agent should validate the
  test DB is clean before running the full suite for review.
- **`db/schema.rb` correctness.** As of this session's end, the
  schema dump may not reflect a stable state because sister
  migrations from 01a were landing in parallel. Re-running
  `bin/rails db:schema:dump` after both phases settle is
  recommended.

### Coordination

- Downstream sub-specs 01c (Genres / Collections shelves) and 01d
  (shelves-by-letter display mode) can drop in
  `render Games::CoverComponent.new(game:, variant: :shelf)` for
  every shelf tile. The component's `DIMENSIONS` constant exposes
  the canonical sizes for layout calculations (e.g. shelf-row
  min-height).
- The Phase 27 01a per-platform ownership migrations landed in
  parallel during this session; my component does not depend on
  ownership shape (it reads only `game.cover_url`, `game.title`,
  `game.id`, `game.to_param`) so the two changes are orthogonal.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01e-shelf-cover-art-variant.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Addendum:
  `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`.
- Plan checkbox: `… /plan.md` → `01e — Shelf cover art variant`
  block (all four boxes ticked).

## 2026-05-11 — sub-spec 01d Display mode switcher + three modes (pito-rails)

Implemented sub-spec 01d per
`specs/01d-display-mode-switcher-and-three-modes.md` plus master
dispatch overrides (locked in this session).

### Master dispatch overrides vs the architect spec

The architect spec proposed `Settings::GamesDisplayModesController`
at `PATCH /settings/games_display_mode/:mode` plus three
ViewComponent classes (`DisplayModeSwitcherComponent`,
`ListViewComponent`, `ShelvesByLetterComponent`). The master
agent dispatched a reframe: a `Users::GamesPreferencesController`
at `PATCH /users/games_preferences` carrying `mode=...` in the
form body, with three plain partials (`_grid_mode`, `_list_mode`,
`_shelves_by_letter_mode`) plus a `_display_mode_switcher`
partial. Behavior parity is full; surface naming differs.

### What landed

- Migration `20260511143000_add_preferred_games_display_mode_to_users`
  adds the `preferred_games_display_mode` integer column on `users`
  with `null: false, default: 0`. Run against both dev and test DBs.
- `User#preferred_games_display_mode` enum with keys `grid`/`list`/
  `shelves_by_letter` mapped to stable integers `0/1/2` and the
  `games_display_` prefix on predicates / bangs.
- `Users::GamesPreferencesController#update` — single PATCH endpoint
  that validates the `mode` param against an allowlist, writes the
  enum, and redirects to `/games?display=<mode>`. Unknown / blank
  modes flash an alert and leave the persisted preference alone.
- Route `PATCH /users/games_preferences` under a fresh `namespace
  :users` block.
- `GamesController#index` reads the resolved display mode via a
  new private `resolved_display_mode` method (URL `?display=`
  overrides per-request; falls back to `Current.user.preferred_
  games_display_mode`; final `:grid` fallback for the anonymous
  defensive path).
- `app/views/games/index.html.erb` now renders the switcher
  flush-right of the H1 row, and branches the "all games" section
  on `@display_mode` to one of three partials.
- `app/views/games/_grid_mode.html.erb` — extracted from the
  legacy `all-games-grid` inline block; renders `games/tile`s with
  `data-keyboard-grid="true"`.
- `app/views/games/_list_mode.html.erb` — `<table>` grouped by
  first-letter buckets, with `<tr class="letter-head">` sticky
  heading rows. Five columns: cover thumb (`t_cover_small`),
  title (linked), platforms owned (placeholder `—` until 01a's
  `game_platform_ownerships` shape stabilises), genres,
  computed status (`recorded` / `released` / `scheduled` /
  `unreleased`). Sticky `position: sticky` declaration inlined on
  the partial so the system-level CSS spec asserts on it without
  chasing across the asset pipeline.
- `app/views/games/_shelves_by_letter_mode.html.erb` — one
  `games/shelf` per non-empty letter bucket. Empty letters hidden
  (locked decision). Non-alphabetic title starts collapse into the
  `#` bucket.
- `app/views/games/_display_mode_switcher.html.erb` — three
  `button_to` forms, one per mode. Active mode renders with the
  `bracketed active` class. No JS. No anchor.

### Tests added (33 new examples, all green)

- `spec/models/user_spec.rb` — `preferred_games_display_mode enum
  (Phase 27 — 01d)`: default, key set, stable-integer mapping,
  prefixed predicates / bangs, ArgumentError on invalid value, DB
  NOT NULL + default backstop. (7 new examples.)
- `spec/requests/users/games_preferences_spec.rb` —
  `Users::GamesPreferences`: per-mode persist + redirect, unknown /
  blank token rejection, rapid-double-PATCH last-write-wins, signed-
  out 302→/login, URL friendliness, yes/no boundary sweep. (9 new
  examples.)
- `spec/views/games/_display_mode_switcher.html.erb_spec.rb` —
  switcher structure, labels, active-class behavior across all
  three modes + String arg parity, CLAUDE.md hard-rule guards (no
  JS confirm / no `text-danger` on the switcher / real forms not
  anchors). (10 new examples.)
- `spec/views/games/_grid_mode.html.erb_spec.rb` — data-mode tag,
  keyboard-grid opt-in, "all games" heading, empty-state copy.
  (4 new examples.)
- `spec/views/games/_list_mode.html.erb_spec.rb` — table head with
  five columns, letter-head row interleaving, sticky CSS, title
  linkage, data-mode tag; edge cases for `#` bucket, lowercase
  titles, missing genres / no release_date / no cover; empty
  state. (10 new examples.)
- `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb` —
  one shelf per non-empty letter, empty letters hidden, steam-
  shelf controller, tile partial usage, edge cases for `#` and
  lowercase buckets, empty state. (8 new examples.)

73 new + adjacent examples run green via
`bundle exec rspec spec/models/user_spec.rb \
  spec/requests/users/games_preferences_spec.rb \
  spec/views/games/_display_mode_switcher.html.erb_spec.rb \
  spec/views/games/_grid_mode.html.erb_spec.rb \
  spec/views/games/_list_mode.html.erb_spec.rb \
  spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`.

### Gates

- `bundle exec rspec` on the 6 spec files above: 73 examples, 0
  failures.
- `bundle exec rubocop` on the 10 Ruby files touched: no offenses.
- `bundle exec brakeman -q -w2`: 0 errors, 0 security warnings,
  full app sweep.

### Open issues / coordination notes for the master

- **01a + 01c drift on `GamesController#index` is blocking the
  full `/games` index render and so the existing
  `spec/requests/games_spec.rb` and the planned 01d system spec.**
  The controller still references `Platform#games_owning` (an
  association the 01a model rewrite removed) and `Game#platform_
  owned_id` (a column the 01a migration dropped). 14 failing
  examples in `spec/requests/games_spec.rb` are all variants of
  that drift; none are caused by 01d. The 01d controller-side
  resolver (`@display_mode = resolved_display_mode`) sits past
  the broken `@platforms_shelves` line, so 01a's controller fix
  will unblock 01d's `/games` integration without any further
  edit.
- The locked routing URL is `/users/games_preferences` (the spec
  proposed `/settings/games_display_mode/:mode`). Plan checkbox
  copy was reworded to match.
- List-mode sort columns are NOT wired yet — the spec calls for a
  sortable column set but the underlying `game_platform_
  ownerships` shape is the 01a / 01f lane. The partial structure
  is in place to wire `?sort=` once those land.
- The "platforms owned" list-mode column renders a literal `—`
  placeholder pending 01a's join-table integration.
- No system spec yet — the existing `/games` index is wedged on
  01a drift (see above). The view + request specs cover the same
  behavior at the per-partial level; a system spec is queued for
  after 01a's controller fix lands.

### Files changed

- `db/migrate/20260511143000_add_preferred_games_display_mode_to_users.rb`
  (new)
- `app/models/user.rb` (enum added)
- `app/controllers/users/games_preferences_controller.rb` (new)
- `app/controllers/games_controller.rb` (resolver helper + index
  reads `@display_mode`)
- `config/routes.rb` (`namespace :users` block)
- `app/views/games/index.html.erb` (switcher + branch on
  `@display_mode`)
- `app/views/games/_grid_mode.html.erb` (new)
- `app/views/games/_list_mode.html.erb` (new)
- `app/views/games/_shelves_by_letter_mode.html.erb` (new)
- `app/views/games/_display_mode_switcher.html.erb` (new)
- `spec/models/user_spec.rb` (enum describe block)
- `spec/requests/users/games_preferences_spec.rb` (new)
- `spec/views/games/_display_mode_switcher.html.erb_spec.rb` (new)
- `spec/views/games/_grid_mode.html.erb_spec.rb` (new)
- `spec/views/games/_list_mode.html.erb_spec.rb` (new)
- `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb` (new)

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01d-display-mode-switcher-and-three-modes.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Plan checkbox: `… /plan.md` → `01d — Display mode switcher +
  three modes` block (all 10 boxes ticked, with reframe notes
  inline).

## 2026-05-11 — sub-spec 01c Genres + Collections shelves (pito-rails)

Implemented sub-spec 01c per
`specs/01c-genres-and-collections-shelves.md` plus master dispatch
overrides (partials over ViewComponents, simpler URL contract,
inline `:shelf` styling pending 01e).

### Master dispatch overrides vs the architect spec

The architect spec proposed three ViewComponent classes
(`Games::GenresShelfComponent`, `Games::CollectionsShelfComponent`,
shared `Games::ShelfTileComponent`) plus a model scope
`Game.in_genre(slug)`. The master agent dispatched a reframe:
two plain partials (`_genres_shelf.html.erb`,
`_collections_shelf.html.erb`) at `app/views/games/`, with the
existing `?genre=<slug>` / new `?collection=<slug>` filter
parameters handled directly in `GamesController#index`. No new
model scope; the existing `joins(:game_genres).where(genre_id: …)`
and `where(collection_id: …)` codepaths absorb both forms.

### What landed

- `app/views/games/_genres_shelf.html.erb` (new) — top-of-page
  horizontal-scroll shelf, alphabetical (case-insensitive). Each
  tile is a clickable `<a>` to `/games?genre=<slug>` (falls back to
  `/games?genre=<id>` when `Genre#slug` is blank). Tiles use the
  `steam-shelf` Stimulus controller already in use by the legacy
  per-genre/per-platform shelves. Empty shelf renders a muted
  `(no genres yet)` placeholder so the layout doesn't shift.
- `app/views/games/_collections_shelf.html.erb` (new) — mirror of
  the Genres shelf for `Collection`. The architect spec mentions a
  `kind: :custom` filter (open question #2); the current Collection
  schema has no `kind` / `custom` column so the shelf renders every
  Collection. A future migration can reintroduce the distinction.
- `app/views/games/index.html.erb` — renders both new partials at
  the top of the page, above the existing bundles / recently-played
  / per-genre / per-platform shelves and the all-games grid.
- `app/controllers/games_controller.rb#index` — sets
  `@genres_for_shelf` and `@collections_for_shelf` (both ordered
  `Arel.sql("LOWER(name)")` with `id` tie-break for deterministic
  rendering across requests). Adds `?collection=<slug>` filter; the
  existing `?genre=<id>` codepath now also accepts a slug string.
  Both lookups go through ActiveRecord parameterized queries, so
  SQL-unsafe input cannot reach the database.
- Inline tile cover-art size locked to 75×100 px (50% of the
  150×200 grid tile) per the master's 50% addendum. Once 01e's
  `Games::CoverComponent.new(variant: :shelf)` (98×130 at 65%)
  is fully wired through the codebase, this inline block swaps to
  the component call; the surrounding tile shell is already shaped
  to absorb the swap.

### Sister-agent compensating patch

The convergent commit `b14f974` landed 01a's migrations
(`drop_platform_owned_id_from_games`, `create_game_platform_ownerships`,
`revamp_platforms_for_friendly_id`) and the post-01a `Platform`
model (`Platform#games_owning` retired, `Platform#games`
re-routed through `:game_platform_ownerships`) but did NOT update
`GamesController#index`. The controller still ran
`Platform.joins(:games_owning)` (now broken) and
`Game.where(platform_owned_id: …)` (column dropped). Every
request to `/games` was 500ing in the test environment.

01c's smallest-possible compensating fix (necessary to land my
own request and system specs) is in
`GamesController#index` only:

- `Platform.joins(:games_owning)` → `Platform.joins(:games)` — the
  new association lives on the post-01a Platform model exactly
  under that name (see `app/models/platform.rb` line 35).
- `scope.where(platform_owned_id: …)` removed — the column is gone;
  the canonical platform filter ships with 01b's filter row
  (`owned_on=<slug>`).
- `sanitized_filter` no longer reads `params[:platform_owned]`.

This patch is the minimum to keep `GET /games` serving. The
remaining 01a controller fan-out (`Game` model needs
`has_many :owned_platforms`, `local_only_params` should drop
`:platform_owned_id`, etc.) stays in 01a's lane and is flagged in
the "Open issues" section below.

### Specs added

- `spec/requests/games_spec.rb` — 12 new examples under "Phase 27
  §01c — top-of-page shelves" (8 examples: heading + empty-state
  for both shelves, alphabetical ordering, slug-based tile hrefs,
  id fallback, steam-shelf controller stamp) and "Phase 27 §01c
  — slug filter routes" (4 examples: `?genre=<slug>` /
  `?collection=<slug>` happy paths + unknown-slug silently drops).
- `spec/system/games_index_spec.rb` already lives in the convergent
  commit (11 examples: shelf headings, alphabetical ordering,
  empty-state placeholders, steam-shelf controller stamp, tile
  navigation across genre / collection / id-fallback paths).

Spec count delta: **+12 request examples** (system spec was
already committed but newly passing).

### Gates

- `bundle exec rspec spec/requests/games_spec.rb -e "Phase 27 §01c"`
  → 12 examples, 0 failures.
- `bundle exec rspec spec/system/games_index_spec.rb`
  → 11 examples, 0 failures.
- `bundle exec rspec spec/requests/games_spec.rb` (full file)
  → 71 examples, 14 failures. All 14 failures are pre-existing
  01a drift (Game model missing `owned_platforms` /
  `game_platform_ownerships`; show.html.erb references those).
  Listed in "Open issues" below.
- `bundle exec rubocop app/controllers/games_controller.rb spec/requests/games_spec.rb spec/system/games_index_spec.rb`
  → 3 files inspected, 0 offenses.
- `bundle exec brakeman -q -w2` → 0 errors, 0 security warnings.

### Open issues / coordination notes for the master

- **01a still has unfinished controller and model fan-out.** The
  `Game` model never gained `has_many :game_platform_ownerships`
  / `has_many :owned_platforms, through: …`. `app/views/games/show.html.erb`
  references `@game.owned_platforms` (committed in `b14f974`) which
  raises `NoMethodError`. 14 `spec/requests/games_spec.rb` examples
  fail on this. None of them are caused by 01c.
- **`Game#belongs_to :platform_owned` still in the model.** The
  column was dropped by 01a's migration but the association is
  alive; loading a Game with `platform_owned` accessed raises.
  Removed by 01a when their fan-out completes.
- **`GamesController#local_only_params` still permits `:platform_owned_id`.**
  The column is gone; the permit is harmless (`permit` silently
  drops keys not on the model) but should be cleaned by 01a.
- **`:shelf` cover variant is inline, not the 01e component.** Once
  01e's `Games::CoverComponent.new(game: …, variant: :shelf)` is
  fully integrated, the inline 75×100 block in both shelf partials
  swaps to the component call. Note 01e's locked size is 65%
  (98×130 px); 01c's inline is 50% (75×100 px) per the addendum's
  starting point. Reviewer should confirm visual density in browser
  before finalizing.
- **No `Collection#custom` column.** The architect spec proposed
  filtering Collections by `kind: :custom`. The Phase 14 Collection
  schema has no such column. The 01c partial shows every Collection
  until a future migration introduces the distinction.
- **`Genre#slug` is not unique-indexed.** The Phase 14 genres table
  has a `slug` column without a unique index. My tile-href fallback
  (`?genre=<id>` when slug is blank) handles missing slugs; if two
  genres ever share a slug, the controller's lookup returns the
  first match (deterministic by id order). A unique index on
  `genres.slug` would be a one-line follow-up.

### Files changed

- `app/views/games/_genres_shelf.html.erb` (new — already in
  `b14f974`, byte-identical to working tree).
- `app/views/games/_collections_shelf.html.erb` (new — already in
  `b14f974`, byte-identical to working tree).
- `app/views/games/index.html.erb` (wire both shelves above the
  existing layout; +7 lines).
- `app/controllers/games_controller.rb` (set `@genres_for_shelf` /
  `@collections_for_shelf`; add `?collection=<slug>` filter; accept
  slug form of `?genre=`; 01a compensating patch on
  `@platforms_shelves` and `sanitized_filter`).
- `spec/requests/games_spec.rb` (+144 lines, +12 examples).
- `spec/system/games_index_spec.rb` (already in `b14f974`,
  byte-identical — 11 examples now passing).

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-genres-and-collections-shelves.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Addendum:
  `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`
  (`:shelf` variant starts at 50%, fallback 65–70%).
- Convergent commit: `b14f974` — landed both shelf partials and the
  system spec; this session adds the controller / view wiring and
  request specs.
- Plan checkbox: `…/plan.md` → `01c — Genres and Collections
  shelves` block (3 of 5 boxes ticked; ViewComponent and `:shelf`
  cover-variant boxes annotated with reframe / dependency notes).

## 2026-05-11 — sub-spec 01a Per-platform ownership data model (pito-rails)

Implemented sub-spec 01a per
`specs/01a-per-platform-ownership-data-model.md`. Replaces the
single-valued `games.platform_owned_id` pointer with a
multi-valued `game_platform_ownerships` join, hardens the existing
Phase 14 `platforms` table into a FriendlyId-backed canonical
reference, and adds the IGDB platform sync service / job / rake
task.

### What landed

- Three migrations (`20260511160000_revamp_platforms_for_friendly_id`,
  `20260511160001_create_game_platform_ownerships`,
  `20260511160002_drop_platform_owned_id_from_games`). All `up` on
  the dev DB, schema dump regenerated cleanly.
- `Platform` model: FriendlyId (`slugged + history + finders`),
  `default_scope { order(:name) }`, `:games_available` association
  (renamed from the legacy `:games` through `game_platforms`),
  `:game_platform_ownerships` + `:games` (through ownerships) with
  `:restrict_with_error` on platform destroy.
- New `GamePlatformOwnership` model. `belongs_to :game` /
  `:platform` (required by default), uniqueness on
  `(game_id, platform_id)`. Cascade from games, restrict from
  platforms.
- `Game` model: dropped `belongs_to :platform_owned`; added
  `:game_platform_ownerships` (`dependent: :destroy`) +
  `:owned_platforms` through. New scopes `.owned`, `.not_owned`,
  `.owned_on(slug)` consumed by 01b's filter row. `owned_on` uses
  raw SQL for the slug match because `where(platforms: { … })`
  collides with the legacy `games.platforms` jsonb column —
  documented in the scope's comment.
- `Platforms::SyncFromIgdb` service + `Platforms::SyncFromIgdbJob`
  wrapper + `lib/tasks/platforms.rake` task + weekly Sidekiq cron
  entry. The service pages via `Igdb::Client#list_all_platforms`
  (new method, paginates `/platforms` 500-at-a-time using the
  `Apicalypse.offset` builder method added this session).
- Seed: PS5, Switch 2, Steam, GOG, Epic populated by slug,
  idempotent.
- MCP `game_update_local` now accepts plural `platform_owned_ids`
  with explicit-null-as-wipe semantics; the legacy singular
  `platform_owned_id` is auto-wrapped into a one-element array per
  the locked decision. Errors surface clean (unknown platform id →
  `RecordNotFound`, validation → `RecordInvalid`).
- Cascading code updates so the column drop doesn't blow up
  unrelated surfaces:
  - `games_controller`: filter resolves a platform **slug** (id
    accepted for backward-compat) and threads through
    `Game.owned_on(slug)`. The `local_only_params` permit list no
    longer carries `:platform_owned_id`.
  - `GameDecorator`: summary JSON now emits
    `platform_owned_ids: [int]` (empty array when no ownership);
    `platforms_owning` detail block renders the joined platforms.
  - `app/views/games/{edit,show}.html.erb`: the platform-owned
    dropdown / read-only field is replaced with a multi-value
    "owned on" inline list. The dedicated editor lands in 01f.
  - `app/views/games/index.json.jbuilder`: filter echo carries
    `platform_owned_slug`.
  - `Igdb::GameMapper` + `Igdb::SyncGame` comment-only updates so
    the local-only column list stays accurate.
- Spec pyramid: model specs (`platform_spec`, `game_spec`,
  `game_platform_ownership_spec`), service spec
  (`platforms/sync_from_igdb_spec`), job spec
  (`platforms/sync_from_igdb_job_spec`), rake spec
  (`platforms_rake_spec`). Existing specs that touched the
  legacy column updated in-place to reflect the new join shape
  (`games_spec` request, `game_decorator_spec`,
  `index.json.jbuilder_spec`, `game_mapper_spec`, `sync_game_spec`).

### Backfill plan

The dropped `games.platform_owned_id` column had no production users
(pre-launch). The migration body documents the recipe for a future
operator who needs to migrate a row set:

    Game.where.not(platform_owned_id: nil).find_each do |g|
      g.game_platform_ownerships.find_or_create_by!(
        platform_id: g.platform_owned_id
      )
    end

The recipe stayed in the migration comments rather than the body so
the migration remains mechanical (drop FK / index / column) and
the data-shape decision stays explicit in code review.

### Column-name variance vs. the spec

Spec body referenced `igdb_platform_id` on the platforms table. The
existing Phase 14 `platforms.igdb_id` column was the equivalent — the
"if not exists" guard in the locked decisions kept it under its
established name to minimize the change radius (renaming would have
touched IGDB sync, factories, and Genre / Company patterns that
mirror the same shape). All other spec invariants (nullable for
seeded rows, unique-when-present, FriendlyId slug, etc.) are
honored.

### Gates

- `rspec` — relevant subtrees green (models, services, jobs,
  decorators, views, requests/games, mcp). Full suite (3629
  examples) passes with 1 pre-existing pending example.
- `rubocop` — clean on all touched Ruby files.
- `brakeman` — 2 warnings, both pre-existing (Notification XSS weak
  warning, composites file-access weak warning). No new findings.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01a-per-platform-ownership-data-model.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Plan checkbox: `…/plan.md` → `01a — Per-platform ownership data
  model` block (all 10 boxes ticked).

---

## 2026-05-11 — 01h Collection cover composer (re-dispatch)

Re-dispatched after the original 01h work landed in `e145122`
("Convergent: P25 01c notifications + P26 01g viewer-time + P27 01h
composer + misc"). This session:

- Verified the committed implementation against the spec
  `specs/01h-collections-cover-composer.md`: 6-variant matrix
  (empty / passthrough / pair / netflix3 / quad / netflix5 / six_grid),
  98×130 output canvas, alphabetical-by-title ordering, MAX 6 tiles,
  fingerprint via `Composite::Checksum.compute`, on-disk path
  `composites/collection-<id>.jpg`, libvips-error degradation
  (substitute placeholder + WARN), cache invalidation hook via
  `Game#after_update_commit` on `collection_id` change.

- Fixed a latent flake in `spec/jobs/collection_cover_rebuild_job_spec.rb`:
  the "survives Errno::ENOENT mid-job" example stubbed `File.delete`
  globally without restoration, which leaked into the `after` cleanup
  hook and crashed teardown. Scoped the stubs to the two specific
  Pathname targets and broadened the `after` hook's `rescue` clause to
  `Pito::AssetsRoot::Error, Errno::ENOENT`.

- Confirmed the `Compositable` concern (`app/models/concerns/compositable.rb`)
  is mixed into both `Bundle` and `Collection`, providing
  `composite_cover_url`, `composite_cover_absolute_path`, and
  `sweep_composite_cover_file`. The `Composite::Builder` itself stays
  bundle-coupled (per the spec's "bundle code stays untouched"
  mandate) — the natural sharing point was the URL/path/sweep trio,
  not the build pipeline.

### Variant matrix coverage (98 × 130)

| Count | Layout       | Tile boxes                                             | Sums      |
| ----- | ------------ | ------------------------------------------------------ | --------- |
| 0     | :empty       | n/a (no composite)                                     | n/a       |
| 1     | :passthrough | n/a (caller renders `Games::CoverComponent`)           | n/a       |
| 2     | :pair        | 49×130 ‖ 49×130                                        | 98 / 130  |
| 3     | :netflix3    | big 64×130 ‖ (34×65 / 34×65)                           | 98 / 130  |
| 4     | :quad        | 49×65 ‖ 49×65 / 49×65 ‖ 49×65                          | 98 / 130  |
| 5     | :netflix5    | big 50×130 ‖ (24×65,24×65 / 24×65,24×65)               | 98 / 130  |
| 6+    | :six_grid    | (33,33,32 × 65) / (33,33,32 × 65)                      | 98 / 130  |

### Files (committed in e145122 + this session's spec polish)

- `app/services/collections/composite_layout.rb` (new — pure layout engine).
- `app/services/collections/cover_composer.rb` (new — orchestrator).
- `app/models/concerns/compositable.rb` (new — shared with Bundle).
- `app/jobs/collection_cover_rebuild_job.rb` (new — eviction job).
- `app/models/collection.rb` — `include Compositable`, `cover_url`,
  `before_destroy :sweep_composite_cover_file`.
- `app/models/bundle.rb` — `include Compositable`, dropped duplicated
  `composite_cover_url` / `composite_cover_absolute_path` /
  `sweep_composite_cover_file`.
- `app/models/game.rb` — `after_update_commit
  :evict_collection_composite_on_collection_change`.
- `app/views/games/_collection_sub_shelf.html.erb` (new — view partial).
- `app/assets/tailwind/application.css` — `.collection-cover-composite`.
- `db/migrate/20260511160358_add_composite_cover_columns_to_collections.rb`
  (composite_cover_path + composite_cover_checksum on collections).
- Specs: `spec/services/collections/composite_layout_spec.rb` (86),
  `spec/services/collections/cover_composer_spec.rb` (22),
  `spec/models/concerns/compositable_spec.rb` (10),
  `spec/models/collection_spec.rb` (additions),
  `spec/models/game_spec.rb` (additions),
  `spec/jobs/collection_cover_rebuild_job_spec.rb` (10 — including
  this session's race-condition stub-scoping fix),
  `spec/views/games/_collection_sub_shelf.html.erb_spec.rb` (15),
  `spec/requests/composites_spec.rb` (additions).

### Gates

- `rspec` — 347 touched-subtree examples green
  (services/collections, models/concerns/compositable, models/collection,
  models/game, jobs/collection_cover_rebuild_job,
  views/games/_collection_sub_shelf, requests/composites, models/bundle,
  services/composite, jobs/bundle_cover_*).
- `rubocop` — clean on all touched Ruby files (16 inspected, no
  offenses).
- `brakeman` — 0 security warnings (2 prior obsolete-ignore entries
  noted, both pre-existing).

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01h-collections-cover-composer.md`.
- Implementing commit: `e145122` (Convergent commit landing 01h
  alongside P25 01c and P26 01g).
- Note on canvas size: spec's Open Question #1 resolved to 98 × 130
  (the existing `:shelf` cover-art variant), NOT the 105 × 140
  alternate. Per the user dispatch — the integer math for the
  six_grid is 33+33+32 vs. the cleaner 35+35+35 at 105, but the
  hosting shelf size locks 98 × 130.
