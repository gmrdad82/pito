# 06 — Filters revamp: one compact row, URL canonicalization, no pagination

> Phase 27 v2 spec. Collapses the existing two filter rows + the
> `[clear all]` link into ONE compact filter block that sits between the
> page title and the first shelf. Left side = status / ownership chips,
> right side = platform chips. All chips default to CHECKED — the URL
> `/games` (no query string) means "show the full list, every shelf,
> nothing narrowed." Un-checking any chip narrows the listing AND
> mutates the URL to reflect the actual state. Re-checking all collapses
> back to `/games`. No page reload on chip toggle — Turbo morph or
> Stimulus + `history.replaceState`.

---

## Goal

The filter UI becomes a single dense control band that always
communicates "what am I currently looking at?" via the URL. Default
state is maximally inclusive (all chips checked = full list visible),
and the user narrows by un-ticking. The `played` chip implies (and
visually shows) the cascading `released` + `owned` + at-least-one-
platform constraints, because a game cannot have been played without
those conditions also holding. The cascade is CHECK-ONLY — un-checking
`played` does NOT un-check the implied chips.

`/games` is the canonical URL for the unfiltered listing. The page
NEVER paginates — letter shelves and shelf horizontal scrolling are the
only navigation primitives.

Filters apply to EVERY shelf surface on `/games` — letter shelves,
genre shelves, and the collections shelf. A shelf whose post-filter
content is empty (no genre matches, no collection matches) is HIDDEN
from the page entirely; the user never sees an empty `RPG` sub-shelf
or an empty collection tile after un-checking `[x] ps5`.

---

## Scope in

- Replace the existing 01b `Games::FilterRowComponent` two-row layout
  with a single compact row.
- Left side chips (status / ownership):
  - `[ ] released` — IGDB `release_date <= today`.
  - `[ ] scheduled` — IGDB `release_date > today`.
  - `[ ] owned` — at least one `game_platform_ownerships` row.
  - `[ ] wishlist` — **NOT owned on ANY platform.** Orthogonal to
    release status: a scheduled-not-yet-released game the user does
    not own IS in wishlist; a released game the user does not own IS
    in wishlist. The chip is purely "no ownership row anywhere." See
    definition below.
  - `[ ] played` — `played_at IS NOT NULL` (existing local-fields
    column). NEW filter chip; the underlying scope is trivial.
- Right side chips (platforms):
  - `[ ] PS5`, `[ ] Switch2`, `[ ] Steam`, `[ ] GoG`, `[ ] Epic`.
  - DROP `Xbox` (user-pinned).
  - **`Switch2` label has NO space** in every UI surface. IGDB's
    canonical platform name is `"Nintendo Switch 2"` (with the space).
    The translation lives in a single constant
    `PLATFORM_LABELS = { "Nintendo Switch 2" => "Switch2", ... }`
    (introduced in `app/models/platform.rb` or a sibling helper). All
    display call sites (chip label, detail-page platform list, MCP
    output) route through `PLATFORM_LABELS[platform.name] ||
    platform.name`. The underlying slug stays `switch2`.
- All chips default to CHECKED. `/games` (no `?filters=`) = all chips
  checked = **show the full list, every shelf, nothing narrowed**.
- URL canonicalization rule:
  - All chips checked → URL `/games` (no `?filters=` param).
  - User un-checks any chip → URL becomes
    `/games?filters=<the,remaining,checked,tokens>` (the chips that
    REMAIN CHECKED — NOT the chips that were un-ticked). The empty
    query string `/games` is the SINGLE canonical "all checked"
    representation; any `?filters=` value is an explicit set.
  - User re-checks all → URL collapses back to `/games` (the controller
    or Stimulus controller drops the `?filters=` param when the active
    set equals the universe).
- No page reload on chip toggle: Stimulus controller intercepts the
  chip click, toggles the URL via `history.replaceState`, and either
  (a) uses Turbo's `<turbo-frame>` to re-fetch the listing area, or
  (b) re-renders via Turbo morph. Architect lean: (a) — wrap the
  listing partition (genres outer shelf, collections outer shelf,
  letter shelves) in one `<turbo-frame id="games_listing">` and
  re-fetch with the new URL on every chip toggle.
- **Filter implication / cascade (check-only, NOT symmetric):**
  checking `[ ] played` → `[x] played` automatically also force-checks
  `[x] released` + `[x] owned` + every platform chip if zero were
  checked. Visual flip is synchronous; URL writer fires AFTER the
  cascade so the URL reflects the cascaded state. **Un-checking `[x]
  played` → `[ ] played` does NOT un-check the implied chips** — the
  cascade is one-way. Documented in the Stimulus controller, baked
  into specs.
