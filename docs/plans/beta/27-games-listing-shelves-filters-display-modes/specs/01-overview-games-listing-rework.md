# 01 — Games Listing Rework (Umbrella)

> Umbrella spec for Phase 27. The seven sub-specs (`01a`–`01g`) carry the
> implementation contracts. This file gathers cross-cutting concerns and the
> dispatch order so reviewers can validate the whole rework as one phase.

---

## Goal

Replace the flat `/games` grid with a dense, navigable surface composed of:

1. Two top shelves — Genres and Collections — alphabetical, horizontally
   scrollable, using a new `:shelf` cover-art variant.
2. A multi-select Filter Row with platform-aware semantics matching §2 of the
   source-of-truth note verbatim.
3. Three Display Modes — Grid (default), List (alpha-grouped, sortable),
   Shelves-by-letter (one row per letter, empty letters hidden) — persisted
   per-user via `User#preferred_games_display_mode`.
4. A `game_platform_ownerships` join table replacing the legacy singular
   `games.platform_owned_id`. Per-platform ownership is the new authoritative
   shape across web, CLI, and MCP.

The rework ships across all three surfaces (web, MCP, CLI) in lockstep so the
new ownership shape and filter contract are consistent everywhere.

Source-of-truth note:
`docs/notes/2026-05-11-11-26-17-games-listing-shelves-filters-display-modes.md`.

---

## Files touched (umbrella roll-up)

The detailed file lists live in each sub-spec. This roll-up exists so the
reviewer agent can see the full surface in one glance.

Migrations / models:

- `db/migrate/*_create_platforms.rb`
- `db/migrate/*_create_game_platform_ownerships.rb`
- `db/migrate/*_drop_platform_owned_id_from_games.rb`
- `db/migrate/*_add_preferred_games_display_mode_to_users.rb`
- `app/models/platform.rb`
- `app/models/game_platform_ownership.rb`
- `app/models/game.rb` (associations + scopes)
- `app/models/user.rb` (enum)
- `db/seeds.rb` (platform seed entry)

Services + jobs:

- `app/services/platforms/sync_from_igdb.rb`
- `app/jobs/platforms/sync_from_igdb_job.rb`
- `app/queries/games/filter.rb`

Controllers + routes:

- `app/controllers/games_controller.rb`
- `app/controllers/games/platform_ownerships_controller.rb`
- `app/controllers/settings/games_display_modes_controller.rb`
- `config/routes.rb`

Views + components:

- `app/views/games/index.html.erb`
- `app/views/games/_grid.html.erb`
- `app/views/games/_list.html.erb`
- `app/views/games/_shelves_by_letter.html.erb`
- `app/views/games/show.html.erb`
- `app/views/games/edit.html.erb`
- `app/components/games/filter_row_component.{rb,html.erb}`
- `app/components/games/genres_shelf_component.{rb,html.erb}`
- `app/components/games/collections_shelf_component.{rb,html.erb}`
- `app/components/games/display_mode_switcher_component.{rb,html.erb}`
- `app/components/games/cover_component.{rb,html.erb}` (extended with `:shelf`)
- `app/components/games/platform_ownership_editor_component.{rb,html.erb}`

MCP:

- `app/mcp/tools/yt/game_update_local.rb` (extended)
- `app/mcp/tools/yt/games_list.rb` (filter parity)

CLI (Rust):

- `extras/cli/src/views/games.rs`
- `extras/cli/src/api/games.rs`

Specs (sweep per project rule D):

- `spec/models/platform_spec.rb`
- `spec/models/game_platform_ownership_spec.rb`
- `spec/models/game_spec.rb` (scopes + ownership integration)
- `spec/models/user_spec.rb` (display-mode enum)
- `spec/services/platforms/sync_from_igdb_spec.rb`
- `spec/jobs/platforms/sync_from_igdb_job_spec.rb`
- `spec/queries/games/filter_spec.rb`
- `spec/components/games/filter_row_component_spec.rb`
- `spec/components/games/genres_shelf_component_spec.rb`
- `spec/components/games/collections_shelf_component_spec.rb`
- `spec/components/games/display_mode_switcher_component_spec.rb`
- `spec/components/games/cover_component_spec.rb`
- `spec/components/games/platform_ownership_editor_component_spec.rb`
- `spec/requests/games_spec.rb`
- `spec/requests/games/platform_ownerships_spec.rb`
- `spec/requests/settings/games_display_modes_spec.rb`
- `spec/system/games_index_spec.rb`
- `spec/system/games_display_modes_spec.rb`
- `spec/system/games_platform_ownerships_spec.rb`
- `spec/mcp/tools/yt/game_update_local_spec.rb`
- `spec/mcp/tools/yt/games_list_spec.rb`
- `extras/cli/tests/games_filter_test.rs`

