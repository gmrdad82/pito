# 06 — Filters revamp: one compact row, URL canonicalization, no pagination

> Phase 27 v2 spec. Collapses the existing two filter rows + the
> `[clear all]` link into ONE compact filter block that sits between the
> page title and the first shelf. Left side = status / ownership chips,
> right side = platform chips. All chips default to CHECKED — the URL
> `/games` (no query string) means "show everything." Un-checking any
> chip narrows the listing AND mutates the URL to reflect the actual
> state. Re-checking all collapses back to `/games`. No page reload on
> chip toggle — Turbo morph or Stimulus + `history.replaceState`.

---

## Goal

The filter UI becomes a single dense control band that always
communicates "what am I currently looking at?" via the URL. Default
state is maximally inclusive (all chips checked = all games visible),
and the user narrows by un-ticking. The `played` chip implies (and
visually shows) the cascading `released` + `owned` + at-least-one-
platform constraints, because a game cannot have been played without
those conditions also holding.

`/games` is the canonical URL for the unfiltered listing. The page
NEVER paginates — letter shelves and shelf horizontal scrolling are the
only navigation primitives.

---

## Scope in

- Replace the existing 01b `Games::FilterRowComponent` two-row layout
  with a single compact row.
- Left side chips (status / ownership):
  - `[ ] released` — IGDB `release_date <= today`.
  - `[ ] scheduled` — IGDB `release_date > today`.
  - `[ ] owned` — at least one `game_platform_ownerships` row.
  - `[ ] wishlist` — NEW semantic. See definition below.
  - `[ ] played` — `played_at IS NOT NULL` (existing local-fields
    column). NEW filter chip; the underlying scope is trivial.
- Right side chips (platforms):
  - `[ ] PS5`, `[ ] Switch2`, `[ ] Steam`, `[ ] GoG`, `[ ] Epic`.
  - DROP `Xbox` (user-pinned).
  - Naming: confirm IGDB platform name for Nintendo Switch 2 is
    `"Switch 2"` (with a space). The display label on the chip is
    `Switch2` (no space) per the project's canonical
    `Platform::CANONICAL_SHORT_NAMES["switch2"] = "Switch2"`. The
    underlying slug stays `switch2`. Document.
- All chips default to CHECKED. `/games` (no `?filters=`) = all chips
  checked = show everything.
- URL canonicalization rule:
  - All chips checked → URL `/games` (no `?filters=` param).
  - User un-checks any chip → URL becomes
    `/games?filters=<the,remaining,checked,tokens>` (the chips that
    REMAIN CHECKED — NOT the chips that were un-ticked). Architect lean:
    invert from current 01b "tokens are the ACTIVE narrowing filters" to
    v2 "tokens are the CHECKED chips" semantics. This way `/games` = no
    param = all checked, and any param value = explicit set. See Open
    questions — alternative is "list the un-checked chips as
    `?off=...`".
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
- Filter implication / cascade: checking `[x] played` automatically
  also checks `[x] released` + `[x] owned` + at least one platform
  chip (since a played game must be owned, released, and on some
  platform). UI shows the implied checks visually so the user can SEE
  the cascade. Implementation = a Stimulus action that, on `played`
  check, also flips the dependent chips to checked.
- **No pagination on `/games`.** Render every matching game. Letter
  shelves bound the per-letter DOM size; horizontal shelf scrolling
  handles overflow within a row.

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
  - On click → flip the chip via Stimulus action; the controller
    mutates the URL and refreshes the Turbo Frame.
  - Carries `data-filter-token="<token>"` so the controller knows which
    chip flipped.
  - Carries `data-implied` (Array) for chips whose check implies others
    (only `played` does — the implied list is `["released", "owned"]`
    + at-least-one platform).

### Stimulus controller

- `app/javascript/controllers/games_filter_controller.js` (NEW)
  - Targets: every `Games::FilterChipComponent`'s root element.
  - Actions:
    - `toggle(event)` — flip the clicked chip's checked state,
      compute the new active set, mutate the URL via
      `history.replaceState`, fire a Turbo Frame refresh.
    - `applyImplications(event)` — when a chip with `data-implied`
      is checked, also force-check every implied chip.
  - URL writer: when the active set equals the universe, emit
    `/games`; otherwise emit `/games?filters=<csv>`. The CSV is
    sorted in a deterministic order (mirrors the chip render order
    so bookmarks are stable).

### Controller

