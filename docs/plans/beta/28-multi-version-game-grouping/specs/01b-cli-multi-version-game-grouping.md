# 01b — CLI Multi-Version Game Grouping (v1)

> Sub-spec of Phase 28. Read `plan.md` first, then the Rails sibling spec at
> `01a-multi-version-game-grouping.md`. This spec covers the `pito` Rust CLI
> half of the same feature: TUI Games surfaces, API-client wire shape, and the
> CLI's MCP-tool wrappers.

---

## Goal

The Rails half of Phase 28 introduces a self-referential parent / edition
relationship on `Game` (`version_parent_id`, `version_title`), surfaces an
`+N editions` badge on primary tiles, exposes editions on the show page, adds a
typeahead picker + free-text `version_title` + `[detach]` to the edit page, and
extends MCP `games_list` / `game_show` with editions data.

The `pito` CLI must reach feature parity with that web + MCP surface for every
games-touching screen it already exposes:

- Games list view (primaries-only by default, badge on primaries with editions,
  toggleable flat mode that includes editions).
- Game show pane (editions sub-section under the per-platform ownership block;
  jump-to-parent from an edition show pane).
- Game edit pane (typeahead picker for `version_parent_id`, free-text
  `version_title`, two-step `[detach]` confirm overlay).
- API client wire shape for `games_list?include_editions=yes/no`, `game_show`
  response with `editions: [...]`, and `game_update` patches for
  `version_parent_id` + `version_title`.
- MCP-tool wrappers (`pito` CLI surfaces the same MCP tools the Rails server
  serves, for scripting parity).

Scope is strictly the CLI side. The Rails-side migration / models / controllers
/ components / IGDB importer / MCP tool implementations live in
`01a-multi-version-game-grouping.md`.

---

## Files touched

API client (Rust):

- `extras/cli/src/api/endpoints/games.rs` — request + response shape for the new
  fields. If this file does not yet exist as a separate module, the equivalent
  additions land in `extras/cli/src/client/games.rs` (whichever the cli-impl
  agent finds is current — flag in open question 4 below).
- `extras/cli/src/api/client.rs` (or `extras/cli/src/client/mod.rs`) — the trait
  gains `game_update` if it does not already have it.
- `extras/cli/src/api/mock.rs` (`MockClient`) — implement the new method +
  return canned fixtures for tests.

TUI screens:

- `extras/cli/src/ui/games.rs` — list view rendering, badge, flat-mode toggle.
- `extras/cli/src/ui/game_detail.rs` — editions sub-section + parent pointer.
- `extras/cli/src/ui/game_edit.rs` — typeahead picker overlay, version_title
  input, [detach] two-step confirm.
- `extras/cli/src/ui/typeahead.rs` (new) — reusable typeahead-input sub-widget.
  Shared with future surfaces (collections, bundles, etc.).

Key routing:

- `extras/cli/src/keys.rs` — bind `i` on Games screen for the "show editions"
  toggle; bind `p` on GameDetail screen (edition rows only) for the "jump to
  parent" navigation.
- `extras/cli/src/app.rs` — `GamesState` gains an `include_editions: bool` field
  (serialised at the wire boundary as `"yes"` / `"no"`); `GameDetail` state
  gains an `editions: Vec<EditionRow>` field.

MCP-tool surface (CLI wrappers):

- `extras/cli/src/mcp/games_list.rs` — CLI wrapper for the `games_list` MCP
  tool, including the `include_editions: yes/no` argument.
- `extras/cli/src/mcp/game_show.rs` — CLI wrapper that parses the `editions`
  array from the response.

Footage subcommand:

- `extras/cli/src/footage/` — verify no breakage. Footage import does NOT
  consume the games listing surface; this is a sanity sweep only. No functional
  changes expected.

Tests:

- `extras/cli/src/api/endpoints/games_test.rs` (or
  `extras/cli/src/client/games_test.rs`) — wiremock-backed unit tests on the
  wire shape.
- `extras/cli/src/ui/games_test.rs` — ratatui `TestBackend` snapshot tests on
  the primaries-only list + the flat-mode list.
- `extras/cli/src/ui/game_detail_test.rs` — editions sub-section render +
  parent-pointer render.
