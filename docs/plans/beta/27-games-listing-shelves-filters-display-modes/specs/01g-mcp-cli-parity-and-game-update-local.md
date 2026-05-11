# 01g — MCP / CLI Parity and `game_update_local` Plural Ownership

> Depends on `01a` (data model) and `01b` (filter row + semantics). Extends the
> MCP `game_update_local` tool to accept plural `platform_owned_ids`, auto-wraps
> singular `platform_owned_id` for back-compat, and mirrors the filter row +
> plural ownership in the `pito` CLI Games view.

---

## Goal

Web, MCP, and CLI agree on the same shape for per-platform ownership and the
same filter semantics. MCP `game_update_local` accepts plural IDs. The CLI TUI
Games view exposes the same ten-chip filter set as web and reads / writes the
plural ownership shape via MCP.

---

## Files touched

MCP:

- `app/mcp/tools/yt/game_update_local.rb` (extend args + handler)
- `app/mcp/tools/yt/games_list.rb` (accept `filters: [...]` argument)
- `app/mcp/tools/yt/game_show.rb` (return plural `platform_owned_ids` in
  response payload; keep singular `platform_owned_id` as the first element of
  the array, deprecated, for one phase)

CLI (Rust):

- `extras/cli/src/api/games.rs` (filter param + plural ownership in response
  struct)
- `extras/cli/src/views/games.rs` (chip row + plural ownership rendering)
- `extras/cli/src/models/game.rs` (struct field rename / dual-field)
- `extras/cli/tests/games_filter_test.rs`

Docs:

- `docs/mcp.md` (document plural shape + back-compat note)

Specs:

- `spec/mcp/tools/yt/game_update_local_spec.rb`
- `spec/mcp/tools/yt/games_list_spec.rb`
- `spec/mcp/tools/yt/game_show_spec.rb`
- `extras/cli/tests/games_filter_test.rs`
- `extras/cli/tests/games_ownership_test.rs`

---

## MCP `yt:game_update_local` contract

### Arguments (new shape)

```json
{
  "id": 123,
  "platform_owned_ids": [4, 7],
  "name": "Optional new name",
  "starred": "yes"
}
```

- `platform_owned_ids: [int]` — plural array of `Platform#id` values the user
  owns the game on.
- `platform_owned_id: int` — DEPRECATED but accepted; the tool auto-wraps it
  into a one-element array. If both are present, `platform_owned_ids` wins and
  the tool returns a `warning` field in the response.
- `starred: "yes" | "no"` — yes/no boundary per project rule.
- Other existing args (e.g. `name`) unchanged.

### Behavior

- Tool resolves the game by `id`.
- For each provided `platform_id`, ensures a `GamePlatformOwnership` exists via
  `find_or_create_by!`.
- For each existing ownership not in the provided set, deletes it (un-owns).
- The operation is atomic — wrapped in a transaction.

### Response shape

```json
{
  "id": 123,
  "name": "...",
  "platform_owned_ids": [4, 7],
  "platform_owned_id": 4,
  "starred": "yes",
  "warning": "..."
}
```

- `platform_owned_id` carried in the response = the first element of the array,
  for back-compat with old MCP clients.
- `warning` populated only when:
  - The caller supplied both singular and plural (and the tool ignored the
    singular).
  - The caller supplied an unknown `platform_id` (which is dropped).
- All booleans in the response use `"yes"` / `"no"` strings.

### Validation

- Unknown `platform_id` values: dropped with a warning, not 422.
- Empty `platform_owned_ids: []` is valid — un-owns the game everywhere.
- Singular `platform_owned_id: null` is treated as "no change" (back-compat with
  callers that pass `null` to mean "skip").

---

## MCP `yt:games_list` filter argument

### Arguments addition

```json
{
  "filters": ["recorded", "ps5", "owned"],
  "display": "list",
  "limit": 50
}
```