- `app/controllers/games_controller.rb#index`
  - Rework filter parsing:
    - When `params[:filters]` is BLANK → treat as "all chips checked"
      → no narrowing applied (every game matches).
    - When present → split on `,`, intersect with the known token
      universe (drop unknowns), use as the CHECKED set. Anything
      NOT in the set is OFF and narrows the listing AWAY from it.
    - The narrowing semantics flip: today's 01b treats tokens as
      `released` = "show only released"; v2 treats tokens as
      `released checked` = "include released games in the listing"
      and the OFF set narrows the page to exclude. See Behavior.
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
      empty (interpreted as "all checked").
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

Ten tokens total. `/games` (no `?filters=`) ≡ all 10 checked.

### URL canonicalization

| User action                           | URL after                              |
| ------------------------------------- | -------------------------------------- |
| Land on `/games` (default)            | `/games`                               |
| Un-check `[x] gog`                    | `/games?filters=released,scheduled,owned,wishlist,played,ps5,switch2,steam,epic` |
| Re-check `[x] gog`                    | `/games`                               |
| Un-check everything in left side      | `/games?filters=ps5,switch2,steam,gog,epic` (just platforms checked) |
| Un-check EVERY chip                   | `/games?filters=` (empty CSV → see Open Q) |

The CSV serialization order follows `TOKEN_UNIVERSE` order so
bookmarks are stable across requests.

### Filter cascade — `played`

- When the user checks `[ ] played` → `[x] played`, the Stimulus
  controller also force-checks `[x] released` + `[x] owned` (because
  any played game is, by definition, released and owned). Also: if
  ZERO platform chips are checked, force-check ALL platform chips
  (since a played game must be on some platform). The visual flip
  happens synchronously before the URL writer runs, so the URL
  reflects the cascaded state.
- When the user UN-checks `[x] played` → `[ ] played`, the implied
  chips stay in whatever state they're in (no auto-uncheck — the
  cascade is one-way "check implies these, but uncheck does not
  release them"). Document.

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
  - Only `wishlist` checked → see Open questions for the wishlist
    semantic (architect lean: `Game.not_owned` — wishlist is the
    inverse of owned).
  - Mixed → union of the checked sub-scopes.
- Platform group (`ps5`, `switch2`, `steam`, `gog`, `epic`):
  - All checked → no narrowing.
  - Subset checked → UNION of `Game.owned_on(slug)` for each
    checked slug, with the existing 01b platform-precedence rule
    falling back to "released on" for unreleased / not-yet-owned
    games (per the source note §2).
- Cross-group: AND. `released, ps5` ≡ `released ∧ ownable_on(ps5)`.

### `played` semantic — model surface

- Add `scope :played, -> { where.not(played_at: nil) }` to
  `Game` (the column exists; only the scope is new).

### `wishlist` semantic — model surface (open question — default lean)

- Architect default: `wishlist ≡ not_owned`. A "wishlist game" is one
  the user has added to their library but does not own on any
  platform yet. Implement via the existing `Game.not_owned` scope —
  just expose under the new chip token.
- Alternative: a dedicated `games.wishlist` Boolean column. Out of
  scope for v2; if the user wants it, separate spec.

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

- `toggle(event)` — flip checked, recompute URL, apply implications,
  refresh frame.
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
  `data-implied` only for the `played` chip.

### Helper spec (`spec/helpers/games/filters_helper_spec.rb`)

- `parse_checked_tokens(nil)` → universe (every token checked).
- `parse_checked_tokens("")` → empty set (every token off).
- `parse_checked_tokens("ps5,steam")` → `[:ps5, :steam]`.
- Unknown tokens are dropped.
- `serialize_checked_tokens(universe)` → empty CSV (caller decides
  whether to emit `/games` vs `/games?filters=`).
- `serialize_checked_tokens([:ps5])` → `"ps5"`.
- `games_path_with_checked(universe)` → `"/games"`.
- `games_path_with_checked([:ps5])` → `"/games?filters=ps5"`.

### Query spec (`spec/queries/games/filter_spec.rb`)

- All 10 tokens checked → relation equals the input scope (no
  narrowing).
- Empty set → relation is `Game.none` (every group's "no chips
  checked" branch produces an empty result; AND across groups
  collapses to none).
- `[:released]` checked (only status released) → narrows to
  `Game.released`, no ownership/platform narrowing.
- `[:released, :owned, :ps5]` checked (one per group) → narrows to
  released AND owned AND owned-on-ps5 (with the 01b precedence
  fallback for scheduled-on-ps5 games).
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