- **No pagination on `/games`.** Render every matching game. Letter
  shelves bound the per-letter DOM size; horizontal shelf scrolling
  handles overflow within a row.
- **Filters apply across all shelf surfaces** — genre shelves,
  collection shelf, letter shelves. Empty post-filter genre sub-
  shelves are hidden (genre with zero matching games does not render
  its `<section class="shelf">`). Empty post-filter collection tiles
  are hidden (a collection whose every member is filtered out does
  not render its composite tile). The genres outer shelf and
  collections outer shelf containers stay even if every sub-shelf
  inside is hidden (so the hairline structure does not collapse);
  the implementation may also hide the outer container when zero
  sub-shelves / tiles render — pick at implementation, document.

## Scope out

- The filter row's RIGHT slot for the display-mode switcher (deleted in
  spec 05).
- Chip styling beyond bracketed-link conventions (no new color palette).
- Saved-view persistence of the filter state. Today saved views encode
  the URL — that still works after the URL re-canonicalization (the
  URL is still the source of truth).
- IGDB sync of platform metadata (existing seed + sync job).
- MCP / CLI parity (separate follow-up).

---

## Files to change

### Component

- `app/components/games/filter_row_component.rb` (rewrite)
  - Drop the existing two-row + right-slot layout.
  - One-row layout: `<div class="filter-block">` with two flex children:
    `.filter-block__left` (status + ownership chips) and
    `.filter-block__right` (platform chips).
  - No `[clear all]` link any more — the canonical "clear" action is
    re-checking every chip (and the URL drops to `/games`).
  - Renders one `Games::FilterChipComponent` per chip in each side.
  - Accepts `checked_tokens:` (the SET of checked-chip tokens) and a
    `request_path:` (defaults to `games_path`).

- `app/components/games/filter_chip_component.rb` (rewrite)
  - Renders `[ ] label` or `[x] label` per `checked?` arg.
  - Platform chip labels use `PLATFORM_LABELS` mapping for display
    (e.g. `Switch2`, not `Nintendo Switch 2`).
  - On click → flip the chip via Stimulus action; the controller
    mutates the URL and refreshes the Turbo Frame.
  - Carries `data-filter-token="<token>"` so the controller knows which
    chip flipped.
  - Carries `data-implied` (Array) for chips whose check implies others
    (only `played` does — the implied list is `["released", "owned"]`
    + at-least-one platform).

### Constants

- `app/models/platform.rb` (or sibling)
  - Add `PLATFORM_LABELS = { "Nintendo Switch 2" => "Switch2",
    "PlayStation 5" => "PS5", "Steam" => "Steam", "GOG" => "GoG",
    "Epic Games Store" => "Epic" }.freeze` (verify exact IGDB strings
    at implementation; the map is on `Platform.display_label(name)`
    helper or similar).
  - Single source of truth for the IGDB → display translation. Used
    by chip labels (spec 06), detail-page platform list (spec 08),
    MCP output, and the platform-logo helper (spec 07) for the `alt`
    attribute.

### Stimulus controller

- `app/javascript/controllers/games_filter_controller.js` (NEW)
  - Targets: every `Games::FilterChipComponent`'s root element.
  - Actions:
    - `toggle(event)` — flip the clicked chip's checked state,
      compute the new active set, mutate the URL via
      `history.replaceState`, fire a Turbo Frame refresh.
    - `applyImplications(event)` — when a chip with `data-implied`
      is CHECKED, also force-check every implied chip. NOT fired on
      un-check (one-way cascade).
  - URL writer: when the active set equals the universe, emit
    `/games`; otherwise emit `/games?filters=<csv>`. The CSV is
    sorted in a deterministic order (mirrors the chip render order
    so bookmarks are stable).

### Controller

