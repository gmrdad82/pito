# Phase 27 — log

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