- `extras/cli/src/ui/game_edit_test.rs` — typeahead poll + selection + [detach]
  two-step confirm.
- `extras/cli/src/ui/typeahead_test.rs` — unit tests on the sub-widget.
- `extras/cli/src/keys.rs` (existing tests module) — additions for the new `i`
  and `p` bindings, including precedence rules.

---

## Acceptance

- [ ] `GamesState` gains `include_editions: bool` (default `false`). The wire
      serialisation converts it to `"yes"` / `"no"` at the request boundary; the
      in-memory representation stays Rust `bool`.
- [ ] `games_list` request issues `?include_editions=yes` when the toggle is on,
      `?include_editions=no` (or omits the param) when off. No `true` / `false`
      strings on the wire.
- [ ] The Games screen renders only primary rows when
      `include_editions == false`. Primaries with `editions_count > 0` render a
      bracketed badge `[+N editions]` (singular `[+1 edition]`) after the title.
- [ ] Pressing `i` on the Games screen flips `include_editions` and re-issues
      the list request. The flat-mode listing renders edition rows with a muted
      `[↳ <parent_title>]` pointer above the title.
- [ ] `i` does NOT collide with any existing Games-screen binding (see Open
      Questions §1 for the audit; current `keys.rs` Games-screen bindings are
      `q`, `j`/`k`, `Enter`, leader keys, `:` prefix, `g` prefix; `i` is
      unbound).
- [ ] `Enter` on a primary tile drills into its show pane. `Enter` on an edition
      tile (flat mode) drills into the edition's own show pane.
- [ ] Game show pane renders the editions sub-section under the per-platform
      ownership block when `editions: [...]` is non-empty. Each row is
      selectable (`j` / `k`) and `Enter` opens that edition's show pane.
- [ ] Edition show pane renders a muted parent-pointer line above the title:
      `[↳ <parent_title>]`. Pressing `p` on an edition show pane navigates to
      the parent's show pane.
- [ ] `p` is bound only on `Screen::GameDetail` for edition rows. On a primary
      show pane, `p` is a no-op (flash "no parent" optional — defer to
      cli-impl).
- [ ] Game edit pane exposes a `version_parent_id` typeahead, a free-text
      `version_title` input, and (when a parent is set) a bracketed `[detach]`
      link.
- [ ] The typeahead polls the Rails endpoint with the current query string
      (debounced 200 ms) and renders up to 20 matching primaries. Selection via
      `j` / `k` + `Enter`.
- [ ] `[detach]` triggers the in-TUI two-step confirmation overlay
      (`Overlay::Confirmation` — existing pattern). The overlay copy reads
      `Detach this edition from <parent_title>?`. Confirming clears
      `version_parent_id` server-side via `PATCH /games/:slug` with
      `version_parent_id: ""`.
- [ ] All wire booleans use `"yes"` / `"no"` strings — `include_editions` on the
      request, plus any new boolean fields the Rails side returns (none
      currently expected for editions, but the boundary is enforced uniformly).
- [ ] `game_show` response parser populates `version_parent_id: Option<i64>`,
      `version_title: Option<String>`, `editions: Vec<EditionRow>`. `EditionRow`
      carries `{ id, title, igdb_slug, version_title }`.
- [ ] `game_update` endpoint accepts `version_parent_id: Option<i64>` and
      `version_title: Option<String>`. Sending `None` for `version_parent_id`
      submits `version_parent_id=""` on the wire to trigger detach.
- [ ] MCP-tool wrappers `games_list` (with `include_editions` flag) and
      `game_show` (parsing the editions array) are added to the CLI's MCP tool
      surface.
- [ ] Test pyramid green: API-client wiremock tests, key-routing tests,
      typeahead-component tests, end-to-end ratatui `TestBackend` test covering
      the `i` toggle.
- [ ] Hard-rule sweep: no `window.confirm` / `alert` / `prompt` (N/A in Rust,
      but the equivalent is "no auto-fire destructive paths" — the `[detach]`
      flow goes through the two-step confirmation overlay).
- [ ] `pito footage` subcommand still builds + passes its existing test suite
      (sanity sweep — no functional changes expected).
- [ ] Footprint check: `cargo test -p pito` green;
      `cargo clippy     -- -D warnings` green.

