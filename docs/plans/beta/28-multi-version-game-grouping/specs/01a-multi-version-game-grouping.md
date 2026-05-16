# 01a — Multi-Version Game Grouping (v1)

> Single v1 sub-spec for Phase 28. Introduces a self-referential parent /
> edition relationship on `Game`, wires IGDB import to populate it, makes the
> games index display only primaries (with an editions badge), and exposes the
> relationship across show / edit, MCP, and CLI.

---

## Goal

Today, "Pragmata", "Pragmata Deluxe Edition", and "Pragmata Standard Edition"
each land as independent `Game` rows when imported from IGDB — three tiles on
`/games`, three duplicate-looking entries the user has to ignore. This sub-spec
collapses that into one logical title with multiple editions:

- A primary row ("Pragmata") with `version_parent_id IS NULL`.
- Edition rows ("Pragmata Deluxe Edition", "Pragmata Standard Edition") whose
  `version_parent_id` points at the primary.
- A `version_title` free-text field on each edition ("Deluxe", "Standard", "Game
  of the Year", "Collector's").
- Listing surfaces (web, MCP, CLI) showing primaries only by default, with an
  `+N editions` badge on primaries that have editions.

Editions own their own genres, platforms, ownership, videos, footages, calendar
entries — the parent is a grouping anchor, nothing more.

This is a non-blocking standalone phase; Phase 27's per-platform ownership shape
feeds the rollup, but no other phase depends on Phase 28.

---

## Files touched

Migrations:

- `db/migrate/<ts>_add_version_parent_to_games.rb`

Models:

- `app/models/game.rb` (associations, scopes, validations, rollup methods)

Factories:

- `spec/factories/games.rb` (optional `:edition` trait)

Services:

- `app/services/igdb/import_game.rb` (or whichever existing entry point ingests
  IGDB game payloads — pre-resolve `version_parent` before save)

Controllers:

- `app/controllers/games_controller.rb` (index primaries-only; edit picker
  source; detach handling)

Views / components:

- `app/views/games/index.html.erb` (and any of `_grid_mode`, `_list_mode`,
  `_shelves_by_letter_mode`, `_by_letter` partials touched to filter to
  primaries)
- `app/views/games/_tile.html.erb` (editions badge)
- `app/views/games/show.html.erb` (editions sub-section)
- `app/views/games/edit.html.erb` (version_parent typeahead + version_title)
- `app/components/games/editions_badge_component.{rb,html.erb}` (new)
- `app/components/games/editions_section_component.{rb,html.erb}` (new)
- `app/components/games/version_parent_picker_component.{rb,html.erb}` (new)
- `app/javascript/controllers/version_parent_picker_controller.js` (Stimulus,
  typeahead)

MCP:

- `app/mcp/tools/games_list.rb` (add `include_editions: yes/no`; default
  primaries-only)
- `app/mcp/tools/game_show.rb` (return `version_parent_id`, `version_title`,
  `editions: [...]`)

CLI:

- `extras/cli/src/views/games.rs` (primaries-only + badge + drill-down)
- `extras/cli/src/client/games.rs` (consume the new MCP fields)

Tasks:

- `lib/tasks/games.rake` (`rake games:backfill_version_parents`)

Specs:

- `spec/models/game_spec.rb` (additions — associations, scopes, validations,
  rollup)
- `spec/services/igdb/import_game_spec.rb` (parent pre-resolve + idempotent
  re-import)
- `spec/requests/games_spec.rb` (index filter, edit detach, picker, MCP parity
  smoke)
- `spec/components/games/editions_badge_component_spec.rb`
- `spec/components/games/editions_section_component_spec.rb`
- `spec/components/games/version_parent_picker_component_spec.rb`
- `spec/system/games_multi_version_spec.rb` (one critical journey: attach /
  detach / re-attach)
- `spec/mcp/tools/games_list_spec.rb` (additions)
- `spec/mcp/tools/game_show_spec.rb` (additions)
- `spec/tasks/games_backfill_version_parents_spec.rb`
- Rust: `extras/cli/src/views/games_test.rs` (or the existing test module
  pattern) — primaries-only render + drill-down render.

---

## Model + migration shape

### Migration

```ruby
class AddVersionParentToGames < ActiveRecord::Migration[8.1]
  def change
    add_reference :games, :version_parent,
                  foreign_key: { to_table: :games, on_delete: :nullify },
                  null: true,
                  index: true
    add_column :games, :version_title, :string, null: true
  end
end
```

Notes:

- `null: true` on both columns — every existing row remains a primary by
  default.
- `on_delete: :nullify` — destroying a parent leaves its editions as orphan
  primaries.
- Index on `version_parent_id` for the `editions` association lookup and the
  `Game.primaries` / `Game.with_editions` scopes.

### `Game` (additions)

Associations:

```ruby
belongs_to :version_parent,
           class_name: "Game",
           optional: true

has_many :editions,
         class_name: "Game",
         foreign_key: :version_parent_id,
         dependent: :nullify
```

Scopes:

```ruby
scope :primaries, -> { where(version_parent_id: nil) }
scope :editions_of, ->(game) { where(version_parent_id: game.id) }
scope :with_editions, lambda {
  primaries.where(id: Game.where.not(version_parent_id: nil).select(:version_parent_id))
}
```

Validations:

```ruby
validate :version_parent_must_be_primary
validate :cannot_be_parent_and_edition_simultaneously
validate :no_self_reference
```

Bodies (illustrative — implementation may tighten):

- `version_parent_must_be_primary` — when `version_parent_id` is present, the
  referenced row must itself have `version_parent_id IS NULL`. Prevents
  two-level chains.
- `cannot_be_parent_and_edition_simultaneously` — when `editions.any?`,
  `version_parent_id` must be nil. Prevents flipping a parent into an edition
  while it still has children.
- `no_self_reference` — `version_parent_id` must not equal `id`.

Rollup methods:

```ruby
def owned_platforms_with_editions
  # primary: union of own ownerships + every edition's ownerships
  # edition: just its own ownerships
  return owned_platforms unless primary?
  Platform
    .joins(:game_platform_ownerships)
    .where(game_platform_ownerships: { game_id: [id, *editions.ids] })
    .distinct
end

def owned_editions(platform)
  editions.joins(:game_platform_ownerships)
          .where(game_platform_ownerships: { platform_id: platform.id })
          .distinct
end

def primary?
  version_parent_id.nil?
end

def edition?
  version_parent_id.present?
end
```

Naming note: keep `Game#owned_platforms` (existing — the
`through: :game_platform_ownerships` association) untouched to avoid silent
behavioural breakage for callers in Phase 27 surfaces. The rollup landing under
a distinct name (`owned_platforms_with_editions`) flows into the new listing /
show surfaces.

---

## IGDB import path

The existing IGDB game import service receives an IGDB payload that may carry a
`version_parent` field (an integer IGDB ID of the parent game).

Modified flow when `version_parent` is present:

1. Look up the parent locally by `igdb_id == payload[:version_parent]`.
2. If present, use it directly.
3. If absent, fetch the parent's IGDB payload, recursively import it (which
   itself MUST land as a primary — IGDB `version_parent` is one level deep by
   convention; if IGDB ever returns a chain, the importer stops at the first
   primary it finds and reports the issue via `Rails.logger.warn`).
