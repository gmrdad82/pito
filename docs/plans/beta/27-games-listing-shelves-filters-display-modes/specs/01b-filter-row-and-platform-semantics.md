# 01b — Filter Row and Platform Semantics

> Depends on `01a` (per-platform ownership join table). Introduces the
> multi-select filter row on `/games` between the top shelves (`01c`) and the
> main listing. Filter state lives in a single CSV URL param (`?filters=`).
> Chips toggle on click. Platform tokens carry ownership-aware semantics locked
> verbatim from the Mobile-driven source directive (see "Locked semantics"
> below).

---

## Goal

Add a horizontal multi-select filter row to `/games`, sitting BELOW the Genres
and Collections shelves (`01c`) and ABOVE the main listing (grid / list /
shelves-by-letter from `01d`). The row is ten chips wide:

```
[recorded] [released] [owned] [not owned] [scheduled] [ps5] [switch2] [steam] [gog] [epic]
```

State lives in the URL as `?filters=token1,token2,...`. Clicking a chip toggles
it. An empty filter set shows every game. A `[clear all]` bracketed link
appears whenever at least one chip is active. Platform tokens are
ownership-aware: their meaning changes depending on whether `owned` is also
active.

This sub-spec is the SECOND of three concurrent surfaces (`01b`, `01c`, `01d`)
that all attach to the `/games` index. It must NOT touch:

- The shelves above it (`01c` owns those partials).
- The display-mode switcher and the three mode partials (`01d` owns those).
- The ownership editor on `Game#show` / `Game#edit` (`01f` owns that).
- The MCP / CLI filter parity (`01g` owns that).

---

## Files touched

Component + helper:

- `app/components/games/filter_row_component.rb`
- `app/components/games/filter_row_component.html.erb`
- `app/components/games/filter_chip_component.rb`
- `app/components/games/filter_chip_component.html.erb`
- `app/helpers/games/filters_helper.rb`

Query object:

- `app/queries/games/filter.rb`

Controller:

- `app/controllers/games_controller.rb` — `#index` reads `params[:filters]`
  (CSV), parses via the helper, dispatches to the query object.

Model scope additions on `Game`:

- `app/models/game.rb` — adds `:recorded`, `:released`, `:scheduled`,
  `:on_platform`, `:scheduled_on`, `:released_on`. (The `:owned`, `:not_owned`,
  `:owned_on` scopes already landed in `01a`.)

Views:

- `app/views/games/index.html.erb` — renders the filter row immediately below
  the two shelves and immediately above the mode-branched listing.

Specs:

- `spec/models/game_spec.rb` — `recorded`, `released`, `scheduled`,
  `on_platform`, `scheduled_on`, `released_on` scope examples.
- `spec/queries/games/filter_spec.rb` — load-bearing matrix: every
  (`owned` × platform) pair across all five platforms, plus status chips,
  plus combinations.
- `spec/components/games/filter_row_component_spec.rb`
- `spec/components/games/filter_chip_component_spec.rb`
- `spec/helpers/games/filters_helper_spec.rb`
- `spec/requests/games_spec.rb` — URL state in and out, controller integration.
- `spec/system/games_index_spec.rb` — click-through chip interaction (additive
  examples; do NOT replace the shelf-system examples landed in `01c`).

---

## Locked semantics (verbatim from Mobile directive)

These statements are the LAW for this sub-spec. The query object, every spec,
the request specs, and the system spec must each assert behaviour that matches
these statements without paraphrase or interpretation.

> **Statement P-1.** If `owned` is unchecked and platform-X is checked: matches
> games that are scheduled OR released on platform-X, regardless of ownership
> state.

> **Statement P-2.** If `owned` is checked and platform-X is checked: matches
> games owned specifically on platform-X (the user's ownership row for that
> game on platform-X must exist).

Worked example, verbatim:

> Game X released on PS5 + Switch 2; user owns on PS5.
>
> - `owned` unchecked, `ps5` checked → matches.
> - `owned` unchecked, `switch2` checked → matches (game is scheduled/released
>   on Switch 2).
> - `owned` checked, `ps5` checked → matches.
> - `owned` checked, `switch2` checked → does NOT match.

Corollaries (architect-derived from P-1 and P-2; flagged as "Open questions"
below for the master agent to confirm before `01g` ships):

- **C-1.** `not_owned` + platform-X — the source directive does not enumerate
  this case. Locked default for `01b`: match games with zero ownership rows
  AND released OR scheduled on platform-X (the same release/schedule check as
  P-1, narrowed to the not-owned set).
- **C-2.** Multiple platform tokens within the same bucket OR together. With
  `owned` unchecked, `[ps5, switch2]` matches games released or scheduled on
  PS5 OR Switch 2. With `owned` checked, `[ps5, switch2]` matches games owned
  on PS5 OR owned on Switch 2.