---

## API client wire shape

### `games_list` request

```
GET /games.json?include_editions=yes&page=1&per_page=50
```

`include_editions` is `"yes"` or `"no"`. Default `"no"` (omit param or send
`"no"` — both behave identically server-side per 01a).

Response row (primaries):

```json
{
  "id": 123,
  "title": "Pragmata",
  "igdb_slug": "pragmata",
  "version_parent_id": null,
  "version_title": null,
  "editions_count": 2
}
```

Response row (editions, only when `include_editions=yes`):

```json
{
  "id": 124,
  "title": "Pragmata Deluxe Edition",
  "igdb_slug": "pragmata-deluxe-edition",
  "version_parent_id": 123,
  "version_title": "Deluxe",
  "editions_count": 0
}
```

Rust struct shape:

```rust
pub struct GameRow {
    pub id: i64,
    pub title: String,
    pub igdb_slug: String,
    pub version_parent_id: Option<i64>,
    pub version_title: Option<String>,
    pub editions_count: i64,
}
```

### `game_show` response

```json
{
  "id": 123,
  "title": "Pragmata",
  "igdb_slug": "pragmata",
  "version_parent_id": null,
  "version_title": null,
  "editions": [
    {
      "id": 124,
      "title": "Pragmata Deluxe Edition",
      "igdb_slug": "pragmata-deluxe-edition",
      "version_title": "Deluxe"
    },
    {
      "id": 125,
      "title": "Pragmata Standard Edition",
      "igdb_slug": "pragmata-standard-edition",
      "version_title": "Standard"
    }
  ]
}
```

For an edition response, `version_parent_id` is the parent's id, the
`version_title` is the edition's free-text label, and `editions` is the empty
array `[]`.

Rust struct additions:

```rust
pub struct GameShow {
    pub id: i64,
    pub title: String,
    pub igdb_slug: String,
    pub version_parent_id: Option<i64>,
    pub version_title: Option<String>,
    pub editions: Vec<EditionRow>,
    // ... existing fields (owned platforms, etc.)
}

pub struct EditionRow {
    pub id: i64,
    pub title: String,
    pub igdb_slug: String,
    pub version_title: Option<String>,
}
```

### `game_update` request

```
PATCH /games/:slug
Content-Type: application/x-www-form-urlencoded

game[version_parent_id]=123&game[version_title]=Deluxe
```

Detach:

```
PATCH /games/:slug
Content-Type: application/x-www-form-urlencoded

game[version_parent_id]=&game[version_title]=
```

Rust method signature:

```rust
async fn game_update(
    &self,
    slug: &str,
    version_parent_id: Option<i64>,
    version_title: Option<String>,
) -> Result<GameShow>;
```

`version_parent_id: None` serialises to `version_parent_id=""` on the wire
(triggers detach server-side).

### `version_parent_picker` typeahead source

```
GET /games.json?include_editions=no&q=prag&per_page=20
```

Returns up to 20 primary rows matching the query. The CLI uses the same
`games_list` endpoint with `q` and `per_page=20`; no new endpoint required. (Per
01a, the typeahead is server-driven; the Rails endpoint already filters to
`primaries.where.not(id: <self>)` when the request carries `?exclude_id`.)

CLI-side debounce: 200 ms after the last keystroke.

---

## TUI behaviour

### Games screen — primaries vs editions

Default (`include_editions == false`):

```
[ pragmata                          ] [+2 editions]
[ death stranding                   ] [+1 edition]
[ elden ring                        ]
```

Toggle on (`i` pressed, `include_editions == true`):

```
[ pragmata                          ] [+2 editions]
  ↳ pragmata
[ pragmata deluxe edition           ]
  ↳ pragmata
[ pragmata standard edition         ]
[ death stranding                   ] [+1 edition]
```

