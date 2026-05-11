# 01b — Filter Row and Platform Semantics

> Depends on `01a` (platform ownership join table). Introduces the multi-select
> filter row on `/games` and the platform-aware semantics from §2 of the source
> note. Filter state lives in URL params; chip clicks toggle individual filters.

---

## Goal

Add a horizontal filter row to `/games` (between the top shelves and the main
listing) with chips: `recorded`, `released`, `owned`, `not owned`, `scheduled`,
`ps5`, `switch2`, `steam`, `gog`, `epic`. Filter state encodes as
`?filters=token1,token2,...` in the URL. Chips toggle on click. A `[clear all]`
link appears when at least one filter is active. Platform filters apply with
ownership-aware precedence: owned games match only on owned platforms; unowned
scheduled games match on scheduled platforms.

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

- `app/controllers/games_controller.rb` (`#index` consumes the filter)

Model scope additions (Game):

- `app/models/game.rb` (`recorded`, `released`, `scheduled` scopes; the `owned`,
  `not_owned`, `owned_on` scopes come from `01a`)

Views:

- `app/views/games/index.html.erb` (renders the component)

Specs:

- `spec/models/game_spec.rb` (filter scopes)
- `spec/queries/games/filter_spec.rb` (full matrix, the load-bearing spec)
- `spec/components/games/filter_row_component_spec.rb`
- `spec/components/games/filter_chip_component_spec.rb`
- `spec/helpers/games/filters_helper_spec.rb`
- `spec/requests/games_spec.rb` (URL state + chip toggle)
- `spec/system/games_index_spec.rb` (chip interaction)

---

## Model + filter shape

### URL contract

```
GET /games?filters=recorded,ps5,owned
```

- `filters` is a comma-separated list of canonical tokens.
- Order is irrelevant.
- Duplicates are de-duplicated server-side.
- Unknown tokens are silently dropped (component logs a warning in dev).

Canonical tokens (locked):

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
uses an underscore (`not_owned`). Conversion happens in the helper.

### Query object — `Games::Filter`

`Games::Filter.new(scope: Game.all, tokens: %w[ps5 owned]).results` returns an
`ActiveRecord::Relation`.

Composition rules:

1. Partition tokens into four buckets:
   - **Status**: `recorded`, `released`, `scheduled`
   - **Ownership**: `owned`, `not_owned`
   - **Platform**: `ps5`, `switch2`, `steam`, `gog`, `epic`
   - **Unknown**: anything else (dropped)
2. Apply each bucket as an intersecting AND across buckets.
3. Within the status bucket, multiple tokens OR together
   (`recorded OR released`).
4. Within the platform bucket, multiple tokens OR together (`ps5 OR switch2`).
5. Ownership bucket: `owned` AND `not_owned` together = contradiction → return
   `Game.none` (and the component renders a contradiction notice).
6. **Platform-precedence combinator (verbatim from source note §2):**
   - If `owned` is present → platform tokens restrict to games owned on those
     platforms (`Game.owned_on(slug)` chain).
   - If `not_owned` is present → platform tokens match games scheduled on those
     platforms but not yet owned anywhere.
   - If neither `owned` nor `not_owned` is present → platform tokens match
     EITHER games owned on those platforms OR games scheduled on those platforms
     when no ownership exists yet. This is the union form.

### Model scopes added to `Game`

```ruby
scope :recorded, -> { where(id: Video.select(:game_id).distinct) }
scope :released, -> { where("first_release_date <= ?", Time.current) }
scope :scheduled, -> { where("first_release_date > ?", Time.current) }
scope :scheduled_on, ->(slug) {
  scheduled.joins(:platforms_from_igdb).where(platforms: { slug: slug })
}
```

