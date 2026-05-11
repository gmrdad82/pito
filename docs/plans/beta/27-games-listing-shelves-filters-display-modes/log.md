# Phase 27 — log

## [skipci] 2026-05-11 — sub-spec 01d re-dispatch — controller wire-up + system spec (pito-rails)

Closed the loop on sub-spec 01d. The original 01d session landed the
migration, the `User` enum, the `Users::GamesPreferencesController`, three
mode partials (`_grid_mode`, `_list_mode`, `_shelves_by_letter_mode`), the
switcher partial, and the per-partial view specs. The `GamesController#index`
wire-up and the matching system spec were deferred at that time because the
controller was wedged on 01a (`Platform#games_owning` association removal) +
01c (per-platform `games.platform_owned_id` column drop) drift. Both have
since cleared via the 01a controller fix and the 01c-v2 nested-shelves
rewrite, so this re-dispatch ties the surface together.

### What landed

- `GamesController#index` now sets `@display_mode = resolved_display_mode`.
  The new private helper resolves the requested mode in order: URL
  `params[:display]` (allowlisted set `grid` / `list` / `shelves` /
  `shelves_by_letter`) → `Current.user.preferred_games_display_mode` →
  `:grid` as the defensive final fallback for the anonymous path.
  `shelves` is a URL-friendly alias for the canonical enum key
  `shelves_by_letter` per the spec.
- `app/views/games/index.html.erb` now renders
  `games/_display_mode_switcher` flush-right of the H1 row (inside the
  existing `display: flex` header with `margin-left: auto;`) and branches
  the all-games partition on `@display_mode` to one of the three partials.
  The legacy inline `<section class="shelf all-games-grid">` block is
  gone — its tile-grid content moved into `_grid_mode` during the original
  01d session.
- `spec/system/games_display_modes_spec.rb` — 13 new Capybara examples on
  the rack_test driver: default-mode grid for a fresh user, switcher
  active-class marking, persistence flow (click `[list]` → preference
  written + list mode renders → reload preserves the choice), `[grid]`
  round-trip from a non-default persisted preference, URL `?display=`
  override does NOT persist the choice, `?display=shelves` alias maps to
  `shelves_by_letter`, list mode renders `tr.letter-head` rows + title
  links, shelves-by-letter mode renders one shelf per non-empty letter
  and hides the others, composition with the `?filters=` set (clear-all
  preserves `?display=`), CLAUDE.md hard-rule guards (no
  `data-turbo-confirm`, no `window.confirm`, no anchors — three
  `<form>` elements per switcher).
- `spec/requests/games_spec.rb` — 12 new `Phase 27 §01d` examples on the
  request layer mirroring the system surface: default → grid, URL
  override per mode (`grid` / `list` / `shelves` / `shelves_by_letter`),
  persisted preference wins when `?display` is absent, override wins
  over persistence for one request, garbage values fall back to the
  persistence, post-PATCH the next `GET /games` reflects the saved
  mode, switcher button text + action URL, active-class assertion,
  filter-row composition. Scopes the `data-display-mode` matcher to
  the all-games `<section>` so the switcher's own button-level
  `data-display-mode` attributes don't contaminate the match.
- `spec/requests/games_spec.rb` (01b regression) — the 01b contradiction
  notice spec's regex used the literal `<section class="shelf all-games-grid">`
  class string; the new `_grid_mode` partial adds a `games-grid-mode`
  class. Switched to `<section[^>]*data-display-mode="grid"` (the stable
  hook the view spec also asserts on).

### Tests

- 13 new system + 12 new request = 25 new examples, all green.
- Full 01d-adjacent sweep (model + request + view + system specs across
  `user`, `users::games_preferences`, every `games/_*_mode` partial,
  switcher, the full `spec/requests/games_spec.rb`, `games_index`,
  `games_steam_shelf`, `games_platform_ownerships`, the new
  `games_display_modes`): 365 examples, 0 failures.
- Rubocop on the touched Ruby files (`games_controller.rb`,
  `spec/requests/games_spec.rb`, `spec/system/games_display_modes_spec.rb`):
  no offenses. (`index.html.erb` skipped — rubocop's Ruby parser misreads
  ERB control flow as a ternary expression; the file is not Ruby.)
- Brakeman `-q -w2`: 0 warnings, 0 errors across the full app.

### Files changed

- `app/controllers/games_controller.rb` (added `@display_mode = resolved_display_mode`
  to `#index` and private `resolved_display_mode` resolver)
- `app/views/games/index.html.erb` (renders `_display_mode_switcher`,
  branches the all-games partition on `@display_mode`)
- `spec/requests/games_spec.rb` (added 12-example `display mode resolution
  (Phase 27 §01d)` describe block; updated one 01b regex to the stable
  `data-display-mode` hook)
- `spec/system/games_display_modes_spec.rb` (new, 13 examples)
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
  (reworded the trailing 01d checkbox to reflect the system spec landing)

### Open notes

- The list-mode "platforms owned" column still renders a literal `—`
  pending the 01a join-table integration wired into the partial. That
  cleanup remains queued and is independent of this re-dispatch.
- Sort-column UI for list mode (`?sort=title|platforms_owned|genres|status`)
  is still deferred until the per-platform ownership shape stabilises
  for sorting. The partial's letter-bucketing + sticky heading layout is
  in place for the sort hookup.
- The 29 unrelated failures observed in the wider request + system sweep
  (`sessions_spec`, `sessions_rate_limit_spec`, `login/totp_challenges_spec`,
  `settings/security/blocks/unblockings_spec`,
  `calendar_edit_delete_spec`, `settings/tokens_spec`,
  `video_import_flow_spec`) are entirely from other concurrent in-flight
  agents' work in the worktree (TOTP / rack_attack / sessions / video
  import surfaces) and do not touch the 01d surface.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01d-display-mode-switcher-and-three-modes.md`.
- Prior 01d log entry: `## 2026-05-11 — sub-spec 01d Display mode switcher +
  three modes (pito-rails)` below.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.

---

## [skipci] 2026-05-11 — sub-spec 01e Shelf cover art variant (pito-rails)

Closed the loop on the `:shelf` cover-art variant. The component, partials,
and 34-example component spec already shipped under earlier 01e / 01c-v2
work at the locked 65% size (98 × 130 against the real 150 × 200 grid,
sourced from IGDB's `t_cover_small_2x` token). This pass tied off the
remaining loose ends:

- **Stylesheet rules for the variant slot.** Added a `.game-cover` /
  `.game-cover--grid` / `.game-cover--shelf` / `.game-cover-img` /
  `.game-cover-missing` block in `app/assets/tailwind/application.css`,
  immediately before the existing 01h `.collection-cover-composite` rule.
  These descriptive class rules pin the locked variant dimensions (150 × 200
  for `:grid`, 98 × 130 for `:shelf`) at the stylesheet level so the slot
  size is reachable without external inline-style introspection. No
  `transform: scale`, no percentage widths — both variants resolve to a
  server-side asset at its native size per the 01e Flaw assertions.
- **Component-spec coverage of the `:shelf` symmetry.** Added four
  assertions to `cover_component_spec.rb` so the `:shelf` happy block now
  mirrors `:grid`: alt text equals the game title, `loading="lazy"`,
  wrapper inline `width: 98px; height: 130px;`, and the wrapper `class`
  attribute is exactly `"game-cover game-cover--shelf"`. The component file
  itself needed no behavioral change.
- **01c-v2 spec inconsistency correction.** `01c-v2-nested-shelves.md`
  carried an in-flight 70% / 105 × 140 draft that proposed bumping the
  variant. The master agent reaffirmed 65% (matching 01e and the shipped
  `Games::CoverComponent`). Prepended a one-line "Corrected from 70%
  draft — locked decision §1 is 65% (98 × 130 px against the real
  150 × 200 grid)" annotation at the top of the spec body. The 70% / 105 ×
  140 mentions inside the spec stay as historical record but are now
  explicitly tagged as superseded.

### Spec deltas

- `spec/components/games/cover_component_spec.rb` — 34 → 38 examples, all
  green. New assertions: alt text on `:shelf`, loading=lazy on `:shelf`,
  inline width/height on `:shelf` wrapper, exact wrapper class string.

### Files touched

- `app/assets/tailwind/application.css` — added `.game-cover` /
  `.game-cover--{grid,shelf}` / `.game-cover-img` / `.game-cover-missing`
  CSS block.
- `spec/components/games/cover_component_spec.rb` — +4 examples.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-v2-nested-shelves.md`
  — prepended one-line correction header.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
  — ticked the four 01e checkboxes with implementation notes.

### Open issues

None. The `:shelf` variant landing was already complete at the component
level; this pass landed the stylesheet rules and tightened the spec
coverage so future drift is caught.

### Cross-stack

- Rails web — covered.
- Rails MCP — N/A (MCP does not render images).
- `pito` CLI — N/A (TUI does not render images).
- Website — N/A.

### Verification

- `bundle exec rspec spec/components/games/cover_component_spec.rb` — 38
  examples, 0 failures.
- `bundle exec rubocop` on touched files — clean.

---

## [skipci] 2026-05-11 — sub-spec 01c-v2 Nested shelves (pito-rails)

Rewrote `/games` top-of-page shelves from the v1 flat-tile design (one tile
per genre, one tile per collection) to v2 nested shelves: each outer shelf
iterates one sub-shelf per non-empty bucket; each sub-shelf is a
horizontally-scrolling row of game tiles at the `:shelf` cover variant
(`Games::CoverComponent.new(game:, variant: :shelf)`). Collection sub-shelves
additionally lead with the existing 01h composite cover tile.

Empty buckets are now hidden end-to-end. When no genre owns any game, the
Genres `<section>` is suppressed (no `<h2>`, no muted "(no genres yet)"
placeholder). Same rule for Collections. This reverses 01c-v1's "always
render with placeholder" pattern per 01c-v2 locked decision #7.

### Scope ladder (in this pass)

In scope:

- Rewrite `_genres_shelf.html.erb` and `_collections_shelf.html.erb` to the
  nested outer-shelf shape.
- New `_genre_sub_shelf.html.erb` + `_collection_sub_shelf_row.html.erb`
  partials for the per-bucket sub-shelf rows.
- Controller scope change on `@genres_for_shelf` / `@collections_for_shelf`
  to filter out empty buckets and preserve alphabetical case-insensitive
  ordering with a stable id tiebreak.
- View + request + system spec rewrites under the existing 01c describe
  blocks.

Deferred (queued follow-ups from the 01c-v2 spec body that remain unshipped):