The parent-pointer is rendered in muted style
(`Style::default().add_modifier(Modifier::DIM)` or the theme's muted color). The
pointer text uses the bracketed convention: `[↳ pragmata]` is a click / Enter
target that navigates to the parent's show pane.

### Game show pane — editions sub-section

Below the existing per-platform ownership block, render:

```
Editions (2)
  [ pragmata deluxe edition          ]  Deluxe
  [ pragmata standard edition        ]  Standard
```

Each row is selectable via `j` / `k`. `Enter` drills into the edition's show
pane. Rendered only when `editions: [...]` is non-empty.

### Game show pane — parent pointer (edition rows)

Above the title, render:

```
[↳ pragmata]
Pragmata Deluxe Edition
Deluxe
```

Pressing `p` navigates to the parent's show pane.

### Game edit pane — picker + version_title + detach

Layout:

```
Title:           Pragmata Deluxe Edition
Version parent:  [ pragmata               ] [detach]
Version title:   [ Deluxe                 ]
Played at:       [ 2026-03-15             ]
Manual override: [yes] [no]

[ save ] [ cancel ]
```

Interacting with `Version parent`:

- Focus → enters typeahead mode. The input echoes keystrokes, debounced 200 ms;
  after the debounce, fire `games_list?q=<query>&include_editions=no`.
- A dropdown lists up to 20 matching primaries; `j` / `k` selects; `Enter`
  commits the id; `Esc` cancels and restores the prior value.
- The hidden `version_parent_id` value tracks the selected id.
- Pressing `Tab` from the typeahead commits the current selection (or clears if
  none) and moves to `Version title`.

Interacting with `[detach]`:

- Pressing `Enter` (or clicking, on terminals that support mouse) on the
  `[detach]` link opens the two-step confirmation overlay
  (`Overlay::Confirmation`). Copy: `Detach this edition from <parent_title>?`
  with `y` / `n` answers.
- Confirming clears the picker's hidden value (so a save POST submits
  `version_parent_id=""`) AND fires an immediate `game_update` with
  `version_parent_id: None`.
- The picker disables (greys out) when the current row has editions of its own
  (a parent cannot become an edition). The CLI receives that signal via
  `editions: [...]` on the `game_show` response — non-empty → disable the
  picker.

---

## Keybinding decisions (final)

Per the audit of `extras/cli/src/keys.rs` (current top-level char bindings: `q`,
`:`, `g`, `?`, `n`, `/`, `j`, `k`, ` ` (leader), `a`/`b`/`l` (pending),
`s`/`D`/`Y`/`f`/`x` on Channels, `x` on Videos, `v`/`s`/`c`/`D`/`Y`/`e` on
ChannelDetail, `h`/`l`/`H`/`L`/`g`/`G`/` ` on FootageDetail):

- `i` is unbound across every screen — clean candidate for the Games-screen
  "include editions" toggle. Recommended.
- `p` is unbound across every screen — clean candidate for the GameDetail "jump
  to parent" navigation (edition rows only).

Both bindings are scoped to the relevant screen (`Screen::Games` and
`Screen::GameDetail`); they do not bleed into other screens.

---

## Test pyramid

### API client (wiremock-backed)

- `games_list` with `include_editions=no` returns primaries only.
- `games_list` with `include_editions=yes` returns a flat list.
- `games_list` request URL serialises `include_editions` as `"yes"` / `"no"`
  (NOT `true` / `false` / `1` / `0`).
- `game_show` parses `editions: [...]` for primaries.
- `game_show` parses `version_parent_id: i64` for editions.
- `game_show` parses `editions: []` for editions (empty array).
- `game_update` PATCH body carries `game[version_parent_id]=<id>` when set.
- `game_update` PATCH body carries `game[version_parent_id]=` (empty string)
  when `None` is passed (detach).
- Server 422 response (validation error) bubbles up as
  `Error::Validation { field, message }`.

### Key routing

- Pressing `i` on `Screen::Games` flips `games_state.include_editions`.
- Pressing `i` on `Screen::GameDetail` is a no-op (or routes to the appropriate
  detail-screen binding — confirm with cli-impl; spec leans no-op).
- Pressing `p` on `Screen::GameDetail` for an edition row triggers
  `app.navigate_to_parent_game()`.
- Pressing `p` on `Screen::GameDetail` for a primary row is a no-op (flash
  optional).
- `i` and `p` are NOT consumed by the leader menu, the confirmation overlay, or
  the search overlay (overlay precedence wins per existing patterns).

### Typeahead component

