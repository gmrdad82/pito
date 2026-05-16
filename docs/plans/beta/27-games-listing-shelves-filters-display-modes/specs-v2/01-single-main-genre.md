# 01 — Single main genre per Game

> Phase 27 v2 spec. Collapses the multi-genre game model to ONE main genre per
> game. Every UI surface that previously rendered a comma-joined "genres" list
> renders a single genre instead. Lower the cognitive cost of browsing the
> library by anchoring each game to exactly one canonical bucket.

---

## Goal

Each `Game` row has exactly ONE main genre — never zero (when IGDB reports any
genre), never two, never a comma-joined list. The existing
`Game#primary_genre_id` pointer (already in the schema) becomes the SINGLE
source of truth for genre rendering. The legacy multi-valued
`game_genres` join is preserved as IGDB raw metadata (no UI consumer) so the
"primary picker" service can re-evaluate the choice on each re-sync without
re-fetching from IGDB.

This is foundation work — every other spec in this v2 set (especially
`05-games-index-shelves-only.md`, `06-filters-revamp.md`,
`08-game-detail-revamp.md`) assumes "the game's genre" is a singleton.

---

## Scope in

- Audit the existing `primary_genre_id` column + `Games::PrimaryGenrePicker`
  service: confirm it is wired on save, decide what to do for legacy rows that
  never re-saved.
- Backfill: data migration walks every `Game` row whose `primary_genre_id` is
  NULL and assigns one via the picker. A row whose `game_genres` is empty
  stays NULL (the UI must handle the "no genre yet / IGDB returned none" case
  gracefully).
- Re-resolve `primary_genre_id` on every IGDB sync run (in `Igdb::SyncGame`)
  so a re-sync that adds / drops genres keeps the pointer current.
- Replace every UI/JSON/MCP rendering of the multi-genre list with the single
  main genre. Drop the comma-joined "genres:" label, drop the `genres.join`
  helper calls, rename labels from "genres" → "genre" everywhere.
- Adjust the existing 01c-v2 Genres outer shelf to consume the single
  `primary_genre_id` directly (controller already filters on it — confirm and
  keep).
- Picker tie-break policy: stable, deterministic. Recommended algorithm
  (preserve existing one if present, document either way): order
  `game_genres` by `genres.name` ASC case-insensitive, then by `genres.id`
  ASC. The picker's existing implementation lives at
  `app/services/games/primary_genre_picker.rb` (verify, document inline).

## Scope out