- `app/controllers/games_controller.rb#index`
  - Rework filter parsing:
    - When `params[:filters]` is BLANK (param ABSENT) → treat as
      "all chips checked" → no narrowing applied (every game
      matches, full list renders).
    - When present → split on `,`, intersect with the known token
      universe (drop unknowns), use as the CHECKED set. Anything
      NOT in the set is OFF and narrows the listing AWAY from it.
    - The narrowing semantics flip: today's 01b treats tokens as
      `released` = "show only released"; v2 treats tokens as
      `released checked` = "include released games in the listing"
      and the OFF set narrows the page to exclude. See Behavior.
  - Apply the active filter relation to:
    - `@letter_buckets` (existing).
    - `@genres_for_shelf` member queries — each genre's sub-shelf
      iterates `genre.games.merge(filtered_scope)`; genres with zero
      filtered games are dropped from `@genres_for_shelf` before
      render.
    - `@collections_for_shelf` member queries — each collection's
      composite tile inspects `collection.games.merge(filtered_scope)`;
      collections whose filtered member set is empty are dropped from
      `@collections_for_shelf` before render. Composite cover
      regeneration is unaffected (the composite is built off the raw
      member list, not the filtered one — filters are a render-time
      concern).
  - Wraps the listing partition in a `<turbo-frame id="games_listing">`
    (this is at the view level — note here so the controller branch
    stays minimal).
  - Drop the `contradiction?` predicate UI (now irrelevant — both
    `owned` and `not_owned` cannot both be CHECKED simultaneously
    because there is no `not_owned` chip in v2; absence of `owned`
    in the checked set means "include not-owned games" semantically).

- `app/queries/games/filter.rb` (rework)
  - Old contract: tokens were a list of narrowing scopes; absence of a
    token meant "no narrowing." That is incompatible with v2's
    "tokens are checked" semantics.
  - New contract:
    - INPUT: `checked_tokens` (Array<Symbol>). May be `nil` /
      empty (interpreted as "all checked" when nil; empty array is
      "every group off" — see Behavior).
    - PARTITIONS into 3 logical groups: status (`released`,
      `scheduled`), ownership (`owned`, `wishlist`, `played`),
      platform (`ps5`, `switch2`, `steam`, `gog`, `epic`).
    - For each group, if EVERY chip in the group is checked → no
      narrowing for that group. If a STRICT SUBSET is checked → the
      results are the UNION of the checked sub-scopes within that
      group (status = `released OR scheduled`; ownership = `owned OR
      wishlist OR played` etc.; platform = `owned_on(slug1) OR
      owned_on(slug2)`).
    - For the platform group, narrowing semantics follow the existing
      01b "owned-on" rule when the user has at least one ownership
      row on that platform; falls back to "released on" when the user
      does not yet own on that platform but it's scheduled / released
      there. Preserve the 01b platform-precedence combinator (§2 of
      the source note).
    - When chips from DIFFERENT groups are off, the groups AND
      together — e.g. `?filters=released,ps5` (other status + other
      platforms unchecked) returns games that are released AND
      ownable on PS5.

### Helper

- `app/helpers/games/filters_helper.rb` (rework)
  - Parser renames: `parse_checked_tokens(raw)`, `serialize_checked_tokens(tokens)`.
  - URL builder helper: `games_path_with_checked(tokens)` — emits
    `/games` when tokens equal the universe, `/games?filters=<csv>`
    otherwise.
  - `TOKEN_UNIVERSE` constant — every valid token in stable order.
  - Drop `parse_dropped_tokens` (no longer relevant — unknowns are
    silently dropped without a UI notice).

### View

- `app/views/games/index.html.erb`
  - Replace the existing filter-row block with the rewritten
    `Games::FilterRowComponent` (no right-slot now).
  - Wrap the listing partition (genres outer + collections outer +
    letter shelves) in `<%= turbo_frame_tag "games_listing" do %>
    ... <% end %>`.

### Tests / cleanup

- Drop the 01b `[clear all]` link tests (link gone).
- Drop the contradiction-notice tests in 01b request specs (no
  contradiction case exists in v2).
- Update the 01b system specs that assert `?filters=ps5` semantics to
  the new "checked = visible" semantics.

---

## Behavior contracts

### Token universe

```
TOKEN_UNIVERSE = %i[released scheduled owned wishlist played
                    ps5 switch2 steam gog epic]
```

Ten tokens total. `/games` (no `?filters=`) ≡ all 10 checked ≡ FULL
LIST.

### URL canonicalization

| User action                           | URL after                              |
| ------------------------------------- | -------------------------------------- |
| Land on `/games` (default)            | `/games` (full list, all 10 checked)   |
| Un-check `[x] gog`                    | `/games?filters=released,scheduled,owned,wishlist,played,ps5,switch2,steam,epic` |
| Re-check `[x] gog`                    | `/games`                               |
| Un-check everything in left side      | `/games?filters=ps5,switch2,steam,gog,epic` (just platforms checked) |
| Un-check EVERY chip                   | `/games?filters=` (empty CSV → see Open Q) |