- `db/migrate/*_add_primary_genre_id_to_games.rb` (per parent dispatch — "no
  new migrations"). Falls back to the existing `genre.games` join — a
  multi-genre game appears in every sub-shelf its `game_genres` join touches.
  Architect-locked behavior is "appears in exactly one bucket via primary
  genre pointer"; the fallback is documented and the migration is queued
  separately.
- `db/migrate/*_add_composite_columns_to_collections.rb` — already shipped
  under 01h. No-op here.
- `Game#primary_genre` association, `Genre#primary_for_games`, orphaning
  rule on `GameGenre#after_destroy_commit`. Gated on the migration above.
- Game show / edit primary-genre picker. Gated on the migration.
- `Composite::Builder` refactor to accept any `Compositable` host. Bundle
  stays bundle-coupled per the 01h log's "bundle code stays untouched"
  note; the refactor is a separate follow-up.
- `Games::CoverComponent` `:shelf` variant size bump from 98×130 to
  105×140 (70% of grid). Per parent dispatch — that surface belongs to
  01e (`01e-shelf-cover-art-variant.md` /
  `01e-v2-shelf-cover-art-variant.md`).

### Naming collision (resolved)

01c-v2 spec pre-reserved `app/views/games/_collection_sub_shelf.html.erb`
for the row partial. 01h shipped first and took that filename for the
leading-tile partial (single composite cover with three branches: empty /
passthrough / composite). Both surfaces are needed; renaming the existing
01h partial would invalidate 14 view specs and the 01h log.

Resolution: new row partial is `_collection_sub_shelf_row.html.erb`. The
row partial wraps the 01h leading-tile partial inside an anchor that
navigates to `/collections/<slug>`, then iterates game tiles. Both
partials are documented at the top of each file.

### Files changed

App:

- `app/controllers/games_controller.rb` — `@genres_for_shelf` /
  `@collections_for_shelf` filter to non-empty buckets via subquery
  (Postgres `SELECT DISTINCT` + `ORDER BY` workaround). Inline comment
  block reworked for v2.
- `app/views/games/index.html.erb` — comment block updated for v2;
  partial call sites unchanged.
- `app/views/games/_genres_shelf.html.erb` — REWRITE. Outer shelf
  `<section data-shelf="outer-genres">` with one `<h2>genres</h2>` and
  per-genre sub-shelves; entire section suppressed when input empty.
- `app/views/games/_collections_shelf.html.erb` — REWRITE. Outer shelf
  with `<h2>custom collections</h2>` and per-collection sub-shelves.
- `app/views/games/_genre_sub_shelf.html.erb` — NEW. Sub-shelf with
  `<h3>` heading + `[see all]` link (only over the 30 cap) +
  horizontally-scrolling row of `:shelf` game tiles, alphabetical.
- `app/views/games/_collection_sub_shelf_row.html.erb` — NEW. Mirror of
  the genre sub-shelf with a leading composite cover tile.

Specs:

- `spec/views/games/_genres_shelf.html.erb_spec.rb` — REWRITE. 14 new
  examples covering outer-shelf wrapper, per-genre sub-shelf count,
  short-form `<h3>` mapping, empty-input hidden, no v1 remnants.
- `spec/views/games/_collections_shelf.html.erb_spec.rb` — NEW. 11
  examples mirroring the genre coverage.
- `spec/views/games/_genre_sub_shelf.html.erb_spec.rb` — NEW. 18
  examples covering happy (under cap), exact cap (30), over cap (31 →
  capped + `[see all]`), empty genre, JS-confirm flaw guard.
- `spec/views/games/_collection_sub_shelf_row.html.erb_spec.rb` — NEW.
  15 examples covering composite leading tile, passthrough leading
  tile (1-game collection), empty leading tile (0-game collection), 31
  games over cap, JS-confirm flaw guard.
- `spec/requests/games_spec.rb` — REWROTE the "Phase 27 §01c" describe
  block. 11 new examples covering outer-shelf hidden when empty,
  outer-shelf rendered with sub-shelf-per-bucket alphabetical, the
  `data-shelf="genre-sub"` / `"collection-sub"` data hooks, `[see all]`
  cap behavior.
- `spec/system/games_index_spec.rb` — REWROTE the 01c describe block.
  5 new examples covering nested shelf rendering, empty-bucket hidden,
  `[see all]` navigation narrowing the all-games grid below.

Plan:

- `docs/plans/beta/27-…/plan.md` — re-ticked the 01c block's five
  checkboxes with v2-aware annotations; documented the deferred work
  inline.

### Gates

- `rspec spec/views/games/ spec/components/games/ spec/requests/games_spec.rb spec/system/games_index_spec.rb spec/system/games_steam_shelf_spec.rb spec/system/games_platform_ownerships_spec.rb` — 833 examples green.
- `rspec spec/models/genre_spec.rb spec/models/collection_spec.rb spec/models/game_spec.rb` — 113 examples green.
- `rubocop` on touched Ruby files — clean (7 files inspected, no offenses).
- `brakeman -q -w2` — 0 security warnings.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-v2-nested-shelves.md`
  (supersedes 01c-v1; this implementation pass).
- Plan checkbox: `…/plan.md` → `01c — Genres and Collections shelves`
  block (five v1 checkboxes re-ticked with v2 annotations).
- Adjacent: 01h leading-tile partial (`_collection_sub_shelf.html.erb`)
  reused as-is; 01b filter row placement preserved; 01e cover variant
  width left to its own surface.

---

## [skipci] 2026-05-11 — sub-spec 01b Filter row + platform semantics (pito-rails)

Shipped the multi-select filter row on `/games`. State lives in a single
CSV URL param (`?filters=token1,token2`). Ten canonical chips in a
locked left-to-right order:

    [recorded] [released] [owned] [not owned] [scheduled]
    [ps5] [switch2] [steam] [gog] [epic]

Clicking a chip toggles it in or out of the comma-separated set;
`[clear all]` appears whenever at least one chip is active; a muted
notice renders when `owned` + `not_owned` are simultaneously active
(the C-3 contradiction case). Chip hrefs preserve `?genre=`,
`?collection=`, and `?display=` overrides verbatim.

### Locked semantics

Platform-token precedence follows the verbatim Mobile directive
(spec §"Locked semantics"):

- **P-1.** `owned` unchecked + platform-X checked → games scheduled OR
  released on platform-X, regardless of ownership state.
- **P-2.** `owned` checked + platform-X checked → games owned
  specifically on platform-X.
- **C-1.** `not_owned` checked + platform-X checked → games with zero
  ownership rows AND released-or-scheduled on platform-X.
- **C-2.** Multiple platform tokens within the same bucket OR together
  (statement applies per bucket state).
- **C-3.** `owned` + `not_owned` together → `Game.none` + a muted
  contradiction notice. No JS dialog, no red.

The query object's `#contradiction?` predicate flags the C-3 case;
`#results` short-circuits to `Game.none`.

### Files (new)

- `app/queries/games/filter.rb` — `Games::Filter` query object.
  Public surface: `#results` (memoised `ActiveRecord::Relation`),
  `#active_tokens`, `#dropped_tokens`, `#contradiction?`. Composition
  algorithm in `#build_results` partitions tokens into Status /
  Ownership / Platform / Unknown; buckets AND together; Status and
  Platform tokens within a bucket OR together. Platform-bucket
  semantics flip on the Ownership-bucket state via `platform_relation_for`.
- `app/helpers/games/filters_helper.rb` — `Games::FiltersHelper`
  mixin. Surface: `parse_filter_tokens(raw)`, `parse_dropped_tokens(raw)`,
  `toggle_filter(active, token)`, `chip_label(token)`. Normalises
  CSV / Array / nil; downcases; strips; de-dupes; preserves input order.
- `app/components/games/filter_row_component.rb` +
  `app/components/games/filter_row_component.html.erb` — ten chips,
  `[clear all]` link, optional contradiction notice.
  `query_string_overrides` preserves the URL state the filter row
  doesn't own.
- `app/components/games/filter_chip_component.rb` +
  `app/components/games/filter_chip_component.html.erb` — single
  bracketed-link chip. ArgumentError when token is non-canonical or
  `request_path` is blank. Active chips carry the `chip--active`
  modifier (no red — red is reserved for destructive).
- Specs (all new):
  - `spec/queries/games/filter_spec.rb` (50 examples) — load-bearing
    matrix: single-token, single-platform-per-ownership-state,
    Mobile-directive worked example (verbatim), multi-platform,
    status combinations, contradiction, normalisation edge cases,
    defensive surface (SQL injection, 100-token input, memoisation,
    composability).
  - `spec/helpers/games/filters_helper_spec.rb` (21 examples).
  - `spec/components/games/filter_chip_component_spec.rb` (17 examples).
  - `spec/components/games/filter_row_component_spec.rb` (18 examples).

### Files (modified)

- `app/models/game.rb` — six new scopes: `.recorded` (rides on
  `VideoGameLink.select(:game_id).distinct` since `videos` connects
  via the join, not directly), `.released`, `.scheduled`,
  `.on_platform(slug)`, `.released_on(slug)`, `.scheduled_on(slug)`.
  The on_platform shape mirrors the `owned_on` pattern with bound
  parameters and the `"platforms"."slug" = ?` literal so the legacy
  `games.platforms` jsonb column doesn't collide.
- `app/controllers/games_controller.rb` — `include Games::FiltersHelper`;
  `#index` reads `params[:filters]` via the helper, instantiates
  `Games::Filter`, narrows `@all_games`, exposes `@filter_contradiction`
  to the view. Compose order: `?genre=` → `?collection=` → filter row.
- `app/views/games/index.html.erb` — renders the filter row between
  the 01c shelves (Genres + Collections) and the all-games grid,
  with `query_string_overrides` carrying `{ genre:, collection:, display: }`.
- `spec/models/game_spec.rb` — 16 new examples covering all six new
  scopes (`recorded`, `released`, `scheduled`, `on_platform`,
  `released_on`, `scheduled_on`) including boundary inclusive-on-today,
  SQL-injection defense, distinct-row defense, nil-date exclusion.
- `spec/requests/games_spec.rb` — 16 new examples in
  `describe "GET /games with ?filters="`: happy paths, contradiction,
  unknown-token dropping (no echo-back), de-duplication, case
  normalisation, 100-token, SQL injection, defensive `data-turbo-confirm`
  absence, query-string preservation for `display=` and `genre=`.
- `spec/system/games_index_spec.rb` — 11 new examples in
  `describe "Games index — filter row (01b)"`: click-through chip
  toggle, `[clear all]` lifecycle, chip composition, contradiction
  rendering, query-string preservation, all-five-platforms union,
  defensive HTML surface.

### Spec deviations from spec text (resolved)

1. **`first_release_date` → `release_date`.** The spec wrote
   `first_release_date` as the IGDB-derived datetime column. The
   actual Phase 14 §1 schema column is `release_date` (a `date`).
   The day-granular semantics are identical (a release scheduled for
   today is "released"; tomorrow is "scheduled"); the model code,
   model specs, and the matrix all use `release_date`.
2. **`Game.recorded` ride-on.** Spec wrote
   `where(id: Video.select(:game_id).distinct)`. The actual
   association is `has_many :videos, through: :video_game_links`
   (Phase 14 §3) — Video has no `game_id` column. The scope rides on
   `VideoGameLink.select(:game_id).distinct` instead; semantically
   identical (any linked Video → recorded).
3. **Boundary inclusive on today.** `release_date == Date.current` is
   in `released`, not `scheduled`. Date-granular makes the
   "exactly now" second-level edge case from the spec moot.

### Open questions (architect-resolved per autonomy/cadence rule)

The spec lists six open questions; locked answers below.

1. **C-1 `not_owned` + platform-X semantics** — adopted the spec's
   locked default: zero ownership rows AND released-or-scheduled on
   the platform. Matrix asserts: `[not_owned, ps5] → B` (B is on PS5,
   not owned anywhere); `[not_owned, epic] → ∅` (G is owned on Epic;
   nothing else is on Epic).
2. **C-3 contradiction rendering** — muted notice (locked default).
   Class is `text-muted` on a `<p>` directly below the chip row.
   Reviewed against the project rule: no red, no JS dialog.
3. **`recorded` semantics with draft Videos** — any linked Video
   record. The project has no `published` state on `Video` yet;
   revisit when video publication state lands.
4. **Boundary inclusiveness on `released`** — locked: today's release
   counts as released, not scheduled (`<= Date.current`).
5. **`platforms_available` association name** — confirmed still
   `platforms_available` (Phase 14 §1; 01a did not rename it). The
   `on_platform` scope rides on `:game_platforms → :platform` (the
   same association under the hood) so the legacy join name doesn't
   leak into the scope shape.
6. **Multi-platform OR shape** — chose the `where(id: union_ids)`
   single-pass form; the alternative `.or` shape would generate the
   same result. Spec asserts equivalence rather than SQL fingerprint;
   16 matrix cells assert the right ids land regardless.

### Gates

- `rspec` — 303 examples across the seven touched spec files; 0
  failures. (16 model + 50 query + 21 helper + 17 chip + 18 row + 87
  request + 22 system + 72 other component / model specs in the
  re-run convergence.)
- `rubocop` — clean on all 13 touched Ruby files. (The .erb files
  aren't passed to rubocop — its Ruby parser doesn't handle them.)
- `brakeman` — 0 security warnings (2 prior obsolete-ignore entries
  noted, both pre-existing). Bound parameters in the new
  `on_platform` / `released_on` / `scheduled_on` scopes and in the
  controller's `parse_filter_tokens` path keep the surface clean.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01b-filter-row-and-platform-semantics.md`.
- Plan checkbox: `…/plan.md` → `01b — Filter row + platform semantics`
  block (all 7 boxes ticked).
- Compose order locked by spec §"Controller integration": genre →
  collection → filter row → display-mode partition (01d).

---

## [skipci] 2026-05-11 — sub-spec 01g MCP `game_update_local` plural ownership (pito-mcp-impl)

Implemented the MCP half of sub-spec 01g — extending the existing
`game_update_local` tool to match the spec's plural ownership contract end to
end, plus the structured `warning` field for legacy / conflict callers. The
pre-existing implementation already accepted `platform_owned_ids: [int]`, the
singular auto-wrap, and the `confirm: yes/no` two-step; this session aligned the
remaining edge-case behavior and broadened spec coverage to the architect's full
pyramid sweep.

### MCP `game_update_local` contract changes

- Unknown `platform_id` values are now DROPPED with a structured `warning` field
  (`"unknown platform_id(s) dropped: …"`) instead of raising a 422. Mirrors the
  spec's "graceful drop, not hard error" rule.
- When BOTH `platform_owned_id` (singular legacy) and `platform_owned_ids`
  (plural) are supplied, the plural form wins and the response carries a
  `warning` (`"both ... supplied; plural wins."`). The preview path
  (`confirm: no`) emits the same warning so callers can spot the conflict before
  they commit.
- `platform_owned_id: null` is now treated as a NO-OP per the spec's back-compat
  note — legacy callers that send `null` to mean "don't touch ownership" no
  longer accidentally un-own a game. Sending `platform_owned_ids: []` (explicit
  empty array) remains the authoritative way to un-own everywhere.
- Response payload gained `platform_owned_id` (singular, equal to the first
  element of the plural array) as a one-phase back-compat field. Removed next
  phase per the spec's deprecation window.
- `sync_ownerships!` no longer pre-validates platform existence — the outer
  `call` does that and drops unknown ids before reaching the upsert. Idempotency
  on existing ownership rows (`acquired_at` / `store` / `notes`) is preserved by
  a covering spec.

### Files changed

- `app/mcp/tools/game_update_local.rb` — input normalization rewrite for
  plural-vs-singular precedence, unknown-id drop with warning, preview /
  response `warning` field, response back-compat singular, doc comment + schema
  description alignment with §01g.
- `spec/mcp/tools/game_update_local_spec.rb` — expanded from 6 examples to 21
  (full §01g pyramid sweep: happy paths for plural / singular / shrink / un-own
  / de-dup / idempotency preservation; sad paths for unknown id + mixed-form
  conflict + preview-warning carry; edge paths for `singular: null` no-op +
  absent-keys no-op + only-bad-ids; flaw paths for transaction rollback +
  mass-assignment guard).

### Test deltas

- `bundle exec rspec spec/mcp/tools/game_update_local_spec.rb` → 21 examples, 0
  failures (was 6 examples, 0 failures).
- `bundle exec rspec spec/mcp/tools/` → 493 examples, 0 failures (full MCP tool
  suite green).
- `bundle exec rspec spec/models/game_platform_ownership_spec.rb spec/models/game_spec.rb`
  → 102 examples, 0 failures (no regression in §1a's model surface).
- `bundle exec rubocop app/mcp/tools/game_update_local.rb spec/mcp/tools/game_update_local_spec.rb`
  → 2 files inspected, no offenses detected.

### Plan checkbox deltas

- 01g checkboxes 1-4 (MCP `game_update_local` plural shape) are now ticked.
- 01g checkboxes 5-6 (CLI TUI Games view + Rust tests) deferred — flagged as
  follow-up below.
- New checkbox added: MCP `yt:games_list` `filters` argument + MCP
  `yt:game_show` plural shape, both deferred and gated on §01b landing.

### Open follow-ups (not in scope this session)

- **CLI half of §01g** — `extras/cli/src/api/games.rs`,
  `extras/cli/src/views/games.rs`, `extras/cli/src/models/game.rs`,
  `extras/cli/tests/games_filter_test.rs`,
  `extras/cli/tests/games_ownership_test.rs`. The spec body covers these in
  full; per the master dispatch brief this sub-spec ships the MCP half and the
  CLI half lands when CLI parity is dispatched to `pito-cli`. Tracked as a
  follow-up at the phase level.
- **MCP `yt:games_list` filter argument** — spec body lists it
  (`filters: ["recorded", "ps5", "owned"]`) but the tool does not yet exist in
  `app/mcp/tools/`. Lands once `Games::Filter` (§01b) exposes a stable
  query-object surface so the MCP tool can reuse it instead of re-implementing
  the filter semantics.
- **MCP `yt:game_show` plural shape** — `game_show` tool does not yet exist (we
  currently route through `game_search` + the show controller's JSON branch).
  When it lands, the response carries the plural `platform_owned_ids`, the
  first-element back-compat singular `platform_owned_id`, and the
  `owned_platforms` / `release_platforms` blocks per the spec body.

### Design notes

- The spec mentioned `starred: "yes" | "no"` as an example boolean arg. The
  `Game` model has no `star` / `starred` column today (only `Channel` and
  `Video` do), so the field was not added — introducing a new column is outside
  §01g's scope and outside this agent's file scope.
- The spec uses path conventions like `app/mcp/tools/yt/...` and
  `spec/mcp/tools/yt/...`. The existing codebase uses a flat layout (no `yt/`
  subdir); kept the flat layout to avoid moving 50+ pre-existing files. The two
  layouts are functionally identical.
- `additionalProperties: false` on the input schema is the wire-level
  mass-assignment guard; the Ruby handler's explicit `attrs[:played_at] = ...`
  cherry-picking is the in-handler guard. A regression spec asserts both layers
  (sending `title:` / `igdb_id:` kwargs does not bleed through).

## [skipci] 2026-05-11 — sub-spec 01f Game show/edit per-platform ownership UI (pito-rails)

Implemented sub-spec 01f per
`specs/01f-game-show-edit-per-platform-ownership.md`. Adds the user-facing
per-platform ownership editor + show-page chip list.

### Show page

- New cell in the `local fields` table: an `OwnedPlatformsChipListComponent`
  followed by `· [edit ownership]`.
- Chip list renders one bracketed chip per `Game#owned_platforms`, alphabetical
  case-insensitive. Each chip links to `/games?filters=<slug>,owned` (locked
  Phase 27 01b filter-row contract). Empty state renders muted
  `(not owned on any platform)` placeholder.
- `[edit ownership]` is a bracketed link to
  `/games/:slug/platform_ownerships/edit` — the dedicated editor.

### Editor page

- Route: `resource :platform_ownerships, only: %i[edit update], module: :games`
  nested under `resources :games`. Friendly URL — `:game_id` carries
  `Game#to_param` (the IGDB slug when present).
- Controller scaffolds in-memory `GamePlatformOwnership` rows for every IGDB
  release-platform of the game (plus any owned platform whose IGDB record was
  scrubbed later — covers manually-added rows). Alphabetical case-insensitive
  ordering.
- Form posts a nested-attributes payload using indexed naming
  (`game[game_platform_ownerships_attributes][N][...]`) with a per-row `_own`
  flag. Project yes/no boundary applied — leading
  `<input type="hidden" value="no">` ensures the controller always sees a value
  regardless of the checkbox state. `_own="yes"` becomes a present row (create /
  update); `_own="no"` on an existing row becomes a `_destroy` marker;
  `_own="no"` on a not-yet-owned platform is a silent no-op.
- Per-row metadata persisted: `acquired_at`, `store` (free-text), `notes` per
  Phase 27 01a v1 column set.

### Model

- `Game` gained
  `accepts_nested_attributes_for :game_platform_ownerships, allow_destroy: true, reject_if: :all_blank`
  so the controller can route updates through the standard nested-attributes
  API.

### Hard rules

- Yes/no boundary enforced on `_own`: any value other than `"yes"` / `"no"`
  (e.g. `"true"`, `"1"`, `"false"`) is rejected with 422 and re-renders the
  editor with an inline error.
- No `data-turbo-confirm`, no `window.confirm`, no `alert` / `prompt` anywhere.
  The form uses `data-turbo="false"` to opt out of Turbo on submit (so the
  redirect-to-show flash lands), not because of any confirmation flow.
- Mass-assignment guard: the controller's `update` only permits
  `game_platform_ownerships_attributes`. Smuggled Game attributes (`title`,
  `notes`, `summary`, `igdb_id`) are silently dropped.
- Duplicate `platform_id` rows in a single submit are rejected with a clear
  error message; unknown `platform_id` likewise.

### Files changed

- `config/routes.rb` — nested `resource :platform_ownerships` under
  `resources :games`.
- `app/models/game.rb` —
  `accepts_nested_attributes_for :game_platform_ownerships`.
- `app/controllers/games/platform_ownerships_controller.rb` (new) —
  `before_action :load_game`, `#edit`, `#update`, `build_ownership_rows`,
  `validate_rows`, `transform_rows`.
- `app/components/games/owned_platforms_chip_list_component.{rb,html.erb}` (new)
  — chip list for the show page.
- `app/components/games/platform_ownership_editor_component.{rb,html.erb}` (new)
  — fieldset-per-platform editor body.
- `app/views/games/platform_ownerships/edit.html.erb` (new) — editor page
  wrapping the editor component in a `form_with`.
- `app/views/games/show.html.erb` — replaced the inline
  `owned_platforms.map(&:name).join(", ")` cell with the chip list component +
  `[edit ownership]` link.

### Spec coverage (all green)

- `spec/components/games/owned_platforms_chip_list_component_spec.rb` — 9
  examples (alphabetical ordering, chip href shape, empty state, no JS confirm,
  no destructive class).
- `spec/components/games/platform_ownership_editor_component_spec.rb` — 19
  examples (one row per platform, indexed nested-attribute names, persisted vs.
  unpersisted row state, value population, no JS confirm, empty
  release-platforms placeholder).
- `spec/requests/games/platform_ownerships_spec.rb` — 26 examples (GET edit 200
  / 404, PATCH happy / sad / boundary / round-trip, duplicate-row rejection,
  mass-assignment guard, stale id from another tab).
- `spec/requests/games/show_ownership_ui_spec.rb` — 9 examples (show-page chip
  list + `[edit ownership]` link wiring).
- `spec/views/games/platform_ownerships/edit.html.erb_spec.rb` — 9 examples
  (form action / PATCH method, `[save]` / `[cancel]`, no `data-turbo-confirm`,
  inline error rendering).
- `spec/system/games_platform_ownerships_spec.rb` — 7 examples (full user
  journey: tick PS5+Steam, un-tick PS5, metadata persists, empty-state
  placeholder, chip href matches filter contract).

Total: 79 new examples; adjacent suites (`spec/requests/games_spec.rb`,
`spec/requests/games_show_meta_block_spec.rb`, `spec/views/games/*_spec.rb`,
`spec/components/games/cover_component_spec.rb`,
`spec/system/games_index_spec.rb`,
`spec/models/{game,platform,game_platform_ownership}_spec.rb`) all remain green.

### Gates

- Targeted `rspec` — 437 examples, 0 failures (all Phase 27 game / platform /
  ownership specs plus the new 01f suite).
- `rubocop` on touched Ruby files — clean (11 files, no offenses).
- `brakeman -q -w2` — 0 warnings, 0 errors.

### Open follow-ups

- `01b` filter-row component (in flight) consumes the chip-href contract
  `/games?filters=<slug>,owned`. The chips already emit the locked URL shape;
  01b's controller plumbing will narrow the listing.
- Per-row metadata collapsibility (spec open question #3 — collapsed by default)
  deferred. Open in v1.
- `[own all]` quick-tick (spec open question #4) deferred.
- 01g — MCP / CLI parity for `game_update_local` plural will land the same join
  through the MCP and CLI surfaces.

### References

- `specs/01f-game-show-edit-per-platform-ownership.md` (spec).
- `plan.md` — 01f checkbox group ticked.
- `app/models/game.rb` — `accepts_nested_attributes_for`.
- `app/controllers/games/platform_ownerships_controller.rb` — controller body.

## 2026-05-10 — Game tile metadata two-line layout (pito-rails)

Reshaped the game-tile caption per user feedback (image #77). The caption is now
two explicit lines below the cover art:

    Red Dead Redemption 2        ← line 1: title, ellipsis-truncated
    ★ 93 · 2018                  ← line 2: rating zero-padded, year

Rating now appears FIRST, year SECOND (reversed from the legacy
`Title (2018) ★ 93` single-line caption). Star is U+2605, separator is the
middle-dot U+00B7. Rating is zero-padded to a minimum of two digits (`5 → 05`,
`93 → 93`, `100 → 100`).

### Missing-data handling

- Rating only: `★ 93`
- Year only: `2018`
- Both missing: line 2 omitted entirely
- Title is never blank (DB default `Untitled game`)

### Variant typography

The partial now accepts an optional `variant:` local (`:grid` default, `:shelf`
opt-in). All existing callers omit the local and inherit `:grid` — pure-additive
change. The `:shelf` variant shrinks the title font (11px → 10px) and the meta
font (10px → 9px) to match the smaller `Games::CoverComponent` `:shelf`
footprint.

### Files changed

- `app/helpers/games_helper.rb` (new) — `format_game_rating(rating)` and
  `game_meta_line(game)` helpers.
- `app/views/games/_tile.html.erb` — two-line caption layout with ellipsis
  truncation, variant-aware typography, and the reversed rating-then-year
  ordering.
- `spec/helpers/games_helper_spec.rb` (new, 17 examples) — covers the helper
  truth table (nil, single-digit, two-digit, three-digit ratings; rating-only /
  year-only / both / neither meta lines; separator placement; star glyph;
  defensive leading / trailing separator checks).
- `spec/views/games/_tile.html.erb_spec.rb` (new, 33 examples) — happy-path
  two-line shape, ellipsis CSS (`white-space: nowrap`, `overflow: hidden`,
  `text-overflow: ellipsis`, `max-width: 150px`), rating zero-padding visible,
  separator placement, missing-data edge cases, variant defaults, shelf-variant
  font sizes, anchor / keyboard wiring preservation, and flaw assertions against
  the legacy single-line caption.

### Gates

- `rspec spec/helpers/games_helper_spec.rb spec/views/games/_tile.html.erb_spec.rb spec/components/games/cover_component_spec.rb`
  — 84 examples, 0 failures.
- Adjacent suites (`spec/views/games/_grid_mode.html.erb_spec.rb`,
  `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`,
  `spec/system/games_index_spec.rb`, `spec/system/games_steam_shelf_spec.rb`,
  `spec/requests/games_spec.rb`) — all green.
- `rubocop` — clean (1127 files inspected, no offenses).
- `brakeman -q -w2` — 0 warnings, 0 errors.

### References

- User feedback image #77 (master agent dispatch).
- `app/helpers/games_helper.rb` (new helper module).
- `app/components/games/cover_component.rb` (untouched; metadata lives on the
  tile partial, not the cover component).

## 2026-05-11 — sub-spec 01e Shelf cover-art variant (pito-rails)

Implemented sub-spec 01e per `specs/01e-shelf-cover-art-variant.md` and the
addendum `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`.
This sub-spec introduces the `Games::CoverComponent` ViewComponent that owns
cover-art rendering at two server-side variants — `:grid` (existing
all-games-grid size) and `:shelf` (new shelf-row size). Downstream consumers
(01c Genres / Collections shelves, 01d shelves-by-letter display mode) render
this component instead of inlining `image_tag` calls.

### Size decision — `:shelf` at 65% of grid

The addendum locked: "try 50% first; if Claude Code judges 50% too small in
practice — covers unreadable, cramped, titles printed on art lost — use 65–70%
instead without asking."

The existing grid tile is 150 × 200 px (not the 234 × 312 the architect's spec
assumed — the spec was written against a hypothetical future grid size; current
reality is 150 × 200 from `app/views/games/_tile.html.erb`).

- 50% of 150 × 200 → 75 × 100 px. Below the legibility threshold for IGDB cover
  art. Persona-style title banners, sequel "II" subtitles, and year stamps
  printed on art disappear into noise at sub-90px widths. Effectively reduces
  the cover from a recognition aid to a colored swatch.
- 65% of 150 × 200 → 97.5 × 130 → rounded to **98 × 130 px**. Recognizable,
  dense, titles printed on art still legible. Matches the spec's locked ratio
  AND the lower end of the addendum's fallback range.
- 70% of 150 × 200 → 105 × 140 px. Marginally larger, gains readability, but
  loses ~14% horizontal density per shelf.

**Chosen: 65% (98 × 130 px).** Sits at the lower end of the addendum's "65–70%"
fallback range — preserves shelf density while clearing the readability bar.

The IGDB CDN source token for `:shelf` is `t_cover_small_2x` (180 × 256 native,
downsamples cleanly into 98 × 130). The `:grid` variant continues to source from
`t_cover_big` (264 × 374 native). The two URLs differ, so cache keys differ — no
CSS scaling tricks anywhere.

### Files touched

**New:**

- `app/components/games/cover_component.rb` — `Games::CoverComponent` with
  `DIMENSIONS` map (`:grid` → 150×200 / `t_cover_big`, `:shelf` → 98×130 /
  `t_cover_small_2x`). Validates the variant symbol at init (`ArgumentError` on
  unknown). Accepts `game:`, `variant:` (default `:grid`), `link_to_show:`
  (default `true`).
- `app/components/games/cover_component.html.erb` — renders an `<a>` (or `<div>`
  when `link_to_show: false`) sized via inline width/height (CLS guard) AND the
  `.game-cover game-cover--<v>` CSS class, plus `data-variant=<v>` for
  downstream styling / spec assertions. Missing-cover branch renders the
  standard `[no cover]` placeholder inside a sized slot.
- `spec/components/games/cover_component_spec.rb` — 28 examples across happy /
  sad / edge / flaw / friendly-URL / introspection groups. Includes the spec's
  mandatory "no `transform: scale`, no `width: 65%`" flaw assertions.

**Edited:**

- `app/models/game.rb` — `COVER_SIZES` extended with `t_cover_small_2x` and an
  inline comment pointing at the 01e variant. The existing `cover_url(size:)`
  guard now accepts the new token. (No other changes — the Phase 27 01a
  per-platform ownership rework on this model landed in parallel and is
  unrelated.)
- `app/assets/tailwind/application.css` — added `.game-cover`,
  `.game-cover--grid`, `.game-cover--shelf`, `.game-cover-img`,
  `.game-cover-missing` rules. Real fixed pixel sizes per variant — NO
  `transform: scale`, NO percentage widths, NO `zoom`.
- `spec/models/game_spec.rb` — added two examples in the `#cover_url` block
  confirming `t_cover_small_2x` resolves to the expected IGDB CDN URL and is
  whitelisted by `Game::COVER_SIZES`.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md` —
  ticked the four 01e checkboxes; corrected the size note to reflect the actual
  150 × 200 grid baseline (the original checkbox copy carried the spec's
  hypothetical 234 × 312).

### Specs added

- 28 new component examples (`Games::CoverComponent`).
- 2 new game-model examples (`t_cover_small_2x` whitelist + URL).

Spec count delta: **+30**.

### Gates

- `bundle exec rspec spec/components/games/cover_component_spec.rb` → 28
  examples, 0 failures.
- `bundle exec rspec spec/components/` → 225 examples, 0 failures (full
  component surface green).
- `bundle exec rspec spec/components/games/cover_component_spec.rb spec/models/game_spec.rb`
  → 94 examples, 1 failure. The single failure is at
  `spec/models/game_spec.rb:10` and asserts the now-removed
  `belongs_to :platform_owned` association — that removal landed in parallel
  from sub-spec 01a (`Phase 27 §1a — per-platform ownership join`). The spec
  line is a leftover for the 01a agent to clean up; it is not in my file scope
  and predates my edits to `game_spec.rb`.
- `bundle exec rubocop app/components/games app/models/game.rb spec/components/games spec/models/game_spec.rb`
  → 4 files inspected, 0 offenses.
- `bundle exec brakeman -q -w2` → 0 security warnings.

### Open issues

- **Sister-agent leftover.** `spec/models/game_spec.rb:10` still references the
  dropped `belongs_to :platform_owned`. The 01a agent owns this fix; my work
  doesn't touch it.
- **Test DB volatility during the parallel push.** While running the suite I
  observed multiple parallel migrations landing mid-run
  (`create_notification_delivery_channels`, `revamp_platforms_for_friendly_id`,
  `create_game_platform_ownerships`, `drop_platform_owned_id_from_games`) and
  the test DB falling into an inconsistent state at one point (`db/schema.rb`
  contained an in-progress `Could not dump table "games"` comment block during a
  parallel agent's pg dump). This is a coordination artefact — the master agent
  should validate the test DB is clean before running the full suite for review.
- **`db/schema.rb` correctness.** As of this session's end, the schema dump may
  not reflect a stable state because sister migrations from 01a were landing in
  parallel. Re-running `bin/rails db:schema:dump` after both phases settle is
  recommended.

### Coordination

- Downstream sub-specs 01c (Genres / Collections shelves) and 01d
  (shelves-by-letter display mode) can drop in
  `render Games::CoverComponent.new(game:, variant: :shelf)` for every shelf
  tile. The component's `DIMENSIONS` constant exposes the canonical sizes for
  layout calculations (e.g. shelf-row min-height).
- The Phase 27 01a per-platform ownership migrations landed in parallel during
  this session; my component does not depend on ownership shape (it reads only
  `game.cover_url`, `game.title`, `game.id`, `game.to_param`) so the two changes
  are orthogonal.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01e-shelf-cover-art-variant.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Addendum: `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`.
- Plan checkbox: `… /plan.md` → `01e — Shelf cover art variant` block (all four
  boxes ticked).

## 2026-05-11 — sub-spec 01d Display mode switcher + three modes (pito-rails)

Implemented sub-spec 01d per
`specs/01d-display-mode-switcher-and-three-modes.md` plus master dispatch
overrides (locked in this session).

### Master dispatch overrides vs the architect spec

The architect spec proposed `Settings::GamesDisplayModesController` at
`PATCH /settings/games_display_mode/:mode` plus three ViewComponent classes
(`DisplayModeSwitcherComponent`, `ListViewComponent`,
`ShelvesByLetterComponent`). The master agent dispatched a reframe: a
`Users::GamesPreferencesController` at `PATCH /users/games_preferences` carrying
`mode=...` in the form body, with three plain partials (`_grid_mode`,
`_list_mode`, `_shelves_by_letter_mode`) plus a `_display_mode_switcher`
partial. Behavior parity is full; surface naming differs.

### What landed

- Migration `20260511143000_add_preferred_games_display_mode_to_users` adds the
  `preferred_games_display_mode` integer column on `users` with
  `null: false, default: 0`. Run against both dev and test DBs.
- `User#preferred_games_display_mode` enum with keys `grid`/`list`/
  `shelves_by_letter` mapped to stable integers `0/1/2` and the `games_display_`
  prefix on predicates / bangs.
- `Users::GamesPreferencesController#update` — single PATCH endpoint that
  validates the `mode` param against an allowlist, writes the enum, and
  redirects to `/games?display=<mode>`. Unknown / blank modes flash an alert and
  leave the persisted preference alone.
- Route `PATCH /users/games_preferences` under a fresh `namespace :users` block.
- `GamesController#index` reads the resolved display mode via a new private
  `resolved_display_mode` method (URL `?display=` overrides per-request; falls
  back to `Current.user.preferred_ games_display_mode`; final `:grid` fallback
  for the anonymous defensive path).
- `app/views/games/index.html.erb` now renders the switcher flush-right of the
  H1 row, and branches the "all games" section on `@display_mode` to one of
  three partials.
- `app/views/games/_grid_mode.html.erb` — extracted from the legacy
  `all-games-grid` inline block; renders `games/tile`s with
  `data-keyboard-grid="true"`.
- `app/views/games/_list_mode.html.erb` — `<table>` grouped by first-letter
  buckets, with `<tr class="letter-head">` sticky heading rows. Five columns:
  cover thumb (`t_cover_small`), title (linked), platforms owned (placeholder
  `—` until 01a's `game_platform_ownerships` shape stabilises), genres, computed
  status (`recorded` / `released` / `scheduled` / `unreleased`). Sticky
  `position: sticky` declaration inlined on the partial so the system-level CSS
  spec asserts on it without chasing across the asset pipeline.
- `app/views/games/_shelves_by_letter_mode.html.erb` — one `games/shelf` per
  non-empty letter bucket. Empty letters hidden (locked decision).
  Non-alphabetic title starts collapse into the `#` bucket.
- `app/views/games/_display_mode_switcher.html.erb` — three `button_to` forms,
  one per mode. Active mode renders with the `bracketed active` class. No JS. No
  anchor.

### Tests added (33 new examples, all green)

- `spec/models/user_spec.rb` —
  `preferred_games_display_mode enum (Phase 27 — 01d)`: default, key set,
  stable-integer mapping, prefixed predicates / bangs, ArgumentError on invalid
  value, DB NOT NULL + default backstop. (7 new examples.)
- `spec/requests/users/games_preferences_spec.rb` — `Users::GamesPreferences`:
  per-mode persist + redirect, unknown / blank token rejection,
  rapid-double-PATCH last-write-wins, signed- out 302→/login, URL friendliness,
  yes/no boundary sweep. (9 new examples.)
- `spec/views/games/_display_mode_switcher.html.erb_spec.rb` — switcher
  structure, labels, active-class behavior across all three modes + String arg
  parity, CLAUDE.md hard-rule guards (no JS confirm / no `text-danger` on the
  switcher / real forms not anchors). (10 new examples.)
- `spec/views/games/_grid_mode.html.erb_spec.rb` — data-mode tag, keyboard-grid
  opt-in, "all games" heading, empty-state copy. (4 new examples.)
- `spec/views/games/_list_mode.html.erb_spec.rb` — table head with five columns,
  letter-head row interleaving, sticky CSS, title linkage, data-mode tag; edge
  cases for `#` bucket, lowercase titles, missing genres / no release_date / no
  cover; empty state. (10 new examples.)
- `spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb` — one shelf per
  non-empty letter, empty letters hidden, steam- shelf controller, tile partial
  usage, edge cases for `#` and lowercase buckets, empty state. (8 new
  examples.)

73 new + adjacent examples run green via
`bundle exec rspec spec/models/user_spec.rb \   spec/requests/users/games_preferences_spec.rb \   spec/views/games/_display_mode_switcher.html.erb_spec.rb \   spec/views/games/_grid_mode.html.erb_spec.rb \   spec/views/games/_list_mode.html.erb_spec.rb \   spec/views/games/_shelves_by_letter_mode.html.erb_spec.rb`.

### Gates

- `bundle exec rspec` on the 6 spec files above: 73 examples, 0 failures.
- `bundle exec rubocop` on the 10 Ruby files touched: no offenses.
- `bundle exec brakeman -q -w2`: 0 errors, 0 security warnings, full app sweep.

### Open issues / coordination notes for the master

- **01a + 01c drift on `GamesController#index` is blocking the full `/games`
  index render and so the existing `spec/requests/games_spec.rb` and the planned
  01d system spec.** The controller still references `Platform#games_owning` (an
  association the 01a model rewrite removed) and `Game#platform_ owned_id` (a
  column the 01a migration dropped). 14 failing examples in
  `spec/requests/games_spec.rb` are all variants of that drift; none are caused
  by 01d. The 01d controller-side resolver
  (`@display_mode = resolved_display_mode`) sits past the broken
  `@platforms_shelves` line, so 01a's controller fix will unblock 01d's `/games`
  integration without any further edit.
- The locked routing URL is `/users/games_preferences` (the spec proposed
  `/settings/games_display_mode/:mode`). Plan checkbox copy was reworded to
  match.
- List-mode sort columns are NOT wired yet — the spec calls for a sortable
  column set but the underlying `game_platform_ ownerships` shape is the 01a /
  01f lane. The partial structure is in place to wire `?sort=` once those land.
- The "platforms owned" list-mode column renders a literal `—` placeholder
  pending 01a's join-table integration.
- No system spec yet — the existing `/games` index is wedged on 01a drift (see
  above). The view + request specs cover the same behavior at the per-partial
  level; a system spec is queued for after 01a's controller fix lands.

### Files changed

- `db/migrate/20260511143000_add_preferred_games_display_mode_to_users.rb` (new)
- `app/models/user.rb` (enum added)
- `app/controllers/users/games_preferences_controller.rb` (new)
- `app/controllers/games_controller.rb` (resolver helper + index reads
  `@display_mode`)
- `config/routes.rb` (`namespace :users` block)
- `app/views/games/index.html.erb` (switcher + branch on `@display_mode`)
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
- Plan checkbox: `… /plan.md` → `01d — Display mode switcher + three modes`
  block (all 10 boxes ticked, with reframe notes inline).

## 2026-05-11 — sub-spec 01c Genres + Collections shelves (pito-rails)

Implemented sub-spec 01c per `specs/01c-genres-and-collections-shelves.md` plus
master dispatch overrides (partials over ViewComponents, simpler URL contract,
inline `:shelf` styling pending 01e).

### Master dispatch overrides vs the architect spec

The architect spec proposed three ViewComponent classes
(`Games::GenresShelfComponent`, `Games::CollectionsShelfComponent`, shared
`Games::ShelfTileComponent`) plus a model scope `Game.in_genre(slug)`. The
master agent dispatched a reframe: two plain partials (`_genres_shelf.html.erb`,
`_collections_shelf.html.erb`) at `app/views/games/`, with the existing
`?genre=<slug>` / new `?collection=<slug>` filter parameters handled directly in
`GamesController#index`. No new model scope; the existing
`joins(:game_genres).where(genre_id: …)` and `where(collection_id: …)` codepaths
absorb both forms.

### What landed

- `app/views/games/_genres_shelf.html.erb` (new) — top-of-page horizontal-scroll
  shelf, alphabetical (case-insensitive). Each tile is a clickable `<a>` to
  `/games?genre=<slug>` (falls back to `/games?genre=<id>` when `Genre#slug` is
  blank). Tiles use the `steam-shelf` Stimulus controller already in use by the
  legacy per-genre/per-platform shelves. Empty shelf renders a muted
  `(no genres yet)` placeholder so the layout doesn't shift.
- `app/views/games/_collections_shelf.html.erb` (new) — mirror of the Genres
  shelf for `Collection`. The architect spec mentions a `kind: :custom` filter
  (open question #2); the current Collection schema has no `kind` / `custom`
  column so the shelf renders every Collection. A future migration can
  reintroduce the distinction.
- `app/views/games/index.html.erb` — renders both new partials at the top of the
  page, above the existing bundles / recently-played / per-genre / per-platform
  shelves and the all-games grid.
- `app/controllers/games_controller.rb#index` — sets `@genres_for_shelf` and
  `@collections_for_shelf` (both ordered `Arel.sql("LOWER(name)")` with `id`
  tie-break for deterministic rendering across requests). Adds
  `?collection=<slug>` filter; the existing `?genre=<id>` codepath now also
  accepts a slug string. Both lookups go through ActiveRecord parameterized
  queries, so SQL-unsafe input cannot reach the database.
- Inline tile cover-art size locked to 75×100 px (50% of the 150×200 grid tile)
  per the master's 50% addendum. Once 01e's
  `Games::CoverComponent.new(variant: :shelf)` (98×130 at 65%) is fully wired
  through the codebase, this inline block swaps to the component call; the
  surrounding tile shell is already shaped to absorb the swap.

### Sister-agent compensating patch

The convergent commit `b14f974` landed 01a's migrations
(`drop_platform_owned_id_from_games`, `create_game_platform_ownerships`,
`revamp_platforms_for_friendly_id`) and the post-01a `Platform` model
(`Platform#games_owning` retired, `Platform#games` re-routed through
`:game_platform_ownerships`) but did NOT update `GamesController#index`. The
controller still ran `Platform.joins(:games_owning)` (now broken) and
`Game.where(platform_owned_id: …)` (column dropped). Every request to `/games`
was 500ing in the test environment.

01c's smallest-possible compensating fix (necessary to land my own request and
system specs) is in `GamesController#index` only:

- `Platform.joins(:games_owning)` → `Platform.joins(:games)` — the new
  association lives on the post-01a Platform model exactly under that name (see
  `app/models/platform.rb` line 35).
- `scope.where(platform_owned_id: …)` removed — the column is gone; the
  canonical platform filter ships with 01b's filter row (`owned_on=<slug>`).
- `sanitized_filter` no longer reads `params[:platform_owned]`.

This patch is the minimum to keep `GET /games` serving. The remaining 01a
controller fan-out (`Game` model needs `has_many :owned_platforms`,
`local_only_params` should drop `:platform_owned_id`, etc.) stays in 01a's lane
and is flagged in the "Open issues" section below.

### Specs added

- `spec/requests/games_spec.rb` — 12 new examples under "Phase 27 §01c —
  top-of-page shelves" (8 examples: heading + empty-state for both shelves,
  alphabetical ordering, slug-based tile hrefs, id fallback, steam-shelf
  controller stamp) and "Phase 27 §01c — slug filter routes" (4 examples:
  `?genre=<slug>` / `?collection=<slug>` happy paths + unknown-slug silently
  drops).
- `spec/system/games_index_spec.rb` already lives in the convergent commit (11
  examples: shelf headings, alphabetical ordering, empty-state placeholders,
  steam-shelf controller stamp, tile navigation across genre / collection /
  id-fallback paths).

Spec count delta: **+12 request examples** (system spec was already committed
but newly passing).

### Gates

- `bundle exec rspec spec/requests/games_spec.rb -e "Phase 27 §01c"` → 12
  examples, 0 failures.
- `bundle exec rspec spec/system/games_index_spec.rb` → 11 examples, 0 failures.
- `bundle exec rspec spec/requests/games_spec.rb` (full file) → 71 examples, 14
  failures. All 14 failures are pre-existing 01a drift (Game model missing
  `owned_platforms` / `game_platform_ownerships`; show.html.erb references
  those). Listed in "Open issues" below.
- `bundle exec rubocop app/controllers/games_controller.rb spec/requests/games_spec.rb spec/system/games_index_spec.rb`
  → 3 files inspected, 0 offenses.
- `bundle exec brakeman -q -w2` → 0 errors, 0 security warnings.

### Open issues / coordination notes for the master

- **01a still has unfinished controller and model fan-out.** The `Game` model
  never gained `has_many :game_platform_ownerships` /
  `has_many :owned_platforms, through: …`. `app/views/games/show.html.erb`
  references `@game.owned_platforms` (committed in `b14f974`) which raises
  `NoMethodError`. 14 `spec/requests/games_spec.rb` examples fail on this. None
  of them are caused by 01c.
- **`Game#belongs_to :platform_owned` still in the model.** The column was
  dropped by 01a's migration but the association is alive; loading a Game with
  `platform_owned` accessed raises. Removed by 01a when their fan-out completes.
- **`GamesController#local_only_params` still permits `:platform_owned_id`.**
  The column is gone; the permit is harmless (`permit` silently drops keys not
  on the model) but should be cleaned by 01a.
- **`:shelf` cover variant is inline, not the 01e component.** Once 01e's
  `Games::CoverComponent.new(game: …, variant: :shelf)` is fully integrated, the
  inline 75×100 block in both shelf partials swaps to the component call. Note
  01e's locked size is 65% (98×130 px); 01c's inline is 50% (75×100 px) per the
  addendum's starting point. Reviewer should confirm visual density in browser
  before finalizing.
- **No `Collection#custom` column.** The architect spec proposed filtering
  Collections by `kind: :custom`. The Phase 14 Collection schema has no such
  column. The 01c partial shows every Collection until a future migration
  introduces the distinction.
- **`Genre#slug` is not unique-indexed.** The Phase 14 genres table has a `slug`
  column without a unique index. My tile-href fallback (`?genre=<id>` when slug
  is blank) handles missing slugs; if two genres ever share a slug, the
  controller's lookup returns the first match (deterministic by id order). A
  unique index on `genres.slug` would be a one-line follow-up.

### Files changed

- `app/views/games/_genres_shelf.html.erb` (new — already in `b14f974`,
  byte-identical to working tree).
- `app/views/games/_collections_shelf.html.erb` (new — already in `b14f974`,
  byte-identical to working tree).
- `app/views/games/index.html.erb` (wire both shelves above the existing layout;
  +7 lines).
- `app/controllers/games_controller.rb` (set `@genres_for_shelf` /
  `@collections_for_shelf`; add `?collection=<slug>` filter; accept slug form of
  `?genre=`; 01a compensating patch on `@platforms_shelves` and
  `sanitized_filter`).
- `spec/requests/games_spec.rb` (+144 lines, +12 examples).
- `spec/system/games_index_spec.rb` (already in `b14f974`, byte-identical — 11
  examples now passing).

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-genres-and-collections-shelves.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Addendum: `docs/notes/2026-05-11-11-33-29-games-shelf-cover-size-addendum.md`
  (`:shelf` variant starts at 50%, fallback 65–70%).
- Convergent commit: `b14f974` — landed both shelf partials and the system spec;
  this session adds the controller / view wiring and request specs.
- Plan checkbox: `…/plan.md` → `01c — Genres and Collections shelves` block (3
  of 5 boxes ticked; ViewComponent and `:shelf` cover-variant boxes annotated
  with reframe / dependency notes).

## 2026-05-11 — sub-spec 01a Per-platform ownership data model (pito-rails)

Implemented sub-spec 01a per `specs/01a-per-platform-ownership-data-model.md`.
Replaces the single-valued `games.platform_owned_id` pointer with a multi-valued
`game_platform_ownerships` join, hardens the existing Phase 14 `platforms` table
into a FriendlyId-backed canonical reference, and adds the IGDB platform sync
service / job / rake task.

### What landed

- Three migrations (`20260511160000_revamp_platforms_for_friendly_id`,
  `20260511160001_create_game_platform_ownerships`,
  `20260511160002_drop_platform_owned_id_from_games`). All `up` on the dev DB,
  schema dump regenerated cleanly.
- `Platform` model: FriendlyId (`slugged + history + finders`),
  `default_scope { order(:name) }`, `:games_available` association (renamed from
  the legacy `:games` through `game_platforms`), `:game_platform_ownerships` +
  `:games` (through ownerships) with `:restrict_with_error` on platform destroy.
- New `GamePlatformOwnership` model. `belongs_to :game` / `:platform` (required
  by default), uniqueness on `(game_id, platform_id)`. Cascade from games,
  restrict from platforms.
- `Game` model: dropped `belongs_to :platform_owned`; added
  `:game_platform_ownerships` (`dependent: :destroy`) + `:owned_platforms`
  through. New scopes `.owned`, `.not_owned`, `.owned_on(slug)` consumed by
  01b's filter row. `owned_on` uses raw SQL for the slug match because
  `where(platforms: { … })` collides with the legacy `games.platforms` jsonb
  column — documented in the scope's comment.
- `Platforms::SyncFromIgdb` service + `Platforms::SyncFromIgdbJob` wrapper +
  `lib/tasks/platforms.rake` task + weekly Sidekiq cron entry. The service pages
  via `Igdb::Client#list_all_platforms` (new method, paginates `/platforms`
  500-at-a-time using the `Apicalypse.offset` builder method added this
  session).
- Seed: PS5, Switch 2, Steam, GOG, Epic populated by slug, idempotent.
- MCP `game_update_local` now accepts plural `platform_owned_ids` with
  explicit-null-as-wipe semantics; the legacy singular `platform_owned_id` is
  auto-wrapped into a one-element array per the locked decision. Errors surface
  clean (unknown platform id → `RecordNotFound`, validation → `RecordInvalid`).
- Cascading code updates so the column drop doesn't blow up unrelated surfaces:
  - `games_controller`: filter resolves a platform **slug** (id accepted for
    backward-compat) and threads through `Game.owned_on(slug)`. The
    `local_only_params` permit list no longer carries `:platform_owned_id`.
  - `GameDecorator`: summary JSON now emits `platform_owned_ids: [int]` (empty
    array when no ownership); `platforms_owning` detail block renders the joined
    platforms.
  - `app/views/games/{edit,show}.html.erb`: the platform-owned dropdown /
    read-only field is replaced with a multi-value "owned on" inline list. The
    dedicated editor lands in 01f.
  - `app/views/games/index.json.jbuilder`: filter echo carries
    `platform_owned_slug`.
  - `Igdb::GameMapper` + `Igdb::SyncGame` comment-only updates so the local-only
    column list stays accurate.
- Spec pyramid: model specs (`platform_spec`, `game_spec`,
  `game_platform_ownership_spec`), service spec
  (`platforms/sync_from_igdb_spec`), job spec
  (`platforms/sync_from_igdb_job_spec`), rake spec (`platforms_rake_spec`).
  Existing specs that touched the legacy column updated in-place to reflect the
  new join shape (`games_spec` request, `game_decorator_spec`,
  `index.json.jbuilder_spec`, `game_mapper_spec`, `sync_game_spec`).

### Backfill plan

The dropped `games.platform_owned_id` column had no production users
(pre-launch). The migration body documents the recipe for a future operator who
needs to migrate a row set:

    Game.where.not(platform_owned_id: nil).find_each do |g|
      g.game_platform_ownerships.find_or_create_by!(
        platform_id: g.platform_owned_id
      )
    end

The recipe stayed in the migration comments rather than the body so the
migration remains mechanical (drop FK / index / column) and the data-shape
decision stays explicit in code review.

### Column-name variance vs. the spec

Spec body referenced `igdb_platform_id` on the platforms table. The existing
Phase 14 `platforms.igdb_id` column was the equivalent — the "if not exists"
guard in the locked decisions kept it under its established name to minimize the
change radius (renaming would have touched IGDB sync, factories, and Genre /
Company patterns that mirror the same shape). All other spec invariants
(nullable for seeded rows, unique-when-present, FriendlyId slug, etc.) are
honored.

### Gates

- `rspec` — relevant subtrees green (models, services, jobs, decorators, views,
  requests/games, mcp). Full suite (3629 examples) passes with 1 pre-existing
  pending example.
- `rubocop` — clean on all touched Ruby files.
- `brakeman` — 2 warnings, both pre-existing (Notification XSS weak warning,
  composites file-access weak warning). No new findings.

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01a-per-platform-ownership-data-model.md`.
- Umbrella:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01-overview-games-listing-rework.md`.
- Plan checkbox: `…/plan.md` → `01a — Per-platform ownership data model` block
  (all 10 boxes ticked).

---

## 2026-05-11 — 01h Collection cover composer (re-dispatch)

Re-dispatched after the original 01h work landed in `e145122` ("Convergent: P25
01c notifications + P26 01g viewer-time + P27 01h composer + misc"). This
session:

- Verified the committed implementation against the spec
  `specs/01h-collections-cover-composer.md`: 6-variant matrix (empty /
  passthrough / pair / netflix3 / quad / netflix5 / six_grid), 98×130 output
  canvas, alphabetical-by-title ordering, MAX 6 tiles, fingerprint via
  `Composite::Checksum.compute`, on-disk path `composites/collection-<id>.jpg`,
  libvips-error degradation (substitute placeholder + WARN), cache invalidation
  hook via `Game#after_update_commit` on `collection_id` change.

- Fixed a latent flake in `spec/jobs/collection_cover_rebuild_job_spec.rb`: the
  "survives Errno::ENOENT mid-job" example stubbed `File.delete` globally
  without restoration, which leaked into the `after` cleanup hook and crashed
  teardown. Scoped the stubs to the two specific Pathname targets and broadened
  the `after` hook's `rescue` clause to
  `Pito::AssetsRoot::Error, Errno::ENOENT`.

- Confirmed the `Compositable` concern (`app/models/concerns/compositable.rb`)
  is mixed into both `Bundle` and `Collection`, providing `composite_cover_url`,
  `composite_cover_absolute_path`, and `sweep_composite_cover_file`. The
  `Composite::Builder` itself stays bundle-coupled (per the spec's "bundle code
  stays untouched" mandate) — the natural sharing point was the URL/path/sweep
  trio, not the build pipeline.

### Variant matrix coverage (98 × 130)

| Count | Layout       | Tile boxes                                   | Sums     |
| ----- | ------------ | -------------------------------------------- | -------- |
| 0     | :empty       | n/a (no composite)                           | n/a      |
| 1     | :passthrough | n/a (caller renders `Games::CoverComponent`) | n/a      |
| 2     | :pair        | 49×130 ‖ 49×130                              | 98 / 130 |
| 3     | :netflix3    | big 64×130 ‖ (34×65 / 34×65)                 | 98 / 130 |
| 4     | :quad        | 49×65 ‖ 49×65 / 49×65 ‖ 49×65                | 98 / 130 |
| 5     | :netflix5    | big 50×130 ‖ (24×65,24×65 / 24×65,24×65)     | 98 / 130 |
| 6+    | :six_grid    | (33,33,32 × 65) / (33,33,32 × 65)            | 98 / 130 |

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
- `app/models/game.rb` —
  `after_update_commit :evict_collection_composite_on_collection_change`.
- `app/views/games/_collection_sub_shelf.html.erb` (new — view partial).
- `app/assets/tailwind/application.css` — `.collection-cover-composite`.
- `db/migrate/20260511160358_add_composite_cover_columns_to_collections.rb`
  (composite_cover_path + composite_cover_checksum on collections).
- Specs: `spec/services/collections/composite_layout_spec.rb` (86),
  `spec/services/collections/cover_composer_spec.rb` (22),
  `spec/models/concerns/compositable_spec.rb` (10),
  `spec/models/collection_spec.rb` (additions), `spec/models/game_spec.rb`
  (additions), `spec/jobs/collection_cover_rebuild_job_spec.rb` (10 — including
  this session's race-condition stub-scoping fix),
  `spec/views/games/_collection_sub_shelf.html.erb_spec.rb` (15),
  `spec/requests/composites_spec.rb` (additions).

### Gates

- `rspec` — 347 touched-subtree examples green (services/collections,
  models/concerns/compositable, models/collection, models/game,
  jobs/collection*cover_rebuild_job, views/games/\_collection_sub_shelf,
  requests/composites, models/bundle, services/composite, jobs/bundle_cover*\*).
- `rubocop` — clean on all touched Ruby files (16 inspected, no offenses).
- `brakeman` — 0 security warnings (2 prior obsolete-ignore entries noted, both
  pre-existing).

### References

- Spec:
  `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01h-collections-cover-composer.md`.
- Implementing commit: `e145122` (Convergent commit landing 01h alongside P25
  01c and P26 01g).
- Note on canvas size: spec's Open Question #1 resolved to 98 × 130 (the
  existing `:shelf` cover-art variant), NOT the 105 × 140 alternate. Per the
  user dispatch — the integer math for the six_grid is 33+33+32 vs. the cleaner
  35+35+35 at 105, but the hosting shelf size locks 98 × 130.

## [skipci] 2026-05-11 — six bundled `/games` follow-ups (primary genre + lowercase + composer wiring + demo collection) (pito-rails)

Single-pass cleanup bundling Phase 27's deferred follow-ups + the P27
reviewer BLOCKER + a couple of copy fixes the user called out while
reviewing the live page.

### Fixes 1 + 2 — primary-genre picker + Game model wire-up

- `db/migrate/20260511180000_add_primary_genre_id_to_games.rb` adds
  `games.primary_genre_id` (nullable, indexed, FK to `genres` with
  `on_delete: :nullify`). Applied to dev and test DBs; `db/schema.rb`
  bumped to `2026_05_11_180000`.
- `app/services/games/primary_genre_picker.rb` returns ONE canonical
  `Genre` per Game via three rules: explicit pin → alphabetical first
  linked → nil. Documented inline; pure function, no persistence.
- `app/models/game.rb` gains `belongs_to :primary_genre, class_name:
  "Genre", optional: true` + `before_save :assign_primary_genre_if_blank`.
- `app/models/game_genre.rb` gains `after_save` / `after_destroy`
  callbacks (NOT the `_commit` variants — RSpec transactional fixtures
  never commit) so the pin updates when `game.genres << g` or `game.genres
  = [...]` fires. The callback short-circuits when a pin is already in
  place to avoid thrashing.
- `lib/tasks/pito.rake` adds `pito:backfill_primary_genres`. Idempotent;
  ran against dev — 2 games backfilled, 4 left NULL (no linked genres),
  re-run is a no-op.
- `app/controllers/games_controller.rb` `@genres_for_shelf` now reads
  `Game.where.not(primary_genre_id: nil).distinct.select(:primary_genre_id)`
  so each game appears in exactly one sub-shelf.
- `app/views/games/_genre_sub_shelf.html.erb` now reads
  `Game.where(primary_genre_id: genre.id)` for both the count and the
  ordered tile list.

### Fix 3 — lowercase genre labels (acronym allowlist)

- `app/helpers/genres_helper.rb` rewritten around a two-stage rule:
  long-form names short-mapped via `GENRE_SHORT_NAMES` ("Role-playing
  (RPG)" → "RPG"), then non-acronym labels downcased ("Adventure" →
  "adventure", "Shooter" → "shooter"). `ACRONYM_LABELS` keeps only
  `RPG` upper-case (per user "shooter is shooter actually" — the
  legacy `First-person shooter → FPS` mapping is gone). MMO / RTS /
  TBS now render lowercase too; extending the acronym list later is
  non-breaking.
- The helper's public method name stayed `genre_short_name` to avoid
  churning every call site (`_genre_sub_shelf.html.erb`,
  `_list_mode.html.erb`).
- Helper spec rewritten end-to-end.

### Fix 4 — collections-shelf heading + seed rename

- `app/views/games/_collections_shelf.html.erb` `<h2>` text changed
  from `custom collections` to plain `collections`.
- `db/seeds.rb` legacy `Demo Collection` renamed to `currently
  playing`. Idempotent — find_or_create_by(name:) creates a new row on
  next seed; existing installs keep the old row (which the user can
  rename / delete in the UI). Notes call out the rename so future
  contributors know why a fresh install has two collection rows in
  dev DBs that ran the prior seed.

### Fix 5 — composer wiring (P27 reviewer BLOCKER)

- `app/services/games/prepare_collections_for_shelf.rb` walks the
  outer-shelf collections and calls `Collections::CoverComposer#call`
  on each. The composer is fingerprint-cached so the call is a no-op
  on cache hits; 0/1 member layouts short-circuit inside the composer.
- `GamesController#index` invokes the service in-line after
  `@collections_for_shelf` resolves. One render per request; out-of-
  band Sidekiq job not needed for the in-flight render path.
- New spec `spec/services/games/prepare_collections_for_shelf_spec.rb`
  asserts the composer is invoked, the input is returned for chaining,
  and a composer exception on one row does not 500 the whole index.
- Added a request spec assertion that `Collections::CoverComposer#call`
  is reached from `GamesController#index` for a 2-game collection.

### Fix 6 — demo "now playing" collection

- `db/seeds.rb` appended a `now playing` collection seed containing
  `Pragmata` + `Red Dead Redemption 2` (lookup by title, creates thin
  placeholder rows when missing so a clean install gets a 2-member
  collection the composer can render). Re-running seeds is idempotent;
  rows already in another collection are left alone.

### Specs

- `+spec/services/games/primary_genre_picker_spec.rb` (7 examples)
- `+spec/services/games/prepare_collections_for_shelf_spec.rb` (4 examples)
- `+spec/models/game_genre_spec.rb` (3 new examples covering callback)
- `+spec/models/game_spec.rb` (1 new association example)
- `~spec/helpers/genres_helper_spec.rb` (rewritten — 23 examples)
- `~spec/views/games/_genres_shelf.html.erb_spec.rb` (lowercase label)
- `~spec/views/games/_collections_shelf.html.erb_spec.rb` (heading copy)
- `~spec/views/games/_genre_sub_shelf.html.erb_spec.rb` (lowercase label)
- `~spec/requests/games_spec.rb` (lowercase label + heading copy +
  composer wiring assertion)
- `~spec/system/games_index_spec.rb` (lowercase headings)
- `~spec/system/games_steam_shelf_spec.rb` (lowercase content)

All 579 examples across the touched + adjacent surface pass. Brakeman
clean (0 warnings, 0 errors). Rubocop clean on every Ruby file touched
(20 files, 0 offenses).

### Files

- `app/services/games/primary_genre_picker.rb` (new)
- `app/services/games/prepare_collections_for_shelf.rb` (new)
- `app/models/game.rb`
- `app/models/game_genre.rb`
- `app/helpers/genres_helper.rb`
- `app/controllers/games_controller.rb`
- `app/views/games/_collections_shelf.html.erb`
- `app/views/games/_genre_sub_shelf.html.erb`
- `db/migrate/20260511180000_add_primary_genre_id_to_games.rb` (new)
- `db/seeds.rb`
- `db/schema.rb`
- `lib/tasks/pito.rake`
- spec files listed above.

### Open issues / deferred

- Manual primary-genre override surface on `/games/:id/edit` — the
  schema and the model honor a manual pin (`primary_genre_id` set
  directly), but there is no UI control yet. Queued as a follow-up
  once the user asks for it.
- Existing dev DB rows from the pre-rename seed (`Demo Collection`)
  remain — the rename is forward-only. Operator can delete via the
  UI when ready.

## 2026-05-11 — Collections shelf restructure (single-row tiles + modal)

### Dispatch

User direction on the `/games` Collections surface (verbatim):
> collections is just one row with the compound cover art. Clicking it
> will open a modal with the games from that collection. Clicking a
> game will navigate to the Game's page.

Replaces the 01c-v2 "outer shelf of per-collection sub-shelves of game
tiles" design with a single horizontal-scroll row of tile-per-
collection. Each tile renders the composite cover (or the project's
shelf-variant fallback SVG when the composer returned nil for an
empty / single-game collection). Click → opens a layout-level
`<dialog id="collections-modal">` whose inner Turbo Frame fetches
`/collections/<id>/games_pane`. The pane lists the collection's games
as `Games::CoverComponent :grid` tiles; each is wrapped in an `<a>`
back to the game show page (full navigation).

The 01h composer wiring (`Games::PrepareCollectionsForShelf` →
`Collections::CoverComposer`) was already in place from the prior
v2 dispatch; this restructure simply rewires the consumer view to
read `collection.cover_url(variant: :shelf)` directly. No composer
changes.

### Changes

Routes:
- `GET /collections/:id/games_pane → Collections#games_pane` (new
  member action; returns a Turbo Frame fragment, no application
  layout).

Controllers:
- `CollectionsController#games_pane` (new).
- `GamesController#index` — composer-warmup comment updated to point
  at the new partial filename. No logic change.

Views:
- `app/views/games/_collections_shelf.html.erb` — rewritten. Now a
  single horizontal-scroll row of `_collection_tile` renders + emits
  the layout-level `<dialog>` modal partial alongside.
- `app/views/games/_collection_tile.html.erb` (new) — one tile,
  composite cover or fallback SVG, name in muted gray below.
- `app/views/games/_collections_modal.html.erb` (new) — `<dialog>`
  with Turbo Frame `collections_modal_frame` + `[close]` bracketed
  link.
- `app/views/collections/games_pane.html.erb` (new) — Turbo Frame
  fragment, grid of `Games::CoverComponent :grid` tiles linked to
  each game's show page.
- `app/assets/tailwind/application.css` — updated stale comment
  reference (`_collection_sub_shelf.html.erb` → `_collection_tile`).

JavaScript:
- `app/javascript/controllers/collections_modal_trigger_controller.js`
  (new) — Stimulus controller: on click sets the Turbo Frame `src`,
  updates the modal heading, calls `dialog.showModal()`. No
  `confirm()` / `alert()` / `prompt()` — closes via
  `confirm-modal#clickOutside` / Escape / `[close]` link.

Deletions:
- `app/views/games/_collection_sub_shelf.html.erb` (orphaned).
- `app/views/games/_collection_sub_shelf_row.html.erb` (orphaned).
- `spec/views/games/_collection_sub_shelf.html.erb_spec.rb`.
- `spec/views/games/_collection_sub_shelf_row.html.erb_spec.rb`.

Specs:
- `spec/views/games/_collections_shelf.html.erb_spec.rb` — rewritten
  (16 examples) for the single-row layout. Covers happy / edge
  (empty input, composer-returned-nil) / flaw (no v1 / v2 remnants).
- `spec/requests/collections_spec.rb` — `+7` examples for
  `GET /collections/:id/games_pane` (200, Turbo Frame wrapper,
  link-to-show-page, alphabetical, empty state, 404 on bad slug,
  no layout, numeric-id resolution).
- `spec/requests/games_spec.rb` — 2 assertions updated (sub-shelf
  refs → tile refs); 1 new (`.collection-tile` count).
- `spec/system/games_index_spec.rb` — `Custom collections outer shelf`
  describe block rewritten + new `Collections modal flow` describe
  block (3 examples: href fallback navigation, pane-fragment listing,
  game tile click → game show page).

### Verification

- Touched specs green: 159 examples (`_collections_shelf` view +
  `collections` request + `games` request + `games_index` system),
  0 failures.
- Adjacent system specs green: `games_display_modes`,
  `games_steam_shelf` — 20 examples, 0 failures.
- Rubocop clean on the 7 touched Ruby files (controllers, routes,
  4 spec files).
- Brakeman clean: 0 warnings, 0 errors.

### Conflict handling note

A sibling `games-polish v2` dispatch had already landed (heading
rename to `collections`, composer wiring via
`Games::PrepareCollectionsForShelf`, demo seeds). This restructure
builds on top — no composer changes, no seed changes, no heading
changes (we kept the `collections` <h2>). The orphaned 01c-v2
sub-shelf partials and their view specs were deleted as part of
this dispatch since the new tile-per-collection design replaces
them entirely.

## 2026-05-11 — `/games` polish bundle (rails-impl dispatch)

User-driven follow-up after the 01c-v2 + display-mode pass. Ten fixes
bundled (Img 42 / 43 / 44 / 47 reference shots). No new migrations
needed — the speculative `games.status` column from the dispatch note
does not exist in this schema (`status` was only a computed token in
the list-mode partial, not a persisted column).

### Fixes applied

- Fix 1 — Drop the outer `<h2>genres</h2>` heading on the Genres
  outer shelf. Per-sub-shelf `<h3>` headings carry the label now.
- Fix 2 — Insert an `<hr class="hairline">` between the genres outer
  shelf and the collections outer shelf, conditional on BOTH shelves
  rendering. Hairline lives in `index.html.erb`, not the individual
  partials.
- Fix 3 — Drop the `status` column from the list-mode table. No
  migration: the column was a computed token (`recorded` /
  `released` / `scheduled` / `unreleased`) rendered inline, not a
  persisted field. The `released` column carries the same signal.
- Fix 4 — Rename the `release year` column to `released`; render the
  full `mm-dd-yyyy` date from `Game#release_date` (em-dash when nil).
  Right-aligned via `.num`.
- Fix 5 — App-wide retire of the `★` star glyph on the rating display
  (`_tile.html.erb`, `_list_mode.html.erb` — show page already used
  `NN / 100`). New `GamesHelper#game_rating_display(game)` returns
  `<NN>/100`. `STAR_GLYPH` constant preserved for any future surface.
- Fix 6 — Title rendered bold (`.not-released` class) when
  `release_date` is nil or strictly in the future. Applied to the
  grid tile and the list-mode title cell.
- Fix 7 — Fix duplicate-cover-fallback rendering. The bug: both
  light + dark fallback `<img>` tags carried inline `display: block`,
  which won the cascade over the class-level
  `.game-cover-fallback--dark { display: none; }` rule and rendered
  BOTH SVGs visibly stacked. Fix: remove inline `display: block` from
  the fallback images, absolute-position them so they overlap in one
  slot (`_tile.html.erb`, `_igdb_cover.html.erb`). Scoped CSS rules
  in `_list_mode.html.erb` hide the off-theme variant for the list
  cover cell.
- Fix 8 — `<h2>all games</h2>` renamed to `<h2>all</h2>` across
  grid / list / shelves-by-letter modes.
- Fix 9 — `.num` class on the `released` + `rating` headers and
  cells; scoped CSS rule right-aligns them.
- Fix 10 — Bulk-select column in front of the list-mode table — a
  bracketed `[ ]` glyph per row. List mode only; grid + shelves-by-
  letter modes do not get the column. Bulk-action wiring itself is a
  separate dispatch.

### Files touched

App:
- `app/helpers/games_helper.rb` — new `game_rating_display(game)`;
  `rating_segment` rewritten to return `<NN>/100` instead of
  `★ <NN>`; docs updated.
- `app/views/games/_genres_shelf.html.erb` — dropped the outer
  `<h2>genres</h2>` heading (Fix 1).
- `app/views/games/index.html.erb` — conditional
  `<hr class="hairline">` between the two outer shelves (Fix 2).
- `app/views/games/_list_mode.html.erb` — full rewrite for Fixes
  3 / 4 / 5 / 6 / 8 / 9 / 10. Drops the `status` column, renames
  `release year` → `released` (full date), renders rating as
  `<NN>/100`, bolds not-yet-released titles, adds `.num` + `[ ]`
  checkbox column, scopes a new CSS rule that hides the off-theme
  fallback variant inside the cover cell.
- `app/views/games/_grid_mode.html.erb` — `<h2>all games</h2>` →
  `<h2>all</h2>` (Fix 8).
- `app/views/games/_shelves_by_letter_mode.html.erb` —
  `<h2>all games</h2>` → `<h2>all</h2>` (Fix 8).
- `app/views/games/_tile.html.erb` — bolds not-yet-released titles
  (Fix 6); fallback images switched to absolute-positioned overlap
  (Fix 7); doc comments refreshed.
- `app/views/shared/_igdb_cover.html.erb` — drop inline
  `display: block` from the dual fallback `<img>` tags so the class
  rule wins (Fix 7).

Specs:
- `spec/helpers/games_helper_spec.rb` — rewritten. 22 examples
  covering `format_game_rating`, new `game_rating_display`, and
  `game_meta_line` (post-polish layout `<NN>/100 · <YYYY>`).
- `spec/views/games/_tile.html.erb_spec.rb` — rewritten. 40
  examples covering happy / sad / edge for the new rating format,
  Fix 6 bold behavior, Fix 7 fallback-overlap behavior, variant
  defaults, linking, native title attribute.
- `spec/views/games/_list_mode.html.erb_spec.rb` — rewritten. 31
  examples covering the new column order, Fix 3 (status dropped),
  Fix 4 (full date column), Fix 5 (rating format), Fix 6 (bold),
  Fix 9 (.num), Fix 10 (bulk-select), Fix 7 (CSS hides off-theme
  fallback inside the cell).
- `spec/views/games/_grid_mode.html.erb_spec.rb` — Fix 8 assertion.
- `spec/views/games/_genres_shelf.html.erb_spec.rb` — Fix 1
  assertion (no outer `<h2>genres</h2>`).
- `spec/views/shared/_igdb_cover.html.erb_spec.rb` — Fix 7
  assertion (no inline `display: block` on fallback images).
- `spec/requests/games_spec.rb` — 2 assertion swaps (`all games` →
  `all`, no outer `<h2>genres</h2>`); 2 new assertions (hairline
  rendered between the shelves; hairline absent when only one
  shelf renders).
- `spec/system/games_steam_shelf_spec.rb` — Fix 8 assertion.
- `spec/system/games_index_spec.rb` — Fix 1 assertion swap (h2
  → no h2; lowercase h3 list intact).
- `spec/system/games_display_modes_spec.rb` — Fix 3 + Fix 4 +
  Fix 8 + Fix 10 column-order swap.

### Verification

- Targeted game specs: 452 examples, 0 failures.
  - `spec/views/games/` (all view specs)
  - `spec/system/games_*` (display modes, steam shelf, index,
    multi-version, platform ownerships)
  - `spec/requests/games_spec.rb`, `spec/requests/games/`,
    `spec/requests/games_json_spec.rb`,
    `spec/requests/games_show_meta_block_spec.rb`
  - `spec/helpers/games_helper_spec.rb`
- Rubocop clean on the 11 touched Ruby files.
- Brakeman: 0 warnings, 0 errors (8 checks against the full app —
  no new findings from this dispatch).

### Open follow-ups

- Bulk-action wiring for the new list-mode `[ ]` checkbox column —
  the column renders but the action surface is a separate dispatch
  (architect note: pair with the existing `/deletions/:type/:ids`
  framework once the wiring lands).
- The `STAR_GLYPH` constant is preserved in `GamesHelper` but has no
  remaining caller; the documentation comment now records this. A
  follow-up dispatch can remove it once the team confirms no
  out-of-tree consumer.