- Typing into the input emits a debounced poll callback after 200 ms.
- Backspace clears one character + re-debounces.
- `Esc` cancels and restores the prior value.
- `Enter` commits the selected row's id.
- `Tab` commits the selected row's id and moves focus forward.
- `j` / `k` move selection within the dropdown.
- Empty query → no dropdown shown.
- Server error during poll → muted error line in the dropdown; commit is inert
  until the user clears the input or retries.

### End-to-end (ratatui `TestBackend`)

One critical journey:

1. Start the TUI; navigate to `Screen::Games`.
2. Backend returns three primaries: "Pragmata" (with 2 editions), "Death
   Stranding" (with 1 edition), "Elden Ring" (no editions).
3. Render: confirm the primary rows show with badges `[+2 editions]`,
   `[+1 edition]`, `(no badge)`.
4. Press `i`. Backend returns the flat list (3 primaries + 3 editions).
5. Render: confirm all 6 rows visible; editions show `[↳ <parent>]` muted
   pointer.
6. Press `i` again. Confirm the list reverts to primaries only.
7. Wire-format assertion: each `games_list` request carries
   `include_editions=yes` or `include_editions=no` (not `true` / `false`).

---

## Locked decisions

1. **Default: primaries only.** `include_editions` defaults to `false`
   (serialised as `"no"`) on every `games_list` request. The toggle is
   per-session (not persisted across launches; not stored in `SavedView` yet —
   that's a follow-up).
2. **Single-level nesting.** The CLI never presents the picker as an option on a
   row that already has editions (the picker is disabled when `editions: [...]`
   is non-empty on the `game_show` response).
3. **Detach is non-destructive.** The two-step confirmation overlay copy reads
   `Detach this edition from <parent_title>?` — no red, no destructive styling.
   The row stays in the database; it just becomes a primary.
4. **yes/no boundary at MCP/JSON.** Every wire boolean uses `"yes"` / `"no"`
   strings. Rust `bool` lives in memory; conversion happens at the serialisation
   seam.
5. **Bracketed-link convention.** All clickable elements use the bracketed
   `[ label ]` style — `[+N editions]`, `[↳ parent]`, `[detach]`. No inner
   padding spaces inside the brackets per `docs/agents/architect.md` rule A.
6. **Typeahead is server-driven, debounced.** 200 ms debounce after the last
   keystroke; server returns up to 20 primaries.

---

## Cross-stack scope

| Surface              | In scope this sub-spec                                 |
| -------------------- | ------------------------------------------------------ |
| Rails web (`/games`) | NO — covered by `01a`                                  |
| Rails MCP            | NO — covered by `01a`                                  |
| `pito` CLI (Rust)    | YES — Games list + show + edit + typeahead + MCP       |
|                      | wrappers + key routing + tests                         |
| `pito footage`       | SANITY ONLY — verify no breakage, no functional change |
| Cloudflare website   | NO                                                     |

---

## Manual test recipe

Pre-req: the Rails side of Phase 28 has landed and is running on
`http://localhost:3000` with seed data including "Pragmata" + two editions.

1. `cd extras/cli && cargo build`.
2. `pito` (default TUI mode) → navigate to Games (`g` then a games shortcut if
   present, else via the leader menu).
3. Confirm the Games screen shows "Pragmata" with `[+2 editions]` badge.
   Editions are NOT in the list.
4. Press `i`. Confirm the list expands to include both editions, each with a
   muted `[↳ pragmata]` pointer above the title.
5. Press `i` again. Confirm the list collapses back to primaries only.
6. Highlight "Pragmata"; press `Enter` to drill into its show pane.
7. Scroll past the per-platform ownership block; confirm the Editions
   sub-section lists both editions with their `version_title`.
8. Highlight "Pragmata Deluxe Edition" inside the Editions section; press
   `Enter`. Confirm you land on the Deluxe edition's show pane with a
   `[↳ pragmata]` pointer above the title.
9. Press `p`. Confirm you return to "Pragmata"'s show pane.
10. From "Pragmata Deluxe Edition"'s show pane, open the edit pane (via the
    existing edit-trigger keybind; cli-impl knows the current binding).
11. The picker should be pre-filled with "pragmata". Type into the version-title
    input: change "Deluxe" to "Deluxe Edition". Save.