The CSV serialization order follows `TOKEN_UNIVERSE` order so
bookmarks are stable across requests.

### Filter cascade — `played` (CHECK-ONLY, NOT symmetric)

- When the user checks `[ ] played` → `[x] played`, the Stimulus
  controller force-checks `[x] released` + `[x] owned` (because any
  played game is, by definition, released and owned). Also: if ZERO
  platform chips are checked, force-check ALL platform chips (since
  a played game must be on some platform). The visual flip happens
  synchronously before the URL writer runs, so the URL reflects the
  cascaded state.
- When the user UN-checks `[x] played` → `[ ] played`, **NO implied
  chips are touched.** The cascade is one-way: check implies these,
  uncheck does not release them. This is LOCKED, not configurable.
  The user can manually un-check `released` / `owned` / platforms
  after un-checking `played`; the system does not do it for them.

### Narrowing semantics (LOCKED)

Per-group rule: every group narrows the listing only when a STRICT
SUBSET of the group's chips is checked. All-checked = "no narrowing
from this group."

- Status group (`released`, `scheduled`):
  - All checked → no narrowing.
  - Only `released` checked → `Game.released`.
  - Only `scheduled` checked → `Game.scheduled`.
  - Neither checked → empty result (no status passes).
- Ownership group (`owned`, `wishlist`, `played`):
  - All checked → no narrowing.
  - Only `owned` checked → `Game.owned`.
  - Only `played` checked → `Game.where.not(played_at: nil)`.
  - Only `wishlist` checked → `Game.not_owned` (NOT owned on ANY
    platform — see semantic below).
  - Mixed → union of the checked sub-scopes.
- Platform group (`ps5`, `switch2`, `steam`, `gog`, `epic`):
  - All checked → no narrowing.
  - Subset checked → UNION of `Game.owned_on(slug)` for each
    checked slug, with the existing 01b platform-precedence rule
    falling back to "released on" for unreleased / not-yet-owned
    games (per the source note §2).
- Cross-group: AND. `released, ps5` ≡ `released ∧ ownable_on(ps5)`.

### Shelf-level filtering

- The active filter relation is applied to EVERY shelf source:
  - Letter shelves — `@letter_buckets` are computed from the
    filtered relation.
  - Genre sub-shelves — each `genre.games` is intersected with the
    filtered relation. Genres with zero matches are dropped from the
    outer genres shelf (their sub-shelf is not rendered).
  - Collection tiles — each `collection.games` is intersected with
    the filtered relation. Collections with zero filtered matches
    are dropped from the collections shelf (their tile is not
    rendered). Composite cover REGENERATION is independent (always
    uses the raw member set); the filter only hides tiles at render
    time.

### `played` semantic — model surface

- Add `scope :played, -> { where.not(played_at: nil) }` to
  `Game` (the column exists; only the scope is new).

### `wishlist` semantic — LOCKED

- `wishlist ≡ NOT owned on ANY platform`. Defined as a game with
  zero `game_platform_ownerships` rows. Orthogonal to release
  status — a scheduled (future) game the user has added to the
  library but does not own anywhere IS in wishlist; a released game
  the user does not own anywhere IS in wishlist. The chip simply
  asks "do I own this somewhere?" and "no" = wishlist.
- Implement via the existing `Game.not_owned` scope (or equivalent —
  rename if helpful: `scope :wishlist, -> { where.missing(:game_platform_ownerships) }`).
- **Drop any `released && !owned` formulation** from earlier drafts.
  The wishlist semantic is purely ownership-based.

### `PLATFORM_LABELS` translation

- Constant on `Platform` (or sibling helper module). Maps IGDB
  canonical platform names → user-facing short labels.
- `Platform.display_label(name)` → returns
  `PLATFORM_LABELS[name] || name`.
- Used by:
  - Filter chip labels (spec 06).
  - Detail-page platform list (spec 08).
  - Platform-logo `alt` attribute (spec 07).
  - MCP / CLI platform output (future parity sweep).
- Display = `Switch2` (no space); IGDB API name = `Nintendo Switch 2`.

### No pagination

- `GET /games` returns ALL matching games. The view renders every
  one across the letter shelves.
- Performance budget: the bottleneck is the `Game.includes(:primary_genre,
  :game_platform_ownerships)` query + the per-shelf cover-art rendering.
  Cover URLs are IGDB CDN — no per-tile DB lookup at render time.
- If a library exceeds 5000 games, the `:see all` per-shelf escape
  hatch can be reintroduced as a follow-up (out of scope here).