- `GET /games` → all games visible (no narrowing).
- `GET /games?filters=ps5` → only games owned-or-ownable on PS5.
- `GET /games?filters=` (empty value) → no games (every group has 0
  chips checked; intersection is empty).
- Unknown tokens in `?filters=ps5,evil` → drop `evil`, narrow on
  `ps5`.
- Turbo Frame request (`Accept: text/vnd.turbo-stream.html` or the
  Turbo Frame `Turbo-Frame: games_listing` header) returns only the
  frame content, not the layout. Confirms the listing partition is
  inside the frame.

### System spec (`spec/system/games_filter_revamp_spec.rb`, NEW)

- Land on `/games` → all 10 chips render as `[x]`.
- Click `[x] gog` → URL updates to `/games?filters=...` with `gog`
  missing from the CSV. The listing re-renders WITHOUT a page reload
  (Capybara's `evaluate_script` or `current_path` assertion confirms
  no full navigation).
- Click `[ ] gog` again (re-check) → URL collapses to `/games`.
- Click `[ ] played` → checks `played` AND auto-checks `released` +
  `owned` if either was unchecked + auto-checks all platforms if
  none were checked.
- No `data-turbo-confirm`, no `window.confirm`, no `[clear all]`
  link present.

---

## Manual test recipe (filters)

1. `bin/dev` → open `http://localhost:3000/games`.
2. All 10 chips render with `[x]` (checked). URL: `/games` (no
   `?filters=`).
3. Click `[x] gog` → chip flips to `[ ]`. URL becomes
   `/games?filters=released,scheduled,owned,wishlist,played,ps5,switch2,steam,epic`.
   The listing area reflows; GoG-owned games disappear from the
   right-side filter scope. Page did NOT reload (scroll position
   preserved on the listing partition).
4. Click `[ ] gog` again → URL collapses to `/games`; all 10 chips
   checked.
5. Un-check `[x] released` → URL omits `released`. The listing
   narrows to scheduled-only games (since `released` is off and
   `scheduled` is still on; intersection is the scheduled set).
6. Click `[ ] played` → cascade: `played` checks, AND `released` +
   `owned` flip to checked if they were unchecked, AND all 5
   platform chips force-check if any were unchecked. URL reflects
   the cascaded state.
7. Type `/games?filters=` in the browser bar manually → page
   renders empty listing (every group has 0 checks; intersection
   is empty). Acceptable edge state.
8. Scroll down — no `[next page]` link, no pagination footer; the
   letter shelves and horizontal shelf scrollbars are the only
   navigation.

---

## Open questions

1. **Token semantic — CHECKED vs OFF.** The user prompt says "When
   user un-checks any, URL updates to reflect actual state
   (`?filters=released,owned,ps5,steam` style)." That example lists
   FOUR tokens, suggesting tokens are the CHECKED set (the four
   remaining checked). v2 default: tokens = CHECKED set. Confirm.
2. **`wishlist` semantic.** Architect default: equivalent to
   `not_owned` (a game in the library that the user does not own on
   any platform). Alternative: dedicated `wishlist` boolean column.
   Confirm.
3. **`/games?filters=` (empty value) — render empty listing OR treat
   as "all checked"?** Architect lean: render empty (the empty CSV
   is a legitimate "every group has zero checks" expression). The
   "no `?filters=` at all" case is the default-all-checked path.
   This means there is exactly one "all checked" URL: `/games`.
4. **Cascade direction.** Architect default: `played` ⇒ implies
   `released, owned, all-platforms` ON CHECK. Un-check `played` does
   NOT auto-uncheck the implied chips. Confirm.
5. **What is the listing partition exactly?** The genres outer
   shelf + collections outer shelf + letter shelves are all
   filterable, OR only the letter shelves? Architect lean: ALL of
   them — a user un-checking `gog` should see fewer games surface
   in the genre sub-shelves too. The whole partition lives inside
   the Turbo Frame.
6. **`Switch 2` (with space) vs `Switch2` (no space) in IGDB.**
   Confirm IGDB's canonical platform name. The `Platform` model's
   `CANONICAL_SHORT_NAMES` uses `"Switch2"` as the short display
   label; the IGDB-imported `Platform.name` may be `"Nintendo
   Switch 2"`. The slug is `switch2` regardless. Cosmetic only;
   does not affect the filter token.
7. **No pagination cost.** Confirm the user is okay with 5000+ DOM
   nodes if a library grows that large. If not, plan a follow-up
   for per-shelf `[see all]` links.
