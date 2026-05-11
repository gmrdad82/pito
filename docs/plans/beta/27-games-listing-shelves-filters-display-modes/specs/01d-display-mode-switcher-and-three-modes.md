# 01d — Display Mode Switcher and Three Modes

> Parallel with `01b` and `01c`. Adds the display-mode switcher (top-right of
> `/games`, above the filter row) and the three modes: Grid (default), List
> (alpha-grouped, sortable), Shelves-by-letter (one shelf per letter, empty
> letters hidden). User preference persists via
> `User#preferred_games_display_mode`.

---

## Goal

Three first-class ways to view `/games`. Grid is what we have today. List is a
single table sorted alphabetically with sticky letter group headings.
Shelves-by-letter renders one horizontal shelf per letter (empty letters
hidden). The switcher persists the user's choice; the URL param `?display=`
overrides for a single request without persisting.

---

## Files touched

Migrations:

- `db/migrate/<ts>_add_preferred_games_display_mode_to_users.rb`

Models:

- `app/models/user.rb` (enum)

Controllers:

- `app/controllers/games_controller.rb` (reads param + falls back to user
  preference)
- `app/controllers/settings/games_display_modes_controller.rb` (PATCH endpoint
  that persists user preference)

Routes:

- `config/routes.rb` —
  `patch "/settings/games_display_mode/:mode",       to: "settings/games_display_modes#update",       as: :update_games_display_mode`

Components:

- `app/components/games/display_mode_switcher_component.{rb,html.erb}`
- `app/components/games/list_view_component.{rb,html.erb}`
- `app/components/games/shelves_by_letter_component.{rb,html.erb}`

Views:

- `app/views/games/index.html.erb` (chooses one partial / component based on
  resolved mode)
- `app/views/games/_grid.html.erb` (existing — minor extract)
- `app/views/games/_list.html.erb` (new — wraps `ListViewComponent`)
- `app/views/games/_shelves_by_letter.html.erb` (new — wraps
  `ShelvesByLetterComponent`)

Helpers:

- `app/helpers/games/display_mode_helper.rb` (resolves param → user pref →
  default)

Specs:

- `spec/models/user_spec.rb` (enum)
- `spec/components/games/display_mode_switcher_component_spec.rb`
- `spec/components/games/list_view_component_spec.rb`
- `spec/components/games/shelves_by_letter_component_spec.rb`
- `spec/helpers/games/display_mode_helper_spec.rb`
- `spec/requests/games_spec.rb` (display param + persisted preference)
- `spec/requests/settings/games_display_modes_spec.rb`
- `spec/system/games_display_modes_spec.rb`

---

## Model + migration shape

### `users.preferred_games_display_mode`

Migration:

```ruby
add_column :users, :preferred_games_display_mode, :integer, null: false, default: 0
```

Model:

```ruby
enum preferred_games_display_mode: {
  grid: 0,
  list: 1,
  shelves_by_letter: 2
}, _prefix: :games_display
```

So `user.games_display_grid?`, `user.games_display_list!`, etc.

### URL contract

- `GET /games` — uses `Current.user.preferred_games_display_mode`.
- `GET /games?display=list` — overrides for this request only.
- `PATCH /settings/games_display_mode/list` — persists the choice.

`display` query token values: `grid`, `list`, `shelves` (URL-friendly alias for
`shelves_by_letter`).

---

## Component decomposition

### `Games::DisplayModeSwitcherComponent`

Inputs:

- `active_mode: Symbol` (`:grid`, `:list`, `:shelves_by_letter`)
- `request_path: String`

Renders three bracketed-link buttons: `[grid]`, `[list]`, `[shelves]`. Active
button gets `active` class (no red). Clicking PATCHes
`/settings/games_display_mode/<mode>` via a button_to (form-driven, no JS) AND
redirects back to `/games` with `?display=<mode>` so the resolved mode shows
immediately on render.

### `Games::ListViewComponent`

Inputs:

- `games: ActiveRecord::Relation`
- `sort: Symbol` (`:title`, `:platforms`, `:genres`, `:status`)

Renders a `<table>` with sticky letter headings as `<tr class="letter-head">`
rows interleaved between game rows. Sorting:

- `?sort=title` (default) — alpha by title.
- `?sort=platforms_owned` — by count of `game_platform_ownerships`.
- `?sort=genres` — by first genre's name.
- `?sort=status` — by computed status enum (recorded > released > scheduled
  > unreleased).

Columns:

1. Cover thumbnail (`:shelf` variant — smaller).
2. Title (linked to `/games/:slug`).
3. Platforms owned (chip set, alphabetical).
4. Genres (comma-separated).
5. Status (single token: `recorded`, `released`, `scheduled`, `unreleased`).

### `Games::ShelvesByLetterComponent`

Inputs:

- `games: ActiveRecord::Relation`

Groups games by first letter of title (`.upcase`, non-alphabetic → `#`). Renders
one shelf per letter that has ≥1 game. Empty letters hidden. Each shelf uses the
skinned horizontal-scroll wrapper. Tiles use `:shelf` cover variant + bracketed
title label.

---

## Helper decomposition

### `Games::DisplayModeHelper#resolved_display_mode`

Resolution order:

1. `params[:display]` if present and valid → that mode (single-request).
2. `Current.user.preferred_games_display_mode` (always present once migration
   runs).
3. Fallback: `:grid` (only if `Current.user` is nil somehow).

`params[:display]` values mapped:

- `"grid"` → `:grid`
- `"list"` → `:list`
- `"shelves"` → `:shelves_by_letter`
- anything else → ignored (drops back to user preference).

---

## Spec pyramid

### Model — `spec/models/user_spec.rb` (additions)

Happy:

- default value is `grid`.
- enum maps to `0/1/2`.
- prefix `games_display_` works: `user.games_display_grid?`.

Sad:

- assigning an invalid value raises `ArgumentError`.

Edge:

- existing users get `grid` default on migration (data migration safe).

Flaw:

- enum int values are stable (0, 1, 2) — load-bearing for production data; spec
  asserts numeric mapping explicitly.

### Component — `spec/components/games/display_mode_switcher_component_spec.rb`

Happy:

- renders three bracketed-link buttons.
- active mode rendered with `active` class.
- each button is a `button_to` form (no JS, no anchor).
- forms PATCH to `/settings/games_display_mode/<mode>`.

Sad:

- never renders red (project rule).
- never uses JS confirm.

Edge:

- with `?display=list` in the request path, the switcher reflects `list` as
  active even if the persisted user pref is `grid`.

### Component — `spec/components/games/list_view_component_spec.rb`

Happy:

- renders a `<table>` with the five columns.
- inserts letter-heading rows between alphabetical groups.
- letter headings carry a `letter-head` class so CSS `position: sticky` applies.
- `?sort=title` sorts alpha.
- `?sort=platforms_owned` sorts by ownership count.

Sad:

- games with non-alphabetic title start (numbers, symbols) bucket into `#`.

Edge:

- a game whose title starts with a lowercase letter still buckets correctly
  (case-insensitive).
- empty relation renders an empty table body (no letter headings).

Flaw:

- never crashes when `genre`, `platforms`, or `status` is nil.

### Component — `spec/components/games/shelves_by_letter_component_spec.rb`

Happy:

- renders one shelf per non-empty letter.
- empty letters are NOT rendered (locked decision).
- each shelf carries the skinned-scroll wrapper.
- tiles use `:shelf` variant.

Sad:

- empty relation renders zero shelves (and an optional muted "(no games)"
  placeholder).

Edge:

- non-alphabetic titles bucket into `#`.

### Helper — `spec/helpers/games/display_mode_helper_spec.rb`

Happy:

- `?display=list` → `:list`.
- no param → user preference.
- no user (anonymous, if ever) → `:grid`.

Sad:

- `?display=foo` → falls back to user preference.

Edge:

- `?display=shelves` maps to `:shelves_by_letter`.

### Request — `spec/requests/games_spec.rb` (additions)

Happy:

- `GET /games?display=list` renders list view.
- `GET /games?display=shelves` renders shelves-by-letter.
- after PATCH `/settings/games_display_mode/list`, `GET /games` renders list
  view (preference persists).

Sad:

- `GET /games?display=garbage` falls back to user preference.

### Request — `spec/requests/settings/games_display_modes_spec.rb`

Happy:

- `PATCH /settings/games_display_mode/list` updates user pref to `list`; returns
  303 to `/games?display=list`.
- `PATCH /settings/games_display_mode/grid` updates to grid.

Sad:

- `PATCH /settings/games_display_mode/garbage` returns 422 (or 404 — pick one
  and document; architect leans 422 with a flash).

Edge:

- two rapid PATCHes settle on the last value.

Flaw:

- only authenticated users may PATCH; anonymous returns 401 / 302 to login.

### System — `spec/system/games_display_modes_spec.rb`

Happy:

- visiting `/games`, clicking `[list]`, page re-renders as list; reload — list
  still active.
- clicking `[shelves]`, page re-renders with letter shelves; empty letters
  hidden.
- clicking `[grid]`, back to grid.

Sad:

- never uses JS confirm.

Edge:

- composes with filter row: `?filters=ps5,owned` survives a mode toggle.

---

## yes / no boundary

No external booleans on this surface. PATCH path uses a path segment, not a
boolean form value.

---

## Friendly URL preservation

- `/games` unchanged.
- `/settings/games_display_mode/:mode` is a new route — `:mode` is a string
  enum, not a record slug.

---

## Manual test recipe

1. Open `/games` — observe `[grid] [list] [shelves]` switcher top-right of the
   filter row.
2. Click `[list]` — page re-renders as a table with alphabetical group headings;
   URL becomes `/games?display=list`.
3. Reload — list mode persists (URL still shows `?display=list` because of the
   PATCH redirect; the user pref is also set).
4. Open a fresh tab to `/games` — list mode is the default (persisted).
5. Click `[shelves]` — letter shelves render; empty letters absent.
6. Click `[grid]` — original grid restored.
7. Filter row composes: click `[ps5]`, switch to list view — both apply.
8. Confirm sticky letter headings stay pinned as you scroll the list (pure CSS
   `position: sticky`).

---

## Cross-stack scope

| Surface    | In scope                                                    |
| ---------- | ----------------------------------------------------------- |
| Rails web  | YES — switcher + three modes                                |
| Rails MCP  | NO — display mode is a UI concern, not exposed in MCP       |
| `pito` CLI | NO — CLI keeps its existing view; can mirror in a follow-up |
| Website    | NO                                                          |

---

## Open questions

1. **Sticky letter headings — pure CSS `position: sticky` or JS-driven?**
   Locked: pure CSS.
2. **`?sort=` default for list mode** — `title` ascending. Confirm.
3. **List mode pagination** — keep existing pagination (Pagy)? Architect leans
   yes; pagination resets to page 1 when sort changes.
4. **Shelves-by-letter row labels** — render `A` / `B` / `C` headings above each
   shelf, or inline as the first tile? Architect leans heading above the shelf
   (matches list mode's letter heading metaphor).
5. **Default mode for a brand-new user** — `grid` (locked).
6. **Touching saved-views** — should an explicit display-mode override land in
   the saved-view URL? Architect leans yes — saved views already capture query
   params; `?display=list` is just another param.