- **C-3.** `owned` + `not_owned` together is a contradiction. Locked: query
  returns `Game.none`; the filter row renders a muted contradiction notice
  (`(owned and not owned together — no matches)`). No JS dialog, no red.

---

## URL contract

```
GET /games?filters=recorded,ps5,owned
```

- `filters` is a single comma-separated list of canonical tokens.
- Order is irrelevant — `?filters=ps5,owned` and `?filters=owned,ps5` are
  identical results AND render identically (controller normalises before
  building chip hrefs).
- Duplicates are de-duplicated server-side.
- Unknown tokens are silently dropped from the active set. The dropped tokens
  do NOT appear in the chip-link hrefs (no echo-back of garbage).
- An empty `filters=` (or no `filters` param at all) → show all games (locked
  decision).

Canonical tokens (the only ten valid values):

```
recorded
released
scheduled
owned
not_owned
ps5
switch2
steam
gog
epic
```

The on-screen chip label uses a space (`not owned`) where the canonical token
uses an underscore (`not_owned`). The helper converts at the boundary.

yes / no boundary: no external boolean inputs on this URL (every token is a
string). Future MCP / CLI mirroring in `01g` still observes the rule for any
boolean argument it introduces.

---

## Model + scope shape

### New scopes on `Game`

```ruby
# Status scopes
scope :recorded,  -> { where(id: Video.select(:game_id).distinct) }
scope :released,  -> { where("first_release_date <= ?", Time.current) }
scope :scheduled, -> { where("first_release_date > ?", Time.current) }

# Platform release/schedule scopes — built on the IGDB-reported
# `platforms_available` association (Phase 14 join `game_platforms`), NOT
# the `01a` ownership association. The two are distinct: "available on" is
# IGDB metadata, "owned on" is the user's library.
scope :on_platform,    ->(slug) { joins(:platforms_available).where(platforms: { slug: slug }).distinct }
scope :released_on,    ->(slug) { released.on_platform(slug) }
scope :scheduled_on,   ->(slug) { scheduled.on_platform(slug) }
```

### Existing scopes consumed from `01a`

```ruby
scope :owned       # at least one game_platform_ownerships row
scope :not_owned   # zero ownership rows
scope :owned_on    # owned on a specific platform slug
```

### Notes

- `Game#platforms_available` is the existing has-many `:platforms_available,
through: :game_platforms, source: :platform` association declared on `Game`
  (Phase 14 §1). The `01b` scopes ride on it; no new association.
- The `where(platforms: { slug: ... })` form is safe here — the legacy
  `games.platforms` jsonb column does not collide for `on_platform` because
  the join is explicit on `:platforms_available`. Where it might still collide
  (Postgres treats `platforms:` as ambiguous in some Rails 8 edge cases), the
  query object uses an explicit `'"platforms"."slug" = ?'` literal — matching
  the pattern used by `Game.owned_on` from `01a`.

---

## Query object — `Games::Filter`

`Games::Filter.new(scope: Game.all, tokens: %w[ps5 owned]).results` returns an
`ActiveRecord::Relation`.

### Composition rules (this is the spec; the spec pyramid must verify each
rule)

1. Partition the incoming tokens into four buckets:
   - **Status**: `recorded`, `released`, `scheduled`
   - **Ownership**: `owned`, `not_owned`
   - **Platform**: `ps5`, `switch2`, `steam`, `gog`, `epic`
   - **Unknown**: anything else — dropped, not echoed in chip hrefs.

2. Buckets are intersected with AND.

3. Within the Status bucket, multiple tokens OR together (`recorded OR
released`).

4. Within the Platform bucket, multiple tokens OR together. The OR semantics
   are evaluated per the ownership-bucket state (see step 6).

5. Ownership bucket:
   - `[]` (neither owned nor not_owned): no ownership restriction; the
     Platform bucket follows statement P-1 (release-or-schedule on the
     platform).
   - `[owned]`: restrict to games with at least one ownership row; the
     Platform bucket follows statement P-2 (owned specifically on the
     platform).
   - `[not_owned]`: restrict to games with zero ownership rows; the Platform
     bucket follows corollary C-1 (released-or-scheduled on the platform AND
     not owned anywhere).
   - `[owned, not_owned]`: contradiction → return `Game.none`. The
     `contradiction?` predicate on the query exposes this for the component.

6. Apply the Platform bucket using the precedence locked above. If the bucket
   is empty, the Ownership bucket alone applies. If the bucket is non-empty,
   each platform token is mapped to a relation via:
   - P-1 mode (Ownership bucket empty): `Game.on_platform(slug)`.
   - P-2 mode (`owned` active): `Game.owned_on(slug)`.
   - C-1 mode (`not_owned` active): `Game.not_owned.on_platform(slug)`.

   Multiple platform relations are unioned by `id` (subquery shape — use
   `where(id: rel_a.select(:id)).or(where(id: rel_b.select(:id)))` or the
   single `where(id: ids_array)` shape; the spec asserts identical results
   regardless of the chosen tactic).

