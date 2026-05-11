# Games listing — compact layout with shelves, filter row, and grouping variants

Rework `/games` to be denser and more navigable.

---

## 1. Top of page — two shelves

Above the main listing, two horizontal shelves:

1. **Genres** shelf — one tile per genre.
2. **Custom collections** shelf — one tile per custom collection.

### Shelf rules

- Both shelves sorted **alphabetically**.
- Both use our existing **horizontal scroll** component (the skinned one — keep
  that styling).
- Tiles inside a shelf use a **shelf-variant cover art** (see "Cover art sizing"
  below).

---

## 2. Filter row

Between the two shelves and the main listing, a filter row. Filters available:

- `recorded`
- `released`
- `owned`
- `not owned`
- `scheduled`
- `ps5`
- `switch2`
- `steam`
- `gog`
- `epic`

**Multi-select** — a game can match multiple filters. Behavior:

### Platform-filter semantics (important)

Platform filters apply to **the platform I got the game on** — i.e. the platform
I personally own it on. A game being merely released on a platform isn't enough
on its own.

But there's a wrinkle for unreleased / not-yet-owned games:

- If a game is **scheduled / not yet released** on a platform and I don't own it
  yet, the platform filter still matches that platform (because future ownership
  intent counts here).
- If I own the game on at least one platform, the platform filter matches only
  the platforms I own it on.

Worked example:

- Game X is released on PS5 and Switch 2. I own it on PS5.
  - `owned` unchecked, `ps5` checked → matches.
  - `owned` unchecked, `switch2` checked → matches (because the game is on that
    platform too).
  - `owned` checked, `ps5` checked → matches.
  - `owned` checked, `switch2` checked → does **not** match (I don't own it on
    Switch 2).

So combining `owned` with a platform filter narrows the match to what I actually
have on that platform.

### Data model implication

We need **per-platform ownership** on Game. Today (assumption: single
`platform_owned_id` on Game) — that has to become a multi-record / multi-value
field. Probable shape: a join table `game_platform_ownerships` keyed by
`(game_id, platform_id)` with optional metadata (purchase date, store, etc.).

The Game screens (show + edit) need UI to manage per-platform ownership:

- A checklist of platforms the game is on (sourced from IGDB).
- Tick the ones I own it on. Optional per-platform details later.

MCP tool `game_update_local` will need extending too — `platform_owned_id`
becomes plural.

### Specs to cover

- Filter combinations: every pair of `owned` × platform with games in each
  ownership/release state.
- `scheduled` × platform: matches future-platform releases on unowned games.
- `recorded` / `released` orthogonal to the rest.
- Empty filter row = show everything.

---

## 3. Main listing — three display modes

Three ways to display the games below the filter row. The current grid stays as
**default**.

### Mode A — Grid (default)

- What we have today.
- No grouping.
- Standard cover art size (the current grid size — don't shrink this one).

### Mode B — List (alphabetic, grouped by letter)

- Long single table sorted alphabetically.
- Group heading per letter (A, B, C, …) acting as a section divider.
- Columns: TBD, but at minimum: cover thumbnail, title, platforms owned, genres,
  status. Open to a denser column set.

### Mode C — Shelves by letter

- One shelf per letter of the alphabet.
- Games inside each shelf laid out horizontally using our skinned horizontal
  scroll.
- Shelf cover art size (smaller — see below).
- Empty letters are either hidden or shown with a "(none)" placeholder — lean
  toward hidden.

### Mode switcher

Add a small control to flip between Grid / List / Shelves-by-letter. Selection
persists per user (probably via the saved-view system or a user preference).

---

## 4. Cover art sizing for shelves

The shelf variant (used in §1 shelves, and in Mode C) needs a **smaller cover
art** than the grid uses today. The user proposed **50%**.

**Challenge from me:** 50% may be too aggressive — at typical grid sizes a 50%
reduction can drop covers below readability for titles printed on the art
itself, and forces the horizontal-scroll skin to fight visually with the tile
content.

Suggested alternatives, pick before implementation:

- **~65–70%** of grid size — keeps title text legible on most covers, still much
  denser. **My recommendation.**
- **75%** — barely denser, probably not worth a new variant.
- **50%** — densest, fine if the user is comfortable with it for
  thumbnail-scanning use rather than reading.

Decision needed before we build the variant. Either way, **introduce a new
explicit cover-art variant** (e.g. `cover_variant: :shelf`) so we don't depend
on browser-resize / CSS scaling tricks — the user explicitly does not want
browser resize. The variant should be a real size class with its own asset
pipeline entry if applicable.

---

## Dispatch

Dispatch agents to work in parallel:

1. **Per-platform ownership data model** — migration, model, factory, MCP tool
   update. Blocking for filter semantics.
2. **Filter row component** — UI, state, query layer. Depends on §1.
3. **Genres shelf + Custom collections shelf** — alphabetical,
   horizontal-scroll-skinned, shelf-variant covers.
4. **Display mode switcher + Grid / List / Shelves-by-letter** — three modes,
   persisted preference.
5. **Shelf cover-art variant** — confirm size with user (recommend ~65–70%); add
   as explicit variant, not browser resize.
6. **Game show/edit screens** — per-platform ownership editor.
7. **Specs** — exhaustive, especially the filter-combination matrix from §2.
   Include system specs for switching display modes and persisting the choice.

Address any CI issues that surface. Aim for 100% autonomously.