12. Back on the show pane: confirm `version_title` now reads "Deluxe Edition".
13. Re-open the edit pane. Press `Enter` on `[detach]`. The two-step
    confirmation overlay opens with copy: `Detach this edition from pragmata?`
    and `y` / `n` keymap. Press `y`.
14. The pane redirects to the (now-detached) row's show pane. Confirm the parent
    pointer is gone.
15. From Games list, confirm "Pragmata Deluxe Edition" now renders as a separate
    primary tile (no badge unless it has its own editions, which it doesn't).
16. Re-attach: open the edit pane on "Pragmata Deluxe Edition". Focus the
    version-parent typeahead. Type "prag" → after ~200 ms, the dropdown shows
    "Pragmata" + "Pragmata Standard Edition" (NO — only primaries, so "Pragmata
    Standard Edition" is excluded). Confirm the dropdown contains only
    "Pragmata".
17. `Enter` to commit. Save. Back at Games list, confirm the row collapsed back
    under "Pragmata" with `[+2 editions]` badge restored.
18. MCP-tool wrapper smoke (via the CLI's MCP surface if exposed as subcommands,
    or via `bin/mcp` against the Rails server — confirm with cli-impl whether
    the CLI ships standalone MCP tools or just consumes the server's):
    ```
    pito mcp games_list include_editions=yes
    ```
    → flat list including editions.
    ```
    pito mcp game_show id=<pragmata_id>
    ```
    → response shows `editions: [...]` populated.
19. Wire-format assertion: run with `PITO_LOG=trace` (or whichever trace flag
    the CLI exposes); grep request URLs for `include_editions=`. Confirm every
    value is `yes` or `no`, never `true` / `false` / `0` / `1`.
20. `pito footage` sanity sweep:
    ```
    pito footage --help
    pito footage list
    ```
    Confirm the subcommand still runs cleanly (no functional change expected;
    this is a regression check).
21. `cargo test -p pito` → all green.
22. `cargo clippy -- -D warnings` → clean.

---

## Open questions

1. **Keybind for the include-editions toggle.** Architect leans `i` (unbound
   across all current screens per the `keys.rs` audit). Surface for user lock;
   cli-impl owns the final letter.
2. **Keybind for the jump-to-parent navigation.** Architect leans `p` (unbound
   across all current screens). Surface for user lock; cli-impl owns the final
   letter.
3. **Typeahead poll strategy.** Architect leans poll-as-you-type (200 ms
   debounced), server-driven. Alternative: fetch all primaries at edit-form open
   and filter client-side. Recommend poll-as-you-type for any library >100
   primaries (client-side filter doesn't scale). For libraries with >1000
   primaries the server-driven path is the only viable option; the typeahead
   caps at 20 results regardless.
4. **API client module layout.** Current CLI may have `src/client/games.rs`
   (older pattern) or `src/api/endpoints/games.rs` (newer pattern). cli-impl
   resolves which file to extend. Spec lists both candidate paths in §Files
   touched.
5. **MCP wrapper depth.** Does the CLI expose `games_list` and `game_show` as
   standalone subcommands (e.g., `pito mcp games_list ...`), or only consume the
   Rails server's MCP over stdio? Architect leans subcommands for scripting
   parity, but the spec accepts either as long as the wire shape (yes/no,
   editions array) is exercised. Surface for cli-impl.
6. **Edit pane edit-trigger keybind.** This sub-spec assumes the existing
   edit-trigger key (whatever it is — likely `e` on the show pane based on the
   ChannelDetail "URL is locked" flash binding) already exists on the GameDetail
   screen. If editing games is not yet wired up in the CLI, that's a
   prerequisite this spec doesn't cover and should be flagged.
7. **Two-step confirm copy for [detach].** Proposed:
   `Detach this edition from <parent_title>?` with `y` / `n`. The existing
   confirmation overlay pattern is delete + sync; detach is novel. Verify the
   overlay's API accepts a custom prompt string. If not, that's a small
   extension to `extras/cli/src/ui/confirmation.rs`.
8. **Per-session toggle vs SavedView persistence.** `include_editions` is
   per-session for v1. A future follow-up could persist it in `SavedView` for
   `kind: games` — out of scope here. Flag if the user wants it folded in.