7. The query is deterministic: token order does not affect the result set.

### Public surface

- `Games::Filter.new(scope:, tokens:)` — accepts an
  `ActiveRecord::Relation` (typically `Game.all`) and an array of canonical
  string tokens. The constructor normalises (downcase, strip, de-dupe, drop
  unknown).
- `#results` — returns the filtered `ActiveRecord::Relation`. Stable identity:
  calling `#results` twice returns the same SQL (the relation is built once
  and memoised).
- `#contradiction?` — returns `true` when the Ownership bucket contains both
  `owned` and `not_owned`. `#results` in that state returns `Game.none`.
- `#active_tokens` — returns the de-duped, sorted-as-input set of recognised
  tokens (for the component's `[clear all]` visibility check).
- `#dropped_tokens` — returns the set of tokens that were dropped because they
  were not canonical. Useful for the component's dev-mode warning and for
  request-spec assertions.

### Constants

```ruby
module Games
  class Filter
    STATUS_TOKENS    = %w[recorded released scheduled].freeze
    OWNERSHIP_TOKENS = %w[owned not_owned].freeze
    PLATFORM_TOKENS  = %w[ps5 switch2 steam gog epic].freeze
    CANONICAL_TOKENS = (STATUS_TOKENS + OWNERSHIP_TOKENS + PLATFORM_TOKENS).freeze
  end
end
```

The platform tokens map to platform slugs 1:1; the slug is the token (locked
by `01a` seeds — `ps5`, `switch2`, `steam`, `gog`, `epic`).

---

## Component decomposition

### `Games::FilterRowComponent`

Inputs:

- `active_tokens: Array<String>` — the canonical (recognised) tokens currently
  active.
- `dropped_tokens: Array<String>` — for an optional dev-mode warning (rendered
  only in `Rails.env.development?`; never in production).
- `request_path: String` — the path to compose chip hrefs against. Always
  `/games` in practice, but injected for testability.
- `query_string_overrides: Hash` — other URL params that must be preserved on
  every chip link (e.g., `display=list` from `01d`). The component never
  invents this — the controller threads them through.
- `contradiction: Boolean` — true when the query object reports
  `contradiction?`. Renders the contradiction notice.

Renders:

- A single horizontal row containing one `FilterChipComponent` per canonical
  token, in the locked left-to-right order:
  `recorded released owned not_owned scheduled ps5 switch2 steam gog epic`.
- A `[clear all]` bracketed link to the right (or below on narrow screens —
  CSS responsibility, not component logic) when `active_tokens.any?`. The
  link points at `request_path` with `filters=` cleared and
  `query_string_overrides` preserved.
- A muted contradiction notice (`(owned and not owned together — no matches)`)
  immediately under the row when `contradiction == true`. Class:
  `text-muted` (no red — red is reserved for destructive actions, per
  project rule).

The component renders NO JavaScript. No `data-turbo-confirm`. No
`window.confirm`. Chip toggling is pure GET-link navigation; URL-state-driven.

### `Games::FilterChipComponent`

Inputs:

- `token: String` — must be a canonical token. Constructor raises
  `ArgumentError` otherwise.
- `active: Boolean`
- `request_path: String`
- `active_tokens: Array<String>` — current state (so the chip can compute its
  toggled-into / toggled-out-of href).
- `query_string_overrides: Hash` — non-filter URL params to preserve.

Renders one bracketed link `[label]`. The label is the on-screen form:

- `not_owned` → `not owned`
- everything else → identical to the canonical token.

Active chips render with the `chip--active` style class (no red). Inactive
chips render as standard bracketed links per `docs/design.md`.

The `href` is `request_path` with:

- `filters=` set to the active-tokens set with `token` toggled in or out.
- Every key in `query_string_overrides` preserved.
- `filters=` omitted entirely when the toggled set is empty (no
  `?filters=` trailing dangle).

The component never emits anything beyond an `<a>` element with the bracketed
text and the appropriate class — no buttons, no forms, no JS.

---

## Helper — `Games::FiltersHelper`

Module mixed into `GamesController` and exposed to views. Public surface:

- `parse_filter_tokens(raw)` — accepts the raw `params[:filters]` value
  (string, nil, or array — Rails sometimes hands an array if the user smuggles
  `?filters[]=`). Returns the canonical array of recognised tokens, de-duped,
  preserving input order; unknown tokens dropped.
- `parse_dropped_tokens(raw)` — returns the unrecognised tokens. Used by the
  component's dev-mode warning and by request specs.
- `toggle_filter(active_tokens, token)` — returns a new array with `token`
  removed if present, appended if absent. Used by the chip component to build
  hrefs.
- `chip_label(token)` — converts canonical → on-screen label
  (`not_owned` → `not owned`, others pass through).

The helper has no side-effects, no DB access, no Rails-cache access.

---

## Controller integration

`GamesController#index` (existing action) gains:

```ruby
# Phase 27 §01b — filter row state read from a single CSV param.
@filter_tokens         = parse_filter_tokens(params[:filters])
@dropped_filter_tokens = parse_dropped_tokens(params[:filters])
@filter_query          = Games::Filter.new(scope: @all_games, tokens: @filter_tokens)
@all_games             = @filter_query.results
@filter_contradiction  = @filter_query.contradiction?
```

The filter query MUST compose AFTER the existing `?genre=` / `?collection=`
filter narrowing (`01c`) and BEFORE the per-mode partitioning into
grid/list/shelves-by-letter (`01d`). That ordering means:

1. Start with `Game.all`.
2. Narrow by `?genre=` / `?collection=` (already in the controller — `01c`).
3. Narrow by the filter row (`@filter_tokens`).
4. Hand `@all_games` to the mode partial (`01d`).

The controller MUST NOT mutate `@filter_tokens` after building the query.

The controller passes `query_string_overrides` to the filter-row component:
`{ genre: params[:genre], collection: params[:collection], display: params[:display] }.compact_blank`.
This is what keeps every chip link from clobbering the rest of the URL state.

---

## View integration

`app/views/games/index.html.erb` renders the filter row in exactly one place
— between the shelves and the listing — by adding a single line:

```erb
<%= render Games::FilterRowComponent.new(
      active_tokens:           @filter_tokens,
      dropped_tokens:          @dropped_filter_tokens,
      request_path:            games_path,
      query_string_overrides:  { genre: params[:genre], collection: params[:collection], display: params[:display] }.compact_blank,
      contradiction:           @filter_contradiction
    ) %>
```

No other view changes. The mode partials (`_grid_mode`, `_list_mode`,
`_shelves_by_letter_mode`) already consume `@all_games`; the filter object has
already narrowed it before they render.

---

## Spec pyramid

This section is the load-bearing surface. Per project rule D
(`docs/agents/architect.md`), the sweep is mandatory. The matrix
(`spec/queries/games/filter_spec.rb`) is the single point where every pair
combination of (`owned` × platform-X) is asserted.

### Model — `spec/models/game_spec.rb` (additions)

Happy:

- `Game.recorded` returns games with at least one linked Video.
- `Game.released` returns games with `first_release_date <= Time.current`.
- `Game.scheduled` returns games with `first_release_date > Time.current`.
- `Game.on_platform('ps5')` returns games whose `platforms_available`
  association includes PS5.
- `Game.released_on('ps5')` is the intersection of `released` and
  `on_platform('ps5')`.
- `Game.scheduled_on('ps5')` is the intersection of `scheduled` and
  `on_platform('ps5')`.

Sad:

- `Game.released` excludes games with `nil` `first_release_date`.
- `Game.scheduled` excludes games with `nil` `first_release_date`.
- `Game.on_platform('nonexistent')` returns an empty relation, does not raise.

Edge:

- a game with `first_release_date == Time.current` is in `released`
  (boundary inclusive on past side).
- a game with `first_release_date == Time.current + 1.second` is in
  `scheduled`.
- `Game.recorded` returns distinct rows even when a game has many Videos.
- `Game.on_platform('ps5')` returns distinct rows when a game is on PS5 once
  but joins multiply (defensive `.distinct`).

Flaw:

- Time freezes consistently across a single query (use `Timecop.freeze` or
  `ActiveSupport::Testing::TimeHelpers#travel`).
- SQL injection via a crafted slug → the bound-parameter form rejects it
  cleanly; the spec asserts the scope returns an empty relation, not a 500.

### Query — `spec/queries/games/filter_spec.rb` (load-bearing matrix)

**Fixture matrix.** Build seven games with explicit ownership + release
shape:

| Game | Available on (IGDB) | Owned on    | Released?              | Has Video? |
| ---- | ------------------- | ----------- | ---------------------- | ---------- |
| A    | PS5, Switch 2       | PS5         | yes (past)             | no         |
| B    | PS5, Steam          | (none)      | yes (past)             | no         |
| C    | Switch 2            | (none)      | no (scheduled, future) | no         |
| D    | PS5, Switch 2       | PS5         | no (scheduled, future) | no         |
| E    | Steam               | Steam       | yes (past)             | yes        |
| F    | GOG                 | (none)      | yes (past)             | no         |
| G    | Epic                | Epic        | yes (past)             | no         |

This matrix MUST be built via factories declared in `spec/factories/games.rb`
+ `spec/factories/game_platforms.rb` + `spec/factories/game_platform_ownerships.rb`
+ `spec/factories/videos.rb`. The factories ALREADY exist (`01a` + Phase
14); the spec composes them.

#### Single-token tests (happy)

- `[]` → A, B, C, D, E, F, G.
- `[recorded]` → E.
- `[released]` → A, B, E, F, G.
- `[scheduled]` → C, D.
- `[owned]` → A, D, E, G.
- `[not_owned]` → B, C, F.

#### Single platform token, `owned` UNCHECKED (statement P-1)

For each of the five platforms, the result is "all games released OR
scheduled on that platform, regardless of ownership state":

- `[ps5]` → A (released on PS5), B (released on PS5), D (scheduled on
  PS5). Expected: A, B, D.
- `[switch2]` → A (released on Switch 2), C (scheduled on Switch 2), D
  (scheduled on Switch 2). Expected: A, C, D.
- `[steam]` → B (released on Steam), E (released on Steam). Expected: B, E.
- `[gog]` → F (released on GOG). Expected: F.
- `[epic]` → G (released on Epic). Expected: G.

#### Single platform token, `owned` CHECKED (statement P-2)

For each of the five platforms, the result is "games owned on that platform":

- `[owned, ps5]` → A, D.
- `[owned, switch2]` → ∅ (no game owned on Switch 2 in the fixture).
- `[owned, steam]` → E.
- `[owned, gog]` → ∅.
- `[owned, epic]` → G.

#### Single platform token, `not_owned` CHECKED (corollary C-1)

For each of the five platforms, the result is "games with zero ownership rows
AND released OR scheduled on that platform":

- `[not_owned, ps5]` → B (released on PS5, not owned anywhere).
- `[not_owned, switch2]` → C (scheduled on Switch 2, not owned anywhere).
- `[not_owned, steam]` → B (released on Steam, not owned anywhere).
- `[not_owned, gog]` → F (released on GOG, not owned anywhere).
- `[not_owned, epic]` → ∅ (G is owned on Epic; nothing else is on Epic).

#### Pair combinations of `owned` × platform-X (matrix, happy)

This is the locked acceptance matrix for the spec. Every cell must be a
distinct `it` block. The reviewer will count the cells.

| Tokens                  | Expected | Citation |
| ----------------------- | -------- | -------- |
| `[ps5]`                 | A, B, D  | P-1      |
| `[switch2]`             | A, C, D  | P-1      |
| `[steam]`               | B, E     | P-1      |
| `[gog]`                 | F        | P-1      |
| `[epic]`                | G        | P-1      |
| `[owned, ps5]`          | A, D     | P-2      |
| `[owned, switch2]`      | ∅        | P-2      |
| `[owned, steam]`        | E        | P-2      |
| `[owned, gog]`          | ∅        | P-2      |
| `[owned, epic]`         | G        | P-2      |
| `[not_owned, ps5]`      | B        | C-1      |
| `[not_owned, switch2]`  | C        | C-1      |
| `[not_owned, steam]`    | B        | C-1      |
| `[not_owned, gog]`      | F        | C-1      |
| `[not_owned, epic]`     | ∅        | C-1      |

**That is fifteen pair-combination examples** (5 platforms × 3 ownership
states: unchecked / owned / not_owned). All fifteen MUST be present in
`spec/queries/games/filter_spec.rb`.

#### Worked-example verbatim assertion

A dedicated `describe "Mobile directive worked example"` block reproduces the
source-note's Game-X example using a fresh `let(:game_x)` whose shape matches
the directive ("released on PS5 + Switch 2, owned on PS5"):

- `owned` unchecked, `ps5` checked → matches game_x.
- `owned` unchecked, `switch2` checked → matches game_x.
- `owned` checked, `ps5` checked → matches game_x.
- `owned` checked, `switch2` checked → does NOT match game_x.

These four examples are MANDATORY and assert against game_x specifically (not
against the A–G fixture matrix). They protect the spec from accidental
regressions in the locked semantics.

#### Multi-platform token (corollary C-2)

- `[ps5, switch2]` (owned unchecked) → A, B, C, D (union of P-1 sets).
- `[owned, ps5, switch2]` → A, D (union of P-2 sets — A owned PS5, D owned
  PS5; switch2 contributes ∅).
- `[not_owned, ps5, switch2]` → B, C (union of C-1 sets).

#### Combination with status tokens

- `[recorded, owned]` → E.
- `[recorded, ps5]` → ∅ (E has no PS5 release).
- `[released, owned, ps5]` → A.
- `[scheduled, ps5]` → D (P-1 narrowed to scheduled: D is scheduled on PS5).
- `[scheduled, owned, ps5]` → D (P-2 narrowed to scheduled).
- `[scheduled, not_owned, ps5]` → ∅ (no game is scheduled on PS5 AND not
  owned anywhere; D is owned on PS5; C is scheduled but only on Switch 2).
- `[scheduled, not_owned, switch2]` → C.

#### Status-bucket OR semantics

- `[released, scheduled]` → A, B, C, D, E, F, G (union of released and
  scheduled; all games in the fixture have a release date one way or the
  other). The OR within the status bucket is asserted explicitly.
- `[recorded, scheduled]` → C, D, E (E recorded; C, D scheduled).

#### Contradiction (sad)

- `[owned, not_owned]` → `Game.none`. `filter.contradiction?` returns true.
  `filter.results` is an empty relation.
- `[owned, not_owned, ps5]` → contradiction wins; result is `Game.none`.

#### Edge

- `[ps5, ps5]` (duplicate) de-dupes to `[ps5]`; identical result.
- `[PS5]` (uppercase) → normalised to `ps5`; identical result.
- ` [ps5] ` (whitespace around) → trimmed; identical result.
- `[]` → all games (A–G); `filter.contradiction?` is false.
- token order does not affect results — assert via property-style examples
  iterating over `[[ "owned", "ps5" ], [ "ps5", "owned" ]]` and confirming the
  result sets are equal.

#### Flaw

- 100-token input does not blow the stack; unknown tokens are dropped; the
  spec asserts `filter.dropped_tokens.size == 100 - canonical_count`.
- SQL-injection-shaped token (`"ps5'; DROP TABLE games; --"`) is rejected by
  the canonical-token whitelist; `filter.dropped_tokens` includes the
  payload; `filter.results` is identical to the un-payloaded filter.
- The query is composable with `.where` chains (e.g.,
  `filter.results.where("id > ?", 0)` is a valid relation), proving
  `#results` returns an `ActiveRecord::Relation` and not an array.
- `#results` is memoised — calling it twice produces the same SQL fingerprint
  (`to_sql` equality).

### Component — `spec/components/games/filter_row_component_spec.rb`

Happy:

- renders all ten canonical chips in the locked order
  (`recorded released owned not_owned scheduled ps5 switch2 steam gog epic`).
- renders `[clear all]` when at least one chip is active.
- the `[clear all]` href clears `filters=` from the URL and preserves every
  `query_string_overrides` key.
- contradiction notice renders when `contradiction: true` (text:
  `(owned and not owned together — no matches)`).

Sad:

- does NOT render `[clear all]` when `active_tokens == []`.
- does NOT render the contradiction notice when `contradiction: false`.
- raises `ArgumentError` when initialised with a chip token outside the
  canonical set.

Edge:

- preserves `display=list` in chip hrefs when passed via
  `query_string_overrides`.
- preserves `genre=open-world` in chip hrefs when passed via
  `query_string_overrides`.
- renders no chip in red (defensive — red reserved for destructive).
- contradiction notice uses `text-muted` class, NOT a danger class.

Flaw:

- never emits `data-turbo-confirm`, `data-confirm`, `onclick`, or any inline
  script attribute. The spec asserts via DOM scan.
- never invokes `window.confirm` / `alert` / `prompt` (the rendered HTML
  contains none of those substrings).

### Component — `spec/components/games/filter_chip_component_spec.rb`

Happy:

- renders `[ps5]` link with `?filters=ps5` when inactive and the request has
  no filters.
- renders `[ps5]` link toggling the chip OFF when it is currently active
  (clicking takes the user back to `?filters=` cleared).
- toggling one chip preserves the others — `[ps5]` clicked while `[owned]` is
  active yields `?filters=owned`.
- displays `not owned` (with space) for `not_owned` token.
- the on-screen label for every other canonical token matches the canonical
  string verbatim.

Sad:

- raises `ArgumentError` if `token` is not in the canonical set.
- raises `ArgumentError` if `request_path` is nil or empty.

Edge:

- preserves `display=list` on the href when passed via
  `query_string_overrides`.
- preserves `genre=<slug>` and `collection=<slug>` on the href when passed.
- when toggling DROPS the last active filter, the link omits `filters=`
  entirely (no `?filters=` trailing dangle).
- when active, the chip carries the `chip--active` CSS class; when inactive,
  it does not.
- the chip is a single `<a>` element (not a button, not a form).

Flaw:

- HTML-escapes any raw token (defense-in-depth — the constructor whitelist
  already rejects non-canonical tokens, but the spec asserts the rendered
  HTML escapes `<`, `>`, `&` on every text node).

### Helper — `spec/helpers/games/filters_helper_spec.rb`

Happy:

- `parse_filter_tokens("ps5,owned")` → `["ps5", "owned"]`.
- `parse_filter_tokens("")` → `[]`.
- `parse_filter_tokens(nil)` → `[]`.
- `parse_filter_tokens(["ps5", "owned"])` → `["ps5", "owned"]` (array input
  accepted).
- `toggle_filter(["ps5"], "ps5")` → `[]`.
- `toggle_filter(["ps5"], "owned")` → `["ps5", "owned"]`.
- `chip_label("not_owned")` → `"not owned"`.
- `chip_label("ps5")` → `"ps5"`.

Sad:

- `parse_filter_tokens("ps5, owned")` strips whitespace.
- `parse_filter_tokens("ps5,bogus")` drops `bogus`.
- `parse_dropped_tokens("ps5,bogus,owned")` → `["bogus"]`.

Edge:

- `parse_filter_tokens("ps5,ps5,owned")` de-duplicates → `["ps5", "owned"]`.
- `parse_filter_tokens("PS5")` normalises case → `["ps5"]`.
- `parse_filter_tokens(",ps5,,owned,")` ignores empty segments →
  `["ps5", "owned"]`.

### Request — `spec/requests/games_spec.rb` (additions)

Happy:

- `GET /games` → 200, no filter applied, all games visible in the response
  body.
- `GET /games?filters=ps5` → 200, filter applied; HTML contains the active
  chip CSS class on `[ps5]`; `[clear all]` link is present.
- `GET /games?filters=ps5,owned` → 200, narrower set; both `[ps5]` and
  `[owned]` render active.
- `GET /games?filters=owned` → 200; visible game set matches `Game.owned`.

Sad:

- `GET /games?filters=` (empty) → 200, treated as empty filter set; no
  `[clear all]`.
- `GET /games?filters=garbage` → 200, unknown token dropped; no `[clear all]`
  (since no canonical token is active); response body does not echo
  `garbage` anywhere (defense-in-depth XSS).
- `GET /games?filters=garbage,ps5` → 200, `[ps5]` active; `garbage` dropped;
  the rendered `[clear all]` href is `/games?filters=` (no `garbage` in it).

Edge:

- `GET /games?filters=owned,not_owned` → 200; renders contradiction notice;
  body excludes game tiles (the listing partial sees `Game.none`).
- `GET /games?filters=ps5&display=list` → 200; list mode renders; chip hrefs
  preserve `display=list`.
- `GET /games?filters=ps5&genre=action` → 200; genre filter (`01c`) and chip
  filter compose; chip hrefs preserve `genre=action`.
- `GET /games?filters=ps5,ps5,owned` → 200; de-duplicates; identical to
  `?filters=ps5,owned`.
- `GET /games?filters=PS5` (uppercase) → 200; normalised; identical to
  `?filters=ps5`.

Flaw:

- query string with 100 tokens does not 500.
- SQL-injection payload as a token (`"ps5'; DROP TABLE games; --"`) → 200;
  the response body does not contain the payload; the games table still
  exists post-request (assert via `Game.count` before/after).
- the response never sets `data-turbo-confirm` or any JS-confirm attribute on
  the filter row.

### System — `spec/system/games_index_spec.rb` (additive examples)

These are ADDED to the existing file landed by `01c`. Do not replace.

Happy:

- visiting `/games` with seed data, clicking `[ps5]` updates the URL to
  `?filters=ps5`; the chip is now styled active; the listing visibly
  narrows.
- clicking `[ps5]` a second time clears it; URL is `/games?filters=` (or
  stripped); listing returns to full set.
- `[clear all]` appears when at least one chip is active; clicking it clears
  the filter set; `[clear all]` disappears.
- composing chips: click `[ps5]` then `[owned]`; URL is
  `?filters=ps5,owned`; listing matches `[ps5, owned]` matrix expectation
  (A, D).

Sad:

- clicking `[owned]` then `[not owned]` renders the contradiction notice and
  an empty listing — page does not crash, no JS dialog.

Edge:

- the filter row preserves the `?display=` param (set by `01d`'s switcher)
  when a chip is toggled. Concretely: click `[list]` then click `[ps5]`;
  URL becomes `?filters=ps5&display=list` (order of params is not
  asserted, but both keys are present).
- the filter row preserves the `?genre=` param (set by `01c`'s shelves) when
  a chip is toggled.
- selecting all five platform chips without `owned` widens to the union of
  all release/schedule sets (matrix-confirmed: every game in A–G has at
  least one available platform → all visible).

Flaw:

- the page contains no `<script>` tag inserted by the filter row.
- no `data-turbo-confirm` anywhere on the row.

---

## yes / no boundary

No new external boolean inputs on `/games?filters=`. Every token is a string.
The hard rule still applies to MCP / CLI mirroring in `01g`.

---

## Friendly URL preservation

- `/games` route unchanged.
- `filters` query param is purely additive.
- No friendly slug routes affected.
- The component's chip-href computation does not touch the slug segment of
  any URL.

---

## Manual test recipe

1. `bin/dev`; open `http://localhost:3000/games`.
2. Observe the filter row sitting BELOW the Genres and Collections shelves
   and ABOVE the main listing. Ten chips render in this order:
   `[recorded] [released] [owned] [not owned] [scheduled] [ps5] [switch2]
   [steam] [gog] [epic]`. No chip is active. No `[clear all]` link.
3. Click `[ps5]`. URL becomes `/games?filters=ps5`. `[ps5]` renders with the
   active class. `[clear all]` appears. The listing narrows to the games
   released or scheduled on PS5 (regardless of ownership state).
4. Click `[owned]`. URL becomes `/games?filters=ps5,owned` (order may differ
   based on click sequence; both tokens present). The listing narrows
   further to games owned specifically on PS5.
5. Click `[ps5]` again. URL becomes `/games?filters=owned`. The listing
   widens to all owned games.
6. Click `[not owned]`. URL becomes `/games?filters=owned,not_owned`. The
   contradiction notice `(owned and not owned together — no matches)`
   renders, muted. The listing is empty. No JS dialog ever appears.
7. Click `[clear all]`. URL becomes `/games` (or `/games?filters=`). All
   chips inactive. The listing returns to the full set.
8. With `01d` shipped, click `[list]` top-right to switch display mode, then
   click `[ps5]`. URL is `/games?filters=ps5&display=list`. List mode
   renders with the filter applied. Reload the page — both the display
   mode and the filter persist.
9. With `01c` shipped, click a genre tile in the Genres shelf, then click
   `[owned]`. URL preserves both `?genre=<slug>` and `?filters=owned`.

State teardown: remove any `?filters=...` to return the listing to the full
set.

---

## Cross-stack scope

| Surface            | In scope for `01b`                                              |
| ------------------ | --------------------------------------------------------------- |
| Rails web `/games` | YES — component, helper, query object, controller, view, specs |
| Rails MCP          | NO — MCP filter parity ships in `01g`                           |
| `pito` CLI         | NO — CLI filter parity ships in `01g`                           |
| Cloudflare website | NO                                                              |

---

## Open questions (for the master agent)

1. **Corollary C-1 (`not_owned` + platform-X).** Source directive does not
   enumerate this case. Architect's reading: match games with zero ownership
   rows AND released-or-scheduled on the platform. Confirm before `01g` so
   MCP surface mirrors the same. (Locked default in this spec — flag a phase
   log entry if the master overrides.)
2. **Corollary C-3 contradiction rendering.** Render a muted notice (locked
   default) versus silently emit an empty listing. Architect chose notice for
   discoverability; the master may revisit.
3. **`recorded` semantics with draft Videos.** Should `Game.recorded` match
   any linked Video record, or only Videos in a `published` state? Architect
   leans "any Video" because the project has no `published` state on Video
   yet; revisit when video publication state lands.
4. **Boundary inclusiveness on `released`.** Locked: `<= Time.current` is
   `released`. A game whose `first_release_date` exactly equals "now" is in
   `released`, not `scheduled`. The spec asserts this; flag if the master
   prefers strict `<`.
5. **`platforms_available` association name.** This sub-spec assumes the
   existing Phase 14 `Game#platforms_available` (through `:game_platforms`,
   source: `:platform`). Confirm the name is still `platforms_available` at
   the time of dispatch — if the `01a` revamp renamed it, the scope code
   needs the new name.
6. **Order of platform tokens within the bucket.** Multiple platforms in the
   same bucket OR together (corollary C-2). The implementation may choose
   between `where(id: rel_a).or(where(id: rel_b))` and a single
   `where(id: union_ids_array)`. The spec asserts result equivalence, not
   the SQL shape — both are acceptable.

---

## References

- Source-of-truth Mobile directive (verbatim) — captured in the Phase 27
  `plan.md` "Locked decisions" §5 (platform filter precedence) and in the
  dispatch directive that produced this spec.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01a-per-platform-ownership-data-model.md`
  — provides `Game.owned`, `Game.not_owned`, `Game.owned_on(slug)`.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-genres-and-collections-shelves.md`
  — provides the genre/collection narrowing this sub-spec composes with.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01d-display-mode-switcher-and-three-modes.md`
  — provides the `?display=` param this sub-spec must preserve.
- `docs/agents/architect.md` — spec pyramid rule D, yes/no boundary rule E,
  bracketed-link rule A.
- `docs/design.md` — bracketed-link convention, monospace style, no red
  outside destructive actions.
- `CLAUDE.md` hard rules — no JS confirm, no `data-turbo-confirm`, yes/no
  boundary, bulk-as-foundation.