- Dropping the `game_genres` join table or removing the `genres` association
  (we keep it as the raw IGDB record for the picker's input).
- Editing the genre label / name themselves (separate concern handled in spec
  05 via a short-name lookup table for shelf headers — same
  `Genre#name` column underneath).
- Surfaces beyond the Rails web app (no MCP / CLI shape change yet — those
  catch up in a later parity pass; the Rails JSON endpoint follows the new
  shape).

---

## Files to change

### Investigation (audit before any change)

- `app/models/game.rb` — confirm the `before_save :assign_primary_genre_if_blank`
  hook + `belongs_to :primary_genre` association are wired (they are, per the
  current source — re-read the existing implementation, list any drift).
- `app/services/games/primary_genre_picker.rb` — read the existing picker
  body. Confirm it returns nil when no genres are present and the chosen
  `Genre` instance otherwise. Document the existing tie-break in this spec's
  Behavior section.
- `db/schema.rb` — confirm `games.primary_genre_id` exists with the
  on-delete-nullify FK. If it does, no migration needed. If not (older
  branch), include the migration below.

### Backfill migration

- `db/migrate/<TS>_backfill_games_primary_genre.rb` — data-only migration.
  Iterates `Game.where(primary_genre_id: nil)` in batches; calls
  `Games::PrimaryGenrePicker.new.pick(game)` and writes the result via
  `update_columns(primary_genre_id: …)` so callbacks do not fire. Idempotent
  — re-running is a no-op once every row is populated. Logs the count
  affected so the operator sees the sweep size.

### IGDB sync wire-up

- `app/services/igdb/sync_game.rb` — after `sync_genres` writes the join
  rows, explicitly re-run `Games::PrimaryGenrePicker.new.pick(game)` and
  `game.update_column(:primary_genre_id, …)`. Document why: the
  `before_save :assign_primary_genre_if_blank` hook on `Game` only sets the
  pointer when it is blank; an existing pointer to a genre that IGDB just
  dropped (or to a genre still present that is no longer the alphabetical
  winner) needs an explicit re-pick on every sync.

### UI surfaces — rename "genres" → "genre" + single value

- `app/views/games/show.html.erb` (Phase 14 §1 polish surface — line ~138
  reads `<span class="text-muted">genres:</span> <%= @game.genres.map(&:name).join(", ").presence || "—" %>`).
  Rewrite to render `@game.primary_genre&.name || "—"` and relabel
  `genres:` → `genre:`. Detail-page revamp in spec 08 supersedes this
  layout entirely; this is the interim guard for the spec-01 single-genre
  rendering rule. When spec 08 ships, the show-page surface for genre
  moves to the spec-08 layout but the data-source rule (single
  `primary_genre`) carries over.
- `app/views/games/_tile.html.erb` — does not currently render genres in
  the caption; verify and document. If a future caption variant wants
  genre, it MUST consume `primary_genre`.
- `app/views/games/_list_mode.html.erb` — list-mode currently has a
  "genres" column. Rename column header to `genre`; render
  `game.primary_genre&.name || "—"` (no comma-join). Adjust the column
  width if needed.
- `app/views/games/_genres_shelf.html.erb` /
  `app/views/games/_genre_sub_shelf.html.erb` — the 01c-v2 nested shelf
  already iterates `primary_genre`-scoped rows. Confirm the
  per-sub-shelf membership query in
  `app/services/games/genre_shelf_batch.rb` reads from
  `primary_genre_id`, not from the `game_genres` join. Document any drift.
- `app/views/games/index.html.erb` — adjust the heading copy if any
  visible label says "genres" in the wrong place.
- `app/views/games/edit.html.erb` — if the edit form exposes a
  primary-genre picker, document its inputs. (The detail-page revamp in
  spec 08 removes `/games/:id/edit` entirely; the edit form here is
  doomed but until spec 08 ships, it must respect the same rule.)

### Helper / JSON surfaces

- `app/helpers/games/*.rb` — search for any `genres.map(&:name).join` or
  `display_genres` helper. If one exists, rename to `display_genre` and
  return the single primary's name (or `"—"` when blank).
- `app/views/games/index.json.jbuilder` / `show.json.jbuilder` — if the
  JSON envelope today emits `genres: [ ... ]`, replace with `genre: "name"`
  (singular). Document the JSON wire change in this spec — downstream
  consumers (MCP / CLI) must adapt, tracked as a follow-up if not in scope
  for v2 now.

---

## Behavior contracts

### `Game#primary_genre` (existing)

- `belongs_to :primary_genre, class_name: "Genre", optional: true`.
- FK: `games.primary_genre_id REFERENCES genres(id) ON DELETE SET NULL`.
- `optional: true` means a freshly added game whose IGDB metadata has not
  arrived yet has `primary_genre_id = NULL`. That state is rendered as `"—"`
  everywhere.

### `Games::PrimaryGenrePicker`

- Public API: `Games::PrimaryGenrePicker.new.pick(game) -> Genre | nil`.
- Inputs: a persisted `Game` whose `genres` association is loaded or
  reloadable. The picker MUST NOT hit IGDB.
- Tie-break (LOCKED): alphabetical `LOWER(genres.name)` ASC, then `genres.id`
  ASC. Deterministic across requests.
- Empty input: returns `nil` (no genres on the game).
- Idempotent: calling `pick` on a game with a primary already assigned still
  returns the same genre.

### Sync re-evaluation hook

- `Igdb::SyncGame#call` MUST re-run the picker AFTER the `sync_genres` step
  writes / removes join rows. The explicit `update_column` write skips
  callbacks so the re-pick does not loop. Document the order:
  `sync_basic_fields` → `sync_genres` → `re_assign_primary_genre` →
  `sync_platforms` → `sync_companies` → … (insert at the natural seam after
  genres land).

### UI rendering rule

- Every place that renders genre information for a single game renders
  EXACTLY ONE genre — the `primary_genre.name`, or the literal `"—"`
  placeholder when nil. No `.map`, no `.join`, no plural label.
- Label copy: `genre` (singular). Plural `genres` is permitted only on the
  Genres outer-shelf heading (where it refers to the set of buckets, not to
  one game's set of genres).

### Backfill migration

- Wrapped in `disable_ddl_transaction!` since the data write spans many
  rows. Use `in_batches(of: 500)`.
- Sets `primary_genre_id` via `update_columns` (bypasses callbacks AND
  validations, which is correct for a backfill).
- Skips rows where the picker returns nil. Logs the per-batch count and a
  final total summary.

---

## Migrations

If `games.primary_genre_id` already exists in `db/schema.rb` (it does in the
current repo, per the existing `Game#belongs_to :primary_genre, optional: true`
declaration), the migration is data-only. Otherwise (older branch):

```ruby
class AddPrimaryGenreToGames < ActiveRecord::Migration[8.1]
  def change
    add_reference :games, :primary_genre,
                  foreign_key: { to_table: :genres, on_delete: :nullify },
                  null: true,
                  index: true
  end
end
```

Data-only backfill migration:

```ruby
class BackfillGamesPrimaryGenre < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    picker = Games::PrimaryGenrePicker.new
    total  = 0
    Game.where(primary_genre_id: nil).find_each(batch_size: 500) do |game|
      genre = picker.pick(game)
      next if genre.nil?
      game.update_columns(primary_genre_id: genre.id)
      total += 1
    end
    say_with_time("backfilled primary_genre on #{total} games") {}
  end

  def down
    # Reversible: clear the pointer. The `before_save` hook re-derives on
    # next save, and the IGDB sync re-assigns on next sync.
    Game.where.not(primary_genre_id: nil).in_batches.update_all(primary_genre_id: nil)
  end
end
```

---

## Spec coverage required

Exhaustive — model, service, request, view, system. Happy + sad + edge + flaw.

### Model spec (`spec/models/game_spec.rb`)

- Existing `belongs_to :primary_genre, optional: true` association test stays.
- New: `assign_primary_genre_if_blank` callback fires on save when blank.
- New: callback is a no-op when `primary_genre_id` is already set.
- New: `primary_genre` is set to the alphabetical-first genre when a game
  has two genres.
- Edge: a game with no genres saves with `primary_genre_id` still nil and
  does not raise.
- Edge: when the picker returns nil, the assignment writes nil (not the
  current value).
- Flaw guard: deleting the `Genre` row pointed at by `primary_genre_id`
  nullifies the FK without destroying the game (FK on_delete: nullify).

### Service spec (`spec/services/games/primary_genre_picker_spec.rb`)

- Happy: single-genre game → returns that genre.
- Happy: multi-genre game → returns alphabetical-first genre by
  `LOWER(name)`, tie-broken by `id`.
- Sad: zero-genre game → returns nil.
- Edge: case-mixed names (`"Action"`, `"action"`, `"ACTION"`) — picker
  treats them as equal and falls back to `id` order.
- Edge: passing an unpersisted game → returns nil (no associations).
- Flaw: passing nil → raises ArgumentError (or returns nil, whichever the
  existing implementation chose — pin the behavior).

### Sync integration spec (`spec/services/igdb/sync_game_spec.rb`)

- After a sync run that swaps the genres set (e.g. game had `[Action]`,
  IGDB now reports `[Adventure, Puzzle]`), `primary_genre_id` is
  re-assigned to `Adventure` (alphabetical first), not left pointing at
  `Action` or stuck at the original `Action`'s id.
- When the post-sync genres set is empty, `primary_genre_id` is set to
  nil.
- The re-pick step does NOT re-fire on a sync run where genres are
  unchanged (the genres set hash is identical) — performance guard.
  Acceptable alternative: re-pick always runs but is idempotent and cheap.

### Migration spec (`spec/migrations/...`)

- Optional but recommended given the bulk write. If skipped, the system
  spec below covers the user-visible effect.

### Request specs (`spec/requests/games_spec.rb`)

- `GET /games/:id` (show) renders `genre: Action` (singular) when the
  primary is set; renders `genre: —` when nil. Sad: garbage `:id` still
  404s.
- `GET /games/:id.json` envelope returns `"genre": "Action"` (singular
  string field), not `"genres": ["Action"]`. Edge: when nil, returns
  `"genre": null`.
- `GET /games` list-mode column header reads `genre` (singular). Edge:
  rows whose primary is nil render `—`.

### View / partial specs

- `spec/views/games/show.html.erb_spec.rb` — label `genre:` (singular),
  value is the primary genre name or em-dash.
- `spec/views/games/_list_mode.html.erb_spec.rb` — `genre` column header,
  one value per row.
- `spec/views/games/_genres_shelf.html.erb_spec.rb` — every sub-shelf
  membership reads from `primary_genre_id` (no duplication of a
  multi-genre game across sub-shelves).

### Helper spec

- If `display_genre` (renamed) helper lands, `spec/helpers/games/...`
  covers nil, present, sanitized output.

### System spec

- ONE new scenario in `spec/system/games_index_spec.rb` (or
  `games_show_spec.rb`): a game has 3 IGDB genres; the index Genres
  outer-shelf shows it under EXACTLY ONE sub-shelf (the alphabetical
  winner). Re-sync the same game with a different IGDB genre set;
  refresh; the game has hopped to a new sub-shelf and is no longer in
  the old one.

---

## Open questions

1. **Should the JSON `/games/:id.json` envelope rename `genres: [...]` to
   `genre: "name"` in v2, or keep both keys (legacy + new) for back-compat?**
   Architect lean: rename outright; the only known consumers are pito's own
   MCP / CLI surfaces, which we own and can update in the same wave. The
   parity follow-up tracks the MCP / CLI rename.
2. **Picker tie-break — confirm alphabetical case-insensitive is the
   existing behavior** (audit the picker file at implementation time). If
   the existing tie-break is different (e.g. lowest IGDB id), document and
   keep, or escalate.
3. **Re-pick on EVERY sync vs only on genre-set change?** Architect lean:
   re-pick always; the picker is cheap (single sort over a few rows). If
   the implementer measures pain, gate on `saved_change_to_genres?` (which
   requires a custom tracker since `genres` is an association, not a
   column).
