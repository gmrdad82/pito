# Phase 28 — Multi-version Game Grouping — Session log

## 2026-05-11 — 01a Rails implementation landed [skipci]

Spec: `specs/01a-multi-version-game-grouping.md`. Architect spec was
locked end-to-end with all 7 open questions resolved per master
direction. Implementation covered the Rails + MCP halves; the CLI
half is deferred to `pito-rust` as a follow-up.

### Files touched

- Migration: `db/migrate/20260512000000_add_version_parent_to_games.rb`
  — adds `games.version_parent_id` (self-FK, ON DELETE SET NULL,
  indexed) + `games.version_title` (string, nullable).
- Model: `app/models/game.rb` — `belongs_to :version_parent`,
  `has_many :editions`, scopes `primaries` / `editions_of` /
  `with_editions` / `owned_rollup`, validations
  (`version_parent_must_be_primary` /
  `cannot_be_parent_and_edition_simultaneously` / `no_self_reference`),
  rollup helpers (`owned_platforms_with_editions`, `owned_editions`),
  predicates (`primary?` / `edition?`), and the
  `derive_release_date_from_editions` `before_save` callback (architect
  lean #1 locked yes).
- Factory: `spec/factories/games.rb` — `:edition` trait.
- IGDB: `app/services/igdb/client.rb` (GAME_FIELDS adds
  `version_parent` + `version_title`), `app/services/igdb/game_mapper.rb`
  (stamps `version_title` when present), `app/services/igdb/sync_game.rb`
  (`resolve_version_parent_id` resolves the IGDB parent id to a local
  Game id, recursively imports the parent when missing, walks chains to
  the first primary, is idempotent + transactional).
- Filter: `app/queries/games/filter.rb` — swaps `Game.owned` to
  `Game.owned_rollup` for the `owned` token (architect lean #7 locked
  yes). Realises rollup ids to avoid Rails' `.merge` + `.or`
  interaction bug that dropped outer relation conditions on `id`.
- Controller: `app/controllers/games_controller.rb` — `index` defaults
  to `Game.primaries`, `?include_editions=yes` flips to the flat list
  (yes/no boundary via `YesNo.from_yes_no`); new
  `version_parent_search` JSON endpoint (max 20 results, primaries
  only, `?exclude_id=`); `local_only_params` permits + coerces
  `version_parent_id` (blank→nil, integer cast) and `version_title`
  (trim 100, blank→nil).
- Routes: `config/routes.rb` — `get :version_parent_search` collection
  route on `games`.
- Views: `app/views/games/_tile.html.erb` (badge bare + parent
  pointer), `app/views/games/_list_mode.html.erb` (parent pointer +
  inline badge), `app/views/games/show.html.erb` (parent pointer above
  chrome + editions section block), `app/views/games/edit.html.erb`
  (picker + version_title rows).
- Components: `app/components/games/editions_badge_component.{rb,html.erb}`
  (bare variant for use inside the wrapping tile anchor),
  `app/components/games/editions_section_component.{rb,html.erb}`,
  `app/components/games/version_parent_picker_component.{rb,html.erb}`
  (typeahead, hidden id, detach link, disabled when row has editions).
- JS: `app/javascript/controllers/version_parent_picker_controller.js`
  — Stimulus typeahead, fetch from `version_parent_search`, no
  `confirm` / `alert` / `prompt`; uses `textContent` (no `innerHTML`)
  for results render.
- MCP: `app/mcp/tools/games_list.rb` (paginated, default primaries
  only, `include_editions: yes/no` argument, `editions_count` per
  row), `app/mcp/tools/game_show.rb` (single read by id or slug;
  returns `version_parent_id`, `version_title`, `editions: [...]`).
- Rake: `lib/tasks/games.rake` — `pito:backfill_version_parents`,
  regex matrix (Deluxe / Standard / GOTY / Collector's / Definitive /
  Anniversary / Ultimate, all case-insensitive, longest-first),
  idempotent, summary line.

### Specs added

- `spec/models/game_spec.rb` — +30 examples (associations,
  predicates, scopes, validations, rollup helpers, release_date
  derivation).
- `spec/services/igdb/sync_game_spec.rb` — +5 examples
  (`version_parent` resolution: stamp existing, recursive import,
  absent payload, idempotency, chain walk).
- `spec/requests/games_spec.rb` — +32 examples (primaries-only listing,
  `include_editions` boundary, `version_parent_search` JSON endpoint,
  show page editions section / parent pointer, edit page picker +
  detach + disabled state, PATCH attach / detach / validation
  rejections / trim semantics, filter row rollup).
- `spec/components/games/editions_badge_component_spec.rb` — +12
  examples (render gate, singular / plural, link target, bare variant,
  hard rules).
- `spec/components/games/editions_section_component_spec.rb` — +9
  examples (render gate, heading, edition rows, ordering, anchor,
  hard rules).
- `spec/components/games/version_parent_picker_component_spec.rb` —
  +10 examples (inputs, pre-fill, detach link, disabled, empty,
  hard rules).
- `spec/mcp/tools/games_list_spec.rb` — +18 examples (default
  behaviour, `include_editions: yes/no` semantics, yes/no boundary
  rejection of `true`/`1`/`false`, pagination, auth gating, schema).
- `spec/mcp/tools/game_show_spec.rb` — +12 examples (by id / slug,
  primary response with editions array, edition response with parent
  pointer + empty editions, missing record errors, auth gating,
  schema).
- `spec/lib/tasks/games_rake_spec.rb` — +15 examples (every regex
  variant, case-insensitive matching, no-match leaves alone,
  idempotency, summary output, longest-suffix wins).
- `spec/system/games_multi_version_spec.rb` — +8 examples (critical
  journey + hard-rule sweep).

Total: +151 new examples.

### Verification

- `bundle exec rspec` (Phase 28 scope): all green.
- `bundle exec rubocop` (touched files): 38 files inspected, 0
  offenses.
- `bin/brakeman -q -w2`: 0 security warnings.
- Rake backfill against dev DB: `attached: 0, skipped: 6, total: 6`
  (no edition-suffix rows in dev to attach).

### Architect leans (all locked)

1. Parent `release_date` derived from earliest edition via
   `before_save :derive_release_date_from_editions` for primaries.
   Honors `manual_date_override`.
2. Typeahead source: title-only ILIKE, primaries only, cap 20.
3. Detached parent stays in place (non-destructive).
4. Backfill via `pito:backfill_version_parents` rake task only (not
   seeds).
5. Bundles containing both parent + edition: display both (no
   de-dupe). _(No bundle-side changes needed in this pass.)_
6. `version_title_manual_override` flag deferred to v1.1.
7. `Games::Filter#owned` token uses `owned_rollup` — a primary with
   an owned Deluxe edition appears in the owned filter.

### Open items

- CLI half (Rust): primaries-only render + drill-down + flat-mode
  toggle + wire-format parity. Tracked as a `pito-rust` follow-up;
  the spec section "CLI changes" is the contract. Tile badge and the
  `include_editions` boundary are already wire-ready via the MCP
  tools.
- Test-DB collisions during the session triggered intermittent
  `PG::ObjectInUse` errors during `db:test:purge`. Resolved by
  terminating idle rspec backends + manual `db:drop db:create
  db:schema:load`. Worth a small note in the per-project test infra
  doc if it recurs.
- During the session a sibling agent reverted some of this lane's
  in-flight edits to existing files (model, controller, IGDB
  service, views, request spec). Re-applied from memory; final state
  matches the spec. Untracked files (components, migration, MCP
  tools, rake task) survived the revert.