Docs:

- `docs/design.md` (display-mode switcher + filter row chips + `:shelf` variant)
- `docs/mcp.md` (plural `platform_owned_ids` documented)

---

## Acceptance (umbrella)

- [ ] All sub-spec acceptance lists tick green.
- [ ] `/games` renders the two shelves + filter row + display-mode switcher +
      grid by default for a fresh user.
- [ ] Filter combinations from the §2 worked example pass in
      `spec/queries/games/filter_spec.rb` and the matching system spec.
- [ ] `:shelf` cover variant is rendered server-side at 65% of grid size (~152 ×
      203 px). Asset cache key differs from `:grid`.
- [ ] Display mode persists across sessions for the authenticated user.
- [ ] MCP `game_update_local` accepts plural `platform_owned_ids` and singular
      `platform_owned_id` (auto-wrapped).
- [ ] CLI Games view exposes the same chip set; toggling matches the web view.
- [ ] Friendly URLs preserved across `/games/:slug`, ownership editor.
- [ ] No `alert` / `confirm` / `prompt` anywhere in the touched surface.
- [ ] yes/no boundary applied on every external boolean.
- [ ] Brakeman + bundler-audit clean. `docs/design.md` and `docs/mcp.md`
      updated.

---

## Manual test recipe (umbrella smoke)

Detailed per-spec recipes live in `01a`–`01g`. Phase-level smoke:

1. Fresh DB. `bin/rails db:migrate && bin/rails db:seed`.
2. Confirm `Platform.count >= 5` (PS5, Switch 2, Steam, GOG, Epic seeded).
3. Open `/games` — observe two shelves (Genres + Collections), alphabetical,
   horizontal-scroll skinned, with `:shelf`-variant tiles.
4. Filter row below shelves; click `[ps5]` then `[owned]`; URL becomes
   `?filters=ps5,owned`; `[clear all]` link appears; click it; URL clears.
5. Click `[list]` top-right; reload; list mode persists.
6. Click `[shelves]`; letter shelves render; empty letters hidden.
7. Open any game's show page; edit per-platform ownership; tick PS5 + Steam;
   save; back on `/games`, `?filters=ps5,owned` includes the game; switch to
   `?filters=switch2,owned` — game does NOT appear.
8. From `pito` CLI: navigate to Games view; toggle `ps5`; same filter result.

---

## Cross-stack scope

| Surface            | In scope this phase | Sub-spec(s) |
| ------------------ | ------------------- | ----------- |
| Rails web `/games` | YES                 | 01b–01f     |
| Rails MCP          | YES                 | 01g         |
| `pito` CLI (Rust)  | YES                 | 01g         |
| Cloudflare website | NO                  | n/a         |

---

## Open questions (umbrella roll-up)

Cross-spec questions surface here so the master agent answers once. Per-spec
open questions stay in their respective `01a`–`01g` files.

1. **`acquired_at` / `store` / `notes` in v1?** (see `01a`).
2. **Filter chip default state — all off or all on?** Architect leans all off
   (matches "empty filter row = show everything").
3. **Drop `games.platform_owned_id` outright in this phase?** Architect leans
   yes (no derived primary-platform pointer).
4. **Saved-view integration depth.** Locked default-mode lives on `User`;
   saved-views still carry filter-set + display-mode in the URL they save. Open:
   should the saved-view UI show the active display mode in its summary line?
   Architect leans yes — cheap to add.
5. **List-mode sticky headings — JS or pure CSS?** Architect leans pure CSS.
6. **IGDB platform sync trigger.** Locked seed + weekly cron job + manual rake
   task.

---

## References

- Source note:
  `docs/notes/2026-05-11-11-26-17-games-listing-shelves-filters-display-modes.md`.
- `docs/agents/architect.md` — spec pyramid (D), yes/no boundary (E).
- `docs/design.md` — bracketed-link convention, monospace style.
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`.
- `CLAUDE.md` hard rules.