4. Save the current row with `version_parent_id` set to the resolved parent.

Idempotency:

- The parent is upserted by `igdb_id` — re-running the importer with the same
  payload does not create a second "Pragmata" parent row.
- An edition that re-imports with the same `version_parent` keeps its existing
  relationship; only the IGDB-sourced columns flow through (per Phase 14 §1
  last-write-wins rules).
- An edition that re-imports with a CHANGED `version_parent` updates the pointer
  (rare; IGDB rarely re-parents).
- If `version_parent` is absent from the payload (the row IS a primary), the
  importer leaves `version_parent_id` untouched (manual overrides via the edit
  form survive IGDB re-sync).

The importer also stamps `version_title` from IGDB's `version_title` field if
present; the user may overwrite it via the edit form. Subsequent re-sync
respects a `version_title_manual_override` semantic — out of scope for v1 (see
open question 1). For v1, IGDB `version_title` always overwrites unless the
field is blank in the payload.

---

## Display rules

### Games index (`GET /games`)

All listing partitions filter to primaries:

- Grid mode: `Game.primaries`.
- List mode: `Game.primaries`, sticky-letter grouping unchanged.
- Shelves-by-letter mode:
  `Game.primaries.where("UPPER(LEFT(title, 1)) = ?", letter)`.
- Genres / Collections shelves at the top: filter their inner content to
  `Game.primaries` too (an edition does not stand alone in a shelf; it lives
  inside its parent).