- `filters: [string]` — same canonical token set as `01b`.
- `display: "grid" | "list" | "shelves"` — optional; affects the response's
  pagination grouping (list = alpha-grouped sections; shelves = letter buckets;
  grid = flat). MCP doesn't render UI, but the grouping helps clients display
  results sensibly.

### Behavior

- Server runs the same `Games::Filter` query object used by the web view.
- Response is JSON; group structure depends on `display`.

---

## MCP `yt:game_show` response shape

```json
{
  "id": 123,
  "name": "...",
  "platform_owned_ids": [4, 7],
  "platform_owned_id": 4,
  "owned_platforms": [
    { "id": 4, "slug": "ps5", "name": "PlayStation 5", "abbreviation": "PS5" },
    { "id": 7, "slug": "steam", "name": "Steam", "abbreviation": "Steam" }
  ],
  "release_platforms": [
    { "id": 4, "slug": "ps5", "name": "PlayStation 5", "abbreviation": "PS5" },
    { "id": 6, "slug": "switch2", "name": "Nintendo Switch 2", "abbreviation": "Switch 2" },
    { "id": 7, "slug": "steam", "name": "Steam", "abbreviation": "Steam" }
  ]
}
```

- `platform_owned_ids` is the new authoritative field.
- `platform_owned_id` carried for one phase as back-compat; remove next phase
  after callers migrate.

---

## CLI (Rust) shape

### `extras/cli/src/models/game.rs`

```rust
pub struct Game {
    pub id: i64,
    pub name: String,
    // Authoritative plural shape.
    pub platform_owned_ids: Vec<i64>,
    // Back-compat: derived from platform_owned_ids[0] when present.
    #[deprecated(note = "Use platform_owned_ids; will be removed next phase")]
    pub platform_owned_id: Option<i64>,
    // ... existing fields
}
```

### `extras/cli/src/views/games.rs`

- Adds a filter chip row above the games list.
- Same ten canonical tokens.
- Keyboard shortcut to toggle a chip (likely `f` then a letter — final binding
  per the CLI keyboard schema work in a later phase).
- Renders each game's `platform_owned_ids` as a chip row in the detail pane.

### `extras/cli/src/api/games.rs`

- `list_games(filters: Vec<String>) -> Vec<Game>` calls MCP `yt:games_list` with
  the filter array.
- `update_game_ownership(id, platform_ids: Vec<i64>)` calls MCP
  `yt:game_update_local` with `platform_owned_ids`.

---

## Spec pyramid

### MCP — `spec/mcp/tools/yt/game_update_local_spec.rb`

Happy:

- `platform_owned_ids: [4, 7]` creates two ownerships.
- subsequent call with `platform_owned_ids: [4]` removes the Steam ownership.
- `platform_owned_ids: []` un-owns everywhere.
- response carries `platform_owned_ids` AND `platform_owned_id`.
- response booleans serialize as `"yes"` / `"no"`.

Sad:

- unknown `platform_id` (e.g. 9999) → dropped, warning populated.
- `platform_owned_id: 4` AND `platform_owned_ids: [7]` → plural wins, warning
  populated.
- `starred: true` (Boolean, not string) → 422 (yes/no boundary enforced).
- `starred: "1"` → 422.

Edge:

- singular `platform_owned_id: 4` (legacy caller) → auto-wraps to `[4]`, no
  warning.
- singular `platform_owned_id: null` → no-op on ownership.
- duplicate IDs in `platform_owned_ids: [4, 4]` → de-duplicated.

Flaw:

- DB transaction rolls back if mid-operation failure occurs; no partial
  ownership state persists.
- mass-assignment guard — no other Game fields settable beyond the documented
  args.

### MCP — `spec/mcp/tools/yt/games_list_spec.rb`

Happy:

- `filters: ["ps5", "owned"]` returns the same game set as the web request.
- `display: "list"` groups response by alpha letter.
- `display: "shelves"` groups by letter and hides empty letters.

Sad:

- `filters: ["garbage"]` drops the unknown token, returns all games.
- `display: "garbage"` → 422 with a clear message.