### Turbo Frame refresh

- The listing partition (genres outer + collections outer + letter
  shelves) is wrapped in `<turbo-frame id="games_listing">`.
- On chip toggle, the Stimulus controller mutates `window.location`
  via `history.replaceState(null, '', new_url)` and then triggers a
  manual Turbo Frame load with the new URL:
  `document.getElementById('games_listing').src = new_url`. Turbo
  fetches the new URL and replaces the frame.
- The filter row itself is OUTSIDE the frame — it does not re-render
  per toggle; the Stimulus controller manages its own chip-checked
  state directly.

---

## Migrations

None (the `played` scope adds no column; `wishlist` is derived from
ownership).

---

## ViewComponents

- `Games::FilterRowComponent` — rewritten.
- `Games::FilterChipComponent` — rewritten.

Old `Games::FilterRowComponent` slot `right_slot` is removed.

---

## Stimulus controllers

- `games_filter_controller.js` (NEW) — see Files to change.

Targets:

- `chip` (every chip's root span/button).

Actions:

- `toggle(event)` — flip checked, recompute URL, apply implications
  (check-only), refresh frame.
- (No separate `clearAll` action — re-checking every chip via the
  user is the "clear" action.)

Values:

- `request-path-value` — `/games`.
- `universe-value` — JSON of the 10-token universe so the controller
  can decide when the URL collapses to `/games`.

---

## Spec coverage required

### Component specs

- `spec/components/games/filter_row_component_spec.rb` — renders one
  row with left (5 status+ownership chips) + right (5 platform chips).
  Default props (`checked_tokens` empty / nil) renders all 10 chips
  checked.
- `spec/components/games/filter_chip_component_spec.rb` — renders `[ ]`
  vs `[x]` per `checked?`; carries `data-filter-token`; carries
  `data-implied` only for the `played` chip; platform-token chips
  render the `PLATFORM_LABELS` short label (`Switch2`, `PS5`).

### Helper spec (`spec/helpers/games/filters_helper_spec.rb`)

- `parse_checked_tokens(nil)` → universe (every token checked, "full
  list").
- `parse_checked_tokens("")` → empty set (every token off).
- `parse_checked_tokens("ps5,steam")` → `[:ps5, :steam]`.
- Unknown tokens are dropped.
- `serialize_checked_tokens(universe)` → empty CSV (caller decides
  whether to emit `/games` vs `/games?filters=`).
- `serialize_checked_tokens([:ps5])` → `"ps5"`.
- `games_path_with_checked(universe)` → `"/games"`.
- `games_path_with_checked([:ps5])` → `"/games?filters=ps5"`.

### Query spec (`spec/queries/games/filter_spec.rb`)

- All 10 tokens checked (or nil) → relation equals the input scope
  (no narrowing, full list).
- Empty set → relation is `Game.none` (every group's "no chips
  checked" branch produces an empty result; AND across groups
  collapses to none).
- `[:released]` checked (only status released) → narrows to
  `Game.released`, no ownership/platform narrowing.
- `[:released, :owned, :ps5]` checked (one per group) → narrows to
  released AND owned AND owned-on-ps5 (with the 01b precedence
  fallback for scheduled-on-ps5 games).
- `[:wishlist]` only → games with ZERO ownership rows (regardless of
  release status — a scheduled-not-owned game IS included).
- `[:played]` only → games with `played_at` set (regardless of
  status/platform group state — but those groups have 0 checks each,
  so they evaluate empty → final relation is `Game.none`). Confirm
  cascade semantic: the controller / Stimulus side cascades
  implication; the query side does NOT enforce cascade. If the
  cascade was bypassed (e.g. URL hand-edited), the query still
  returns the right intersection (which may be empty).
- Cascade interaction: with the cascade applied (Stimulus side),
  `played` ⇒ `released, owned, all-platforms` checked → relation is
  `Game.released.owned.played.where(platform any of 5)`.

### Request spec (`spec/requests/games_spec.rb`)

- `GET /games` → full list visible (no narrowing). Every genre shelf
  renders, every collection tile renders, every letter shelf renders.
- `GET /games?filters=ps5` → only games owned-or-ownable on PS5.
  Genre sub-shelves with zero PS5 games are HIDDEN. Collection tiles
  whose member set has zero PS5 games are HIDDEN.
- `GET /games?filters=` (empty value) → no games (every group has 0
  chips checked; intersection is empty). All shelves hidden.
- Unknown tokens in `?filters=ps5,evil` → drop `evil`, narrow on
  `ps5`.
- Turbo Frame request (`Accept: text/vnd.turbo-stream.html` or the
  Turbo Frame `Turbo-Frame: games_listing` header) returns only the
  frame content, not the layout. Confirms the listing partition is
  inside the frame.

### System spec (`spec/system/games_filter_revamp_spec.rb`, NEW)

- Land on `/games` → all 10 chips render as `[x]` → full list.
- Click `[x] gog` → URL updates to `/games?filters=...` with `gog`
  missing from the CSV. The listing re-renders WITHOUT a page reload
  (Capybara's `evaluate_script` or `current_path` assertion confirms
  no full navigation). Genres and collections with zero GoG games
  disappear from the page.
- Click `[ ] gog` again (re-check) → URL collapses to `/games`. All
  shelves re-appear.
- Click `[ ] played` → checks `played` AND auto-checks `released` +
  `owned` if either was unchecked + auto-checks all platforms if
  none were checked.
- Un-check `[x] played` → ONLY the `played` chip flips. The implied
  chips (released, owned, platforms) STAY in their current state.
- Platform chip labels read `PS5`, `Switch2` (no space), `Steam`,
  `GoG`, `Epic`.
- No `data-turbo-confirm`, no `window.confirm`, no `[clear all]`
  link present.

---

## Manual test recipe (filters)

1. `bin/dev` → open `http://localhost:3000/games`.
2. All 10 chips render with `[x]` (checked). URL: `/games` (no
   `?filters=`). Full list shows — every genre shelf, every
   collection tile, every letter shelf.
3. Platform chips read `PS5`, `Switch2` (no space), `Steam`, `GoG`,
   `Epic`. No `Xbox`.
4. Click `[x] gog` → chip flips to `[ ]`. URL becomes
   `/games?filters=released,scheduled,owned,wishlist,played,ps5,switch2,steam,epic`.
   The listing area reflows; GoG-owned games disappear; any genre
   sub-shelf or collection tile that becomes empty is HIDDEN. Page
   did NOT reload (scroll position preserved on the listing
   partition).
5. Click `[ ] gog` again → URL collapses to `/games`; all 10 chips
   checked; full list returns including the previously-hidden
   genres / collections.
6. Un-check `[x] released` → URL omits `released`. The listing
   narrows to scheduled-only games (since `released` is off and
   `scheduled` is still on; intersection is the scheduled set).
7. Click `[ ] played` → cascade: `played` checks, AND `released` +
   `owned` flip to checked if they were unchecked, AND all 5
   platform chips force-check if any were unchecked. URL reflects
   the cascaded state.
8. Un-check `[x] played` → ONLY `played` flips to `[ ]`. `released`,
   `owned`, and platforms stay as-is. URL reflects only the
   `played`-removed state.
9. Click `[x] owned` → unchecks. Wishlist games (zero ownership) now
   surface alongside owned games being filtered out per the AND
   semantic of the group split. Confirm scheduled-not-owned games
   appear when `[x] wishlist` is the only ownership chip checked.
10. Type `/games?filters=` in the browser bar manually → page
    renders empty listing (every group has 0 checks; intersection
    is empty). Acceptable edge state.
11. Scroll down — no `[next page]` link, no pagination footer; the
    letter shelves and horizontal shelf scrollbars are the only
    navigation.

---

## Open questions

1. **Outer shelf container behavior when every sub-shelf inside is
   filtered out.** Architect lean: keep the outer container's
   hairline structure so the page does not visually collapse; the
   inside renders nothing. Alternative: hide the outer container
   AND the leading hairline. Pick at implementation, document.
2. **`/games?filters=` (empty value) — render empty listing OR treat
   as "all checked"?** Architect lean: render empty (the empty CSV
   is a legitimate "every group has zero checks" expression). The
   "no `?filters=` at all" case is the default-full-list path.
   This means there is exactly one "full list" URL: `/games`.
3. **`PLATFORM_LABELS` exact IGDB strings.** Confirm at
   implementation by inspecting the `Platform.name` rows IGDB
   actually populates. The keys above (`"Nintendo Switch 2"`,
   `"PlayStation 5"`, `"GOG"`, `"Epic Games Store"`) are best
   guesses; the implementer cross-checks against
   `Platform::IGDB_ID_TO_CANONICAL_SLUG` and the seeded `Platform`
   rows.
4. **No pagination cost.** Confirm the user is okay with 5000+ DOM
   nodes if a library grows that large. If not, plan a follow-up
   for per-shelf `[see all]` links.