URL escape hatch: `?include_editions=yes` (yes/no boundary) flips every
partition to a flat list. URL absent or `?include_editions=no` defaults to
primaries-only. The escape hatch persists across pagination but does not persist
across sessions; it is a debugging affordance, not a saved-view toggle.

### Tile (`_tile.html.erb`)

A primary with `editions.count > 0` renders a small bracketed badge after the
title, using the `Games::EditionsBadgeComponent`:

```
Pragmata  [+2 editions]
```

Singular form: `[+1 edition]`. Click target is the primary's show page anchored
to `#editions` (`<a href="/games/<slug>#editions">`).

Editions in a flat (`include_editions=yes`) listing render their tile with a
muted parent-pointer above the title:

```
↳ Pragmata
Pragmata Deluxe Edition
```

The parent pointer link is bracketed: `[↳ pragmata]`.

### Show page (`/games/:slug`)

For a primary:

- Existing header + body unchanged.
- New "Editions" section (rendered by `Games::EditionsSectionComponent`) appears
  as the last block before footer, anchored `#editions`. Lists each edition
  with: cover thumb (using the existing `:shelf` variant from Phase 27 §01e),
  title, `version_title`, and the per-edition owned-platforms chip strip.
- Section heading is muted: `Editions (2)`. No section rendered when
  `editions.empty?`.

For an edition:

- Existing header + body unchanged.
- Above the title, a muted parent pointer: `[↳ pragmata]` linking to the
  primary's show page.
- The per-edition ownership chip strip continues to render from the edition's
  own `owned_platforms`.

### Edit page (`/games/:slug/edit`)

Two new fields on the local-fields form, between `version_title` and
`played_at`:

1. `version_parent_id` — rendered by `Games::VersionParentPickerComponent`.
   Stimulus-driven typeahead. Source: `Game.primaries.where.not(id: <self>)`,
   matched by `LOWER(title) ILIKE '%query%'`, capped at 20. Value-as-id — the
   submitted form value is the game id. A `[detach]` bracketed link clears the
   field (sets `version_parent_id` to nil on submit). The picker is disabled
   when the current row HAS editions (a row with children cannot become an
   edition itself — enforced server-side too).
2. `version_title` — free-text input, max 100 chars, placeholder examples:
   "Deluxe", "Standard", "Game of the Year".

The typeahead respects `docs/agents/architect.md` rule A (bracketed labels, no
inner padding spaces). The Stimulus controller never uses `window.confirm` /
`alert` / `prompt`.

---

## Ownership aggregation

- Per-edition ownership tracked independently in `game_platform_ownerships`.
- `Game#owned_platforms` (existing): unchanged. Returns the row's own ownerships
  via `through: :game_platform_ownerships`. Callers in Phase 27 surfaces keep
  working.
- `Game#owned_platforms_with_editions` (new): for a primary, unions own
  ownerships with editions' ownerships. For an edition, equivalent to
  `owned_platforms`.
- `Game#owned_editions(platform)`: returns the editions you own on that
  platform. Empty for a primary with no editions; empty for an edition (an
  edition has no editions).
- Filter row interaction (Phase 27 §01b): `owned` / `owned_on(slug)` /
  `not_owned` scopes operate per-row as today. When the listing is in
  primaries-only mode, a primary appears in `owned` if EITHER the primary itself
  OR any edition has an ownership row. New scope:

  ```ruby
  scope :owned_rollup, lambda {
    where(id: Game.joins(:game_platform_ownerships).select(:id))
      .or(where(id: Game.where(version_parent_id: Game.joins(:game_platform_ownerships).select(:id))))
      .distinct
  }
  ```

  And the existing `Game.owned` is retired in favour of `Game.owned_rollup`
  inside the `Games::Filter` query object (Phase 27 §01b), with a deprecation
  note in `Games::Filter` pointing back to this spec. (Phase 27 callers that use
  `Game.owned` directly stay on the existing per-row scope; only the filter-row
  composition path swaps to the rollup.)

---

## MCP changes