Edge:

- `filters: []` returns all games.
- `filters: ["owned", "not_owned"]` returns empty list (contradiction).

Flaw:

- huge `filters` array (1000 entries) handled without 500.

### MCP — `spec/mcp/tools/yt/game_show_spec.rb`

Happy:

- response includes `platform_owned_ids`, `platform_owned_id` (first of the
  plural), `owned_platforms`, `release_platforms`.
- platforms serialize with `id`, `slug`, `name`, `abbreviation`.

Sad:

- unknown game id → 404 with structured error.

### CLI — `extras/cli/tests/games_filter_test.rs`

Happy:

- toggling `ps5` filter calls MCP `yt:games_list` with `filters: ["ps5"]`.
- multi-toggle works.

Sad:

- network failure on filter call surfaces an error banner in the TUI, not a
  crash.

### CLI — `extras/cli/tests/games_ownership_test.rs`

Happy:

- save calls MCP `yt:game_update_local` with `platform_owned_ids`.
- response's plural field updates the local `Game` struct.

Sad:

- 422 from MCP renders a TUI error message.

Edge:

- legacy MCP response carrying only `platform_owned_id` populates plural field
  as a one-element vector (back-compat parsing).

---

## yes / no boundary

Every external boolean on this surface uses `"yes"` / `"no"`:

- MCP request: `starred: "yes" | "no"`.
- MCP response: `starred: "yes" | "no"`.
- CLI wire format mirrors MCP exactly.

No boolean parameters introduced for the filter set (filters are tokens, not
booleans).

---

## Friendly URL preservation

- MCP tools accept either `id` (integer) or `slug` (string) where the existing
  tool already supports both. New plural field doesn't affect resolution.

---

## Manual test recipe

1. From the MCP inspector (or `bin/mcp` stdio), call `yt:game_update_local` with
   `id: <some game>` and `platform_owned_ids: [4, 7]`. Confirm response carries
   plural + singular fields.
2. Call again with singular legacy form: `platform_owned_id: 4`. Confirm
   ownership reduces to PS5 only; response plural = `[4]`.
3. Call with conflicting form: `platform_owned_id: 4` AND
   `platform_owned_ids: [7]`. Confirm response includes `warning` field; plural
   wins.
4. Call `yt:games_list` with `filters: ["ps5", "owned"]`. Compare result set
   against `/games?filters=ps5,owned` — must match.
5. From `pito` CLI: open the Games view; toggle `ps5` chip; confirm list
   narrows.
6. From `pito` CLI: open a game detail; modify ownership; submit; confirm web
   `/games/:slug` reflects the change.

---

## Cross-stack scope

| Surface    | In scope                       |
| ---------- | ------------------------------ |
| Rails web  | NO — covered by `01b` / `01f`  |
| Rails MCP  | YES — three tools touched      |
| `pito` CLI | YES — Games view + API surface |
| Website    | NO                             |

---

## Open questions

1. **Back-compat lifetime for singular `platform_owned_id`.** Phase 27 ships
   plural authoritative + singular accepted. Drop singular in Phase 28 or leave
   for one additional phase as grace? Architect leans Phase 28 drop (one-phase
   grace).
2. **MCP `yt:games_list` grouping for `display`** — return a flat array plus a
   `groups: { "A": [...], "B": [...] }` companion field, OR return only the
   grouped form when `display != grid`? Architect leans companion field so
   clients can choose.
3. **CLI filter keyboard binding** — `f`-then-letter or a popup? Locked decision
   deferred to the CLI keyboard schema phase; for `01g` the chips are clickable
   via the existing mouse / cursor selection.
4. **CLI ownership editor UX** — same checklist metaphor as web, or a chip row
   with toggle keys? Architect leans chip row + toggle keys (TUI-native).
5. **MCP tool name parity** — `game_update_local` is the existing name; keep, or
   rename to `update_game` for symmetry with other tools? Architect leans keep —
   rename is a separate concern.