`Game.platforms_from_igdb` is the IGDB-reported release-platform association
(not the ownership join — that's `owned_platforms`). The exact source
association is determined by the existing IGDB integration; the spec calls out
that this is a distinct association from `owned_platforms`.

---

## Service / job decomposition

No new services or jobs in `01b`. The query object is a plain Ruby class under
`app/queries/`.

---

## Component decomposition

### `Games::FilterRowComponent`

Inputs:

- `active_tokens: Array<String>`
- `request_path: String` (so the chip links know where to send the user)

Renders:

- A horizontal row of `FilterChipComponent` instances, one per canonical token.
- A `[clear all]` bracketed link when `active_tokens.any?` — links to the same
  path with `?filters=` cleared.

### `Games::FilterChipComponent`

Inputs:

- `token: String`
- `active: Boolean`
- `request_path: String`
- `active_tokens: Array<String>`

Renders one bracketed link `[token]` (label uses spaces where canonical uses
underscores). The link's `href` is the current path with `token` toggled in/out
of `filters`. Active chips render with the `chip--active` style class (no red —
red is reserved for destructive actions only, per project rule).

---

## Spec pyramid

### Model — `spec/models/game_spec.rb` (additions)

Happy:

- `Game.recorded` returns games with at least one Video.
- `Game.released` returns games with past release date.
- `Game.scheduled` returns games with future release date.
- `Game.scheduled.scheduled_on('ps5')` restricts to PS5 scheduled releases.

Sad:

- `Game.released` excludes games with `nil` `first_release_date`.
- `Game.scheduled` excludes games with `nil` `first_release_date`.

Edge:

- a game with `first_release_date == Time.current` is `released` (boundary
  inclusive on past side).
- `Game.recorded` returns distinct games (no duplicates from multi-video).

Flaw:

- changing system time mid-query is consistent within a single query.

### Query — `spec/queries/games/filter_spec.rb` (load-bearing)

Build the §2 fixture matrix:

- Game A: released on PS5 + Switch 2; owned on PS5.
- Game B: released on PS5 + Steam; owned on neither.
- Game C: scheduled on Switch 2 only.
- Game D: scheduled on PS5 + Switch 2; owned on PS5.
- Game E: released on Steam; owned on Steam; one Video linked.
- Game F: released on GOG; not owned, no Video.
- Game G: released on Epic; owned on Epic.

Test cases (happy):

- `[]` → all games (A–G).
- `[recorded]` → E only.
- `[released]` → A, B, E, F, G.
- `[scheduled]` → C, D.
- `[owned]` → A, D, E, G.
- `[not_owned]` → B, C, F.
- `[ps5]` (no ownership filter, union semantics) → A, B, D (D scheduled on PS5;
  A + B released on PS5; A owned on PS5 → confirmed).
- `[switch2]` (union) → A (released + not owned on Switch 2 — falls under the
  "owned somewhere, restrict to owned" rule. A is owned on PS5; Switch 2 match
  requires ownership on Switch 2; A does NOT match), C, D.

  **Worked corollary from §2:** `[switch2]` alone matches: C (scheduled, not
  owned anywhere → scheduled-platform match), D (scheduled on Switch 2, owned on
  PS5 elsewhere → owned-somewhere rule applies; Switch 2 ownership required; D
  does NOT match). Final expected set for `[switch2]`: C only.

  Architect note: the §2 examples talk about "Game X owned on PS5" and unticking
  `owned`. For `[switch2]` alone with `owned` NOT in the token list, the source
  note (worked example, line 53) reads: "`owned` unchecked, `switch2` checked →
  matches (because the game is on that platform too)." This implies the union
  form when ownership is not constrained. Yet line 47 reads: "If I own the game
  on at least one platform, the platform filter matches only the platforms I own
  it on." The two statements conflict unless we read line 47 as conditional on
  `owned` being checked.

  **Locked interpretation (master agent):** line 47 applies only when `owned` is
  also active. When ownership is unconstrained, the union form holds.

  Under that interpretation, `[switch2]` alone → A, C, D (A released on Switch 2
  even though owned on PS5; C scheduled on Switch 2; D scheduled on Switch 2).

- `[owned, ps5]` → A, D (owned on PS5).
- `[owned, switch2]` → empty (no game owned on Switch 2).
- `[not_owned, ps5]` → empty (B and F are not owned but B is released on PS5
  with no ownership; per §2, `not_owned` + platform matches scheduled platforms
  only; B is released, not scheduled, so excluded).

  **Locked interpretation (master agent):** `[not_owned, ps5]` matches games
  that are NOT owned anywhere AND are scheduled on PS5 → empty in this fixture.

- `[recorded, owned]` → E.

Test cases (sad):

- `[owned, not_owned]` → contradiction → `Game.none` and a flag the component
  reads to render the contradiction notice.

Test cases (edge):

- unknown token `[gameboy]` is silently dropped; relation reflects an empty
  filter set.
- duplicate tokens `[ps5, ps5]` are de-duplicated; result identical to `[ps5]`.
- token order `[owned, ps5]` vs `[ps5, owned]` produces identical results.

Test cases (flaw):

- huge token list (100+ tokens) does not blow the stack; unknown tokens dropped.
- SQL injection via crafted token → token whitelist rejects it cleanly (the
  partition logic only accepts canonical strings).

### Component — `spec/components/games/filter_row_component_spec.rb`

Happy:

- renders 10 chips (one per canonical token).
- renders `[clear all]` when any chip is active.

Sad:

- does NOT render `[clear all]` when `active_tokens == []`.

Edge:

- `active_tokens` containing unknown token still renders the row; unknown token
  is not displayed.

Flaw:

- never emits `data-turbo-confirm` (no destructive action here).

### Component — `spec/components/games/filter_chip_component_spec.rb`

Happy:

- renders `[ps5]` link with `?filters=ps5` when inactive and request path is
  `/games?filters=` (or no `filters` param).
- renders `[ps5]` link toggling off when active.
- displays `not owned` (with space) for `not_owned` token.

Sad:

- raises if token is not in the canonical set.

Edge:

- preserves other URL params on the link (e.g., `?display=list`).

Flaw:

- HTML-escapes any raw token (defense-in-depth).

### Helper — `spec/helpers/games/filters_helper_spec.rb`

Happy:

- `parse_filter_tokens("ps5,owned")` → `["ps5", "owned"]`.
- `parse_filter_tokens("")` → `[]`.
- `parse_filter_tokens(nil)` → `[]`.
- `toggle_filter(["ps5"], "ps5")` → `[]`.
- `toggle_filter(["ps5"], "owned")` → `["ps5", "owned"]`.

Sad:

- `parse_filter_tokens("ps5, owned")` strips whitespace.
- `parse_filter_tokens("ps5,bogus")` drops unknown.

Edge:

- `parse_filter_tokens("ps5,ps5,owned")` de-duplicates.

### Request — `spec/requests/games_spec.rb`

Happy:

- `GET /games` → 200, no filter applied.
- `GET /games?filters=ps5` → 200, filter applied; HTML shows active chip.
- `GET /games?filters=ps5,owned` → 200, narrower set.

Sad:

- `GET /games?filters=` → 200, treated as empty filter set.
- `GET /games?filters=garbage` → 200, unknown token dropped.

Edge:

- `GET /games?filters=owned,not_owned` → 200, renders contradiction notice; body
  excludes game cards.

Flaw:

- query string with 100 tokens does not 500.

### System — `spec/system/games_index_spec.rb`

Happy:

- visiting `/games`, clicking `[ps5]` updates URL to `?filters=ps5`; clicking
  again clears it.
- `[clear all]` appears when one chip is active and clears the filter set.
- multiple chips compose; visible game count matches the query-object truth.

Sad:

- clicking `[owned]` then `[not owned]` shows the contradiction notice; page
  does not crash.

Edge:

- the filter row preserves the `?display=` param when a chip is toggled.

---

## yes / no boundary

No external booleans in the filter URL. All tokens are string tokens. Future MCP
/ CLI mirroring (`01g`) still observes the yes/no rule for any boolean argument.

---

## Friendly URL preservation

- `/games` route unchanged.
- `filters` query param is purely additive.
- No friendly slug routes affected.

---

## Manual test recipe

1. Open `/games` — observe ten chips, none active, no `[clear all]`.
2. Click `[ps5]` — URL `?filters=ps5`; chip rendered active; `[clear all]`
   appears.
3. Click `[owned]` — URL `?filters=ps5,owned`; game count narrows.
4. Click `[ps5]` again — URL `?filters=owned`; PS5 chip de-activates.
5. Click `[not owned]` — URL `?filters=owned,not_owned`; contradiction notice
   renders.
6. Click `[clear all]` — URL `?filters=` (or stripped entirely); all chips
   inactive.
7. Verify the game lists match the query-object truth for each of these
   transitions against `spec/queries/games/filter_spec.rb` expectations.

---

## Cross-stack scope

| Surface    | In scope                                          |
| ---------- | ------------------------------------------------- |
| Rails web  | YES — component, helper, query object, controller |
| Rails MCP  | NO — MCP filter parity ships in `01g`             |
| `pito` CLI | NO — CLI filter parity ships in `01g`             |
| Website    | NO                                                |

---

## Open questions

1. **Worked-example reconciliation (§2 lines 47 vs 53).** Locked interpretation:
   line 47 applies only when `owned` is checked; otherwise the union form holds.
   Confirm with the user before `01g` ships so MCP surface mirrors this exactly.
2. **`not_owned` + platform semantics.** Locked: matches games not owned
   anywhere AND scheduled on the platform. Source note doesn't enumerate the
   `not_owned + platform` case; this is the architect's reading.
3. **Contradiction (`owned + not_owned`)** — render a notice, or silently show
   empty? Locked: render notice (better UX).
4. **Default chip ordering.** Locked left-to-right:
   `recorded released owned not_owned scheduled ps5 switch2 steam gog epic`.
   Matches the source-note list order with platform chips trailing.
5. **`recorded` semantics on draft Videos.** Confirm: any linked Video, or only
   `published` Videos? Architect leans any Video; phase log can revisit if the
   user wants a stricter rule.