### `games_list`

New optional argument `include_editions: yes/no` (yes/no boundary). Default
`"no"` → primaries only. `"yes"` → flat list. The existing pagination / filter
arguments compose normally.

Response shape (per row):

```json
{
  "id": 123,
  "title": "Pragmata",
  "igdb_slug": "pragmata",
  "version_parent_id": null,
  "version_title": null,
  "editions_count": 2,
  ...
}
```

Edition rows (when `include_editions: "yes"`):

```json
{
  "id": 124,
  "title": "Pragmata Deluxe Edition",
  "igdb_slug": "pragmata-deluxe-edition",
  "version_parent_id": 123,
  "version_title": "Deluxe",
  "editions_count": 0,
  ...
}
```

### `game_show`

Returns `version_parent_id`, `version_title`, plus a new `editions` array of
`{ id, title, igdb_slug, version_title }` objects (empty for editions). The
parent pointer is the existing `version_parent_id` integer (callers resolve via
a second `game_show` call if they need the parent's full row).

---

## CLI changes

`pito` TUI Games view:

- Default render: primaries only. Tiles render the editions badge inline
  (`Pragmata [+2 editions]`).
- Enter on a tile drills into the show view, which renders the editions
  sub-section.
- A keybind (proposed: `e`) toggles `include_editions: "yes"` for the current
  listing — flat mode. State is per-session (not persisted).
- Rust client: `extras/cli/src/client/games.rs` plumbs the new
  `include_editions` parameter and parses `version_parent_id`, `version_title`,
  `editions_count`.

CLI keybinding final decision is deferred to the cli-impl agent (the existing
TUI keybind map governs).

---

## Edit + detach path

`PATCH /games/:slug` accepts `game[version_parent_id]` (integer or empty string
→ nil) and `game[version_title]` (string). The controller assigns and saves;
validation errors render the edit form with field-level errors.

Detach flow: user clicks `[detach]` in the picker → the Stimulus controller
clears the hidden input value → form submission sets `version_parent_id` to nil
server-side. No JS confirm; no `/deletions/` redirect (detach is non-destructive
— the row stays, just becomes a primary). If the user wants to delete the row
outright, they use the existing `/deletions/games/:slug` flow (unchanged).

Server-side guards:

- A row with `editions.any?` rejects a non-nil `version_parent_id` with a
  validation error.
- The picker's typeahead endpoint returns primaries only — but the server
  re-validates on save so a hand-crafted form post can't sneak through.

---

## Backfill rake task

`lib/tasks/games.rake` adds:

```ruby
namespace :games do
  desc "Backfill version_parent_id by regex on existing titles."
  task backfill_version_parents: :environment do
    # See spec body for behaviour.
  end
end
```

Behaviour:

- Iterate every primary `Game` row (rows with `version_parent_id IS NULL`).
- For each row, compute a candidate "base title" by stripping the following
  suffixes (case-insensitive, anchored to end of title):
  - ` Deluxe Edition`, ` Deluxe`
  - ` Standard Edition`, ` Standard`
  - ` Game of the Year Edition`, ` Game of the Year`, ` GOTY Edition`, ` GOTY`
  - ` Collector's Edition`, ` Collectors Edition`, ` Collector Edition`
  - ` Definitive Edition`
  - ` Anniversary Edition`
  - ` Ultimate Edition`
- If a stripped variant matches another existing primary's title
  (case-insensitive, exact match), attach the row as an edition of that primary,
  stamping `version_title` with the captured suffix (normalised: "Deluxe",
  "Standard", "Game of the Year", "Collector's", "Definitive", "Anniversary",
  "Ultimate").
- If no match exists, leave the row alone — DO NOT auto-create a synthetic
  parent.
- Output a summary: `attached: N, skipped: M, total: T`.
- Idempotent: re-running visits the same set; rows already attached as editions
  are skipped (the iteration only walks primaries).

Edge cases the task does NOT handle:

- "Halo: The Master Chief Collection" containing multiple sub-games — outside
  scope. The task targets edition suffix patterns, not bundle-of-games
  semantics.
- Titles like "Game (Special Edition)" with parentheses — the regex can be
  extended in a follow-up; v1 sticks to the suffix list above.

---

## Spec pyramid

### Model — `spec/models/game_spec.rb` (additions)

Happy:

- `version_parent` association resolves correctly.
- `editions` returns the right collection ordered by `id` (or `title` if
  scoped).
- `Game.primaries` excludes editions.
- `Game.editions_of(game)` returns only that game's editions.
- `Game.with_editions` returns only primaries that have ≥1 edition.
- `primary?` / `edition?` return the expected boolean.
- `owned_platforms_with_editions` on a primary unions self + editions
  ownerships, deduped.
- `owned_platforms_with_editions` on an edition equals its own
  `owned_platforms`.
- `owned_editions(platform)` returns editions owned on that platform.

Sad:

- Setting `version_parent_id` to a row that is itself an edition rejects with a
  validation error ("version parent must be a primary").
- Setting `version_parent_id` to `self.id` rejects.
- A row that already has editions cannot accept a non-nil `version_parent_id`.

Edge:

- `dependent: :nullify` — destroying a parent leaves its editions in place with
  `version_parent_id = nil`.
- Detaching (setting `version_parent_id` to nil) on an edition succeeds and
  promotes the row to a primary.
- A primary with no editions returns `owned_platforms_with_editions` equal to
  its own `owned_platforms`.

Flaw:

- Cycle attempt — even though one level of nesting is enforced, an attacker
  payload setting `version_parent_id` to a row that is currently being
  re-parented in the same transaction rejects via the
  `version_parent_must_be_primary` validation.
- `Game.editions_of(nil)` returns an empty relation (does not error).

### Service — `spec/services/igdb/import_game_spec.rb` (additions)

Happy:

- IGDB payload with `version_parent` set resolves the existing parent and stamps
  `version_parent_id`.
- IGDB payload with `version_parent` set, parent not yet in DB, recursively
  imports the parent first (with its OWN `version_parent` nil) and then the
  edition.
- IGDB payload with `version_parent` absent imports as a primary
  (`version_parent_id` stays nil).
- IGDB `version_title` is stamped on the edition.

Sad:

- IGDB returns a `version_parent` ID that itself has a `version_parent` (a
  chain) — service logs a warning and stops at the first primary.
- IGDB client raises while resolving the parent — service re-raises after
  logging; the edition row is NOT saved (transactional).

Edge:

- Re-import of the same edition payload is idempotent (same row updated, no
  sibling created).
- Re-import where `version_parent` has CHANGED updates the pointer.
- Re-import where `version_parent` was previously set and is now absent in the
  payload leaves the existing pointer (does NOT clear it — manual / prior state
  wins).

Flaw:

- Concurrent imports of two siblings of the same not-yet-imported parent —
  service uses `find_or_create_by!` semantics to prevent two parents.

### Request — `spec/requests/games_spec.rb` (additions)

Happy:

- `GET /games` renders primaries only (editions absent).
- `GET /games?include_editions=yes` renders the full list.
- `GET /games?include_editions=no` is equivalent to no param.
- `GET /games/:slug` for a primary renders the editions section.
- `GET /games/:slug` for an edition renders the parent pointer link.
- `GET /games/:slug/edit` shows the picker + `version_title` field.
- `PATCH /games/:slug` with `version_parent_id` → row becomes an edition.
- `PATCH /games/:slug` with `version_parent_id: ""` → row becomes a primary
  (detach).

Sad:

- `?include_editions=true` (NOT yes/no) → treated as `"no"` per yes/no boundary
  rule (CLAUDE.md hard rule).
- `PATCH` with a `version_parent_id` pointing to an edition → validation error,
  edit form re-renders with the error.
- `PATCH` with `version_parent_id == self.id` → validation error.

Edge:

- Editions index URL hash anchor `#editions` lands on the right element.
- Pagination + `include_editions=yes` compose without losing the param across
  pages.

Flaw:

- A hand-crafted form POST setting `version_parent_id` to an already-parented
  row rejects server-side (the picker's typeahead can't be trusted alone).

### Components

`spec/components/games/editions_badge_component_spec.rb`:

- Renders nothing when `game.editions.empty?`.
- Renders `[+1 edition]` for one edition.
- Renders `[+2 editions]` for two.
- Link target is `game_path(game, anchor: 'editions')`.

`spec/components/games/editions_section_component_spec.rb`:

- Renders heading `Editions (N)`.
- Renders one row per edition with cover, title, version_title, ownership chip
  strip.
- Renders nothing when `game.editions.empty?`.

`spec/components/games/version_parent_picker_component_spec.rb`:

- Renders typeahead input + hidden id input.
- Pre-fills with current parent's title when `version_parent_id` is set.
- Renders `[detach]` link when a parent is set.
- Disabled state when the current row has editions.

### System — `spec/system/games_multi_version_spec.rb`

One critical journey:

1. Create primary "Pragmata".
2. Visit `/games/pragmata/edit` on an unrelated row "Pragmata Deluxe Edition";
   pick "Pragmata" in the typeahead; save.
3. Visit `/games` — only "Pragmata" tile renders, with `[+1 edition]` badge.
4. Click the badge → lands on `/games/pragmata#editions`; editions section
   visible.
5. Visit `/games/pragmata-deluxe-edition/edit` → click `[detach]` → save.
6. Visit `/games` — both rows render again.
7. Hard rule guards: no `data-turbo-confirm`, no `confirm`/`alert`/`prompt`
   anywhere in the rendered HTML or controller JS.

### MCP

`spec/mcp/tools/games_list_spec.rb` (additions):

- Default → primaries only.
- `include_editions: "yes"` → flat list.
- `include_editions: "no"` → primaries only (explicit).
- `include_editions: "true"` → rejected with yes/no boundary error.
- Response rows carry `editions_count`.

`spec/mcp/tools/game_show_spec.rb` (additions):

- Primary response carries `editions: [...]` populated.
- Edition response carries `version_parent_id` integer and `editions: []`.

### Task

`spec/tasks/games_backfill_version_parents_spec.rb`:

- "Halo 3" + "Halo 3 Game of the Year" → second attaches with
  `version_title: "Game of the Year"`.
- "Pragmata" + "Pragmata Deluxe Edition" → attaches with
  `version_title: "Deluxe"`.
- Re-running the task is idempotent.
- A row whose base title has no match is left untouched.
- Case-insensitive matching ("PRAGMATA DELUXE EDITION" still attaches).

### CLI (Rust)

`extras/cli/src/views/games_test.rs` (additions):

- Default render lists primaries only with the badge.
- Drill-down shows editions.
- Toggling `include_editions` re-renders the flat list.
- yes/no boundary preserved across the wire (request body carries `"yes"` /
  `"no"`).

---

## yes / no boundary

Every external boolean tied to this sub-spec:

- URL param `?include_editions=yes` or `?include_editions=no` only. Any other
  value coerces to `"no"`.
- MCP `games_list` `include_editions` argument: `"yes"` / `"no"` only.
- CLI wire format: serialises Rust `bool` to `"yes"` / `"no"` strings at the
  boundary.

Internal storage / Ruby code paths continue to use Ruby `true` / `false`.

---

## Friendly URL preservation

- `Game#to_param` continues to return `igdb_slug` (existing Phase 20 behaviour).
  Unchanged.
- Editions retain their existing slugs.
- Anchored show URLs (`/games/pragmata#editions`) honour the fragment via the
  browser; no server-side handling needed.

---

## Manual test recipe

1. `bin/rails db:migrate` — confirm migration adds `version_parent_id` and
   `version_title` to `games`.
2. `bin/rails console`:
   ```ruby
   parent = Game.create!(title: "Pragmata")
   deluxe = Game.create!(title: "Pragmata Deluxe Edition",
                         version_parent: parent,
                         version_title: "Deluxe")
   standard = Game.create!(title: "Pragmata Standard Edition",
                           version_parent: parent,
                           version_title: "Standard")
   parent.editions.count           # => 2
   parent.editions.pluck(:version_title) # => ["Deluxe", "Standard"]
   deluxe.primary?                 # => false
   parent.primary?                 # => true
   Game.primaries.pluck(:title)    # includes "Pragmata", excludes editions
   ```
3. Attempt to nest: `deluxe.update(version_parent: standard)` → returns `false`;
   `deluxe.errors[:version_parent_id]` contains "must be a primary".
4. Attempt self-reference: `parent.update(version_parent: parent)` → returns
   `false`; `parent.errors[:version_parent_id]` contains "cannot reference
   itself".
5. `bin/dev` → `http://localhost:3000/games`:
   - Only "Pragmata" renders, with `[+2 editions]` badge.
   - "Pragmata Deluxe Edition" / "Pragmata Standard Edition" absent.
6. Visit `http://localhost:3000/games?include_editions=yes` — flat list, all
   three rows visible; editions show `[↳ pragmata]` muted pointer.
7. Click the `[+2 editions]` badge → lands on `/games/pragmata#editions`;
   section lists both editions with cover thumbs.
8. Visit `/games/pragmata-deluxe-edition/edit`:
   - Picker is pre-filled with "Pragmata".
   - `version_title` field shows "Deluxe".
   - Click `[detach]` → submit → row becomes a primary; back at `/games`
     "Pragmata Deluxe Edition" renders as a separate tile.
9. Re-attach: `/games/pragmata-deluxe-edition/edit` → type "prag" into the
   picker → select "Pragmata" → submit. Confirm tile collapses back under
   "Pragmata".
10. `rake games:backfill_version_parents` against a seeded set with "Halo 3" +
    "Halo 3 Game of the Year Edition" — confirm GOTY row attaches; re-run task;
    confirm no duplicate attach.
11. MCP smoke (via `bin/mcp` stdio or the inspector):
    ```json
    { "name": "games_list", "arguments": { "include_editions": "no" } }
    ```
    → primaries only.
    ```json
    { "name": "games_list", "arguments": { "include_editions": "yes" } }
    ```
    → flat list.
12. `pito` TUI Games view: open, see primaries only with badge; drill into
    "Pragmata"; toggle flat mode (`e` keybind, pending cli-impl confirmation);
    confirm wire format uses `"yes"` / `"no"`.
13. Hard-rule sweep:
    `grep -RIn "data-turbo-confirm\|window.confirm\|window.alert\|window.prompt" app/`
    against the touched files → no matches.

---

## Cross-stack scope

| Surface    | In scope                                                 |
| ---------- | -------------------------------------------------------- |
| Rails web  | YES — index rollup + show editions + edit picker +       |
|            | detach + components + backfill task                      |
| Rails MCP  | YES — `games_list include_editions`, `game_show`         |
|            | editions + version_parent_id + version_title             |
| `pito` CLI | YES — Games view primaries-only + drill-down + flat-mode |
|            | toggle + wire-format parity                              |
| Website    | NO                                                       |

---

## Open questions

1. **`version_title_manual_override` semantics.** For v1, IGDB re-sync
   overwrites `version_title` when the payload's `version_title` is present.
   Should we add a `version_title_manual_override` flag (mirroring
   `manual_date_override`) so a user's hand-edited title survives re-sync?
   Architect leans yes, but defer to a v1.1 follow-up to keep this sub-spec
   tight.
2. **Parent `release_date` rollup.** When the parent has no `release_date` of
   its own (e.g., auto-created from IGDB), should it derive from the earliest
   edition's date? Architect leans yes, via an `after_save` hook on the edition
   that updates the parent if `release_date IS NULL` and
   `manual_date_override = false`. Surface for user lock — if no, the parent's
   calendar entry simply doesn't render until an edition is manually promoted.
   Locked decision option (a) in the umbrella `plan.md`.
3. **Typeahead source scope.** Picker shows primaries only (an edition cannot
   itself parent another). Confirmed; coded server-side.
4. **Bundle interaction.** A bundle may contain both the primary and an edition
   of the same logical title. Listing-side de-dupe at bundle render time, or
   display both? Architect leans display both (the user's explicit grouping
   wins).
5. **CLI keybind for flat-mode toggle.** Proposed `e`. The cli-impl agent owns
   the final letter; this spec just describes the behaviour.
6. **Backfill regex coverage.** v1 ships the suffix list above. Should we add
   parenthesised variants ("Game (Deluxe Edition)") in v1 or wait until we have
   data telling us how common they are in the user's library? Architect leans
   wait.
7. **`Game.owned` deprecation in Phase 27 §01b's `Games::Filter`.** The filter
   row's `owned` token swaps from `Game.owned` to `Game.owned_rollup` for the
   primaries-only listing path. Confirm with the user that this is the desired
   behaviour — a primary with an unowned base but an owned Deluxe edition
   appears in the `owned` filter. Architect leans yes (matches the "logical
   title" framing of this phase).
