# Phase 27 — Games Listing Rework: Shelves, Filter Row, Display Modes, Per-Platform Ownership

> Read `docs/plans/beta/beta.md` first. Then read this `plan.md`. Then read the
> umbrella spec at `specs/01-overview-games-listing-rework.md` and the seven
> sub-specs in order.

---

## Goal

Rework `/games` from a single flat grid into a denser, more navigable surface:
two top shelves (Genres, Collections), a multi-select Filter Row with
platform-aware semantics, three Display Modes (Grid / List / Shelves-by-letter)
with persisted user preference, and per-platform ownership replacing the single
`platform_owned_id` pointer on `Game`.

The phase also introduces a `Platform` model (sourced from IGDB), a
`game_platform_ownerships` join table, an explicit `:shelf` cover-art variant
(65% of grid, pipeline-rendered — no browser-resize), and MCP / CLI parity for
the new plural ownership shape and the filter row.

Source-of-truth note (Mobile drop, verbatim):
`docs/notes/2026-05-11-11-26-17-games-listing-shelves-filters-display-modes.md`.

---

## Scope

In scope:

- New `platforms` table (FriendlyId slug, IGDB platform id, abbreviation).
- New `game_platform_ownerships` join table — per-platform ownership of a game.
- Filter row component with multi-select chip state in URL params
  (`?filters=recorded,ps5,owned`), platform-aware semantics, clear-all link.
- Genres and Collections shelves at the top of `/games`, alphabetical,
  horizontal-scroll skinned.
- Display mode switcher (Grid / List / Shelves-by-letter), persisted via a new
  `User#preferred_games_display_mode` enum.
- List mode with alpha-grouped sticky letter headings and a sortable column set.
- Shelves-by-letter mode (empty letters hidden).
- Explicit `:shelf` cover-art variant rendered server-side (65% of grid size).
- Game show + edit screens gain a per-platform ownership editor.
- MCP `game_update_local` accepts plural `platform_owned_ids: [int]` (singular
  `platform_owned_id` auto-wrapped for back-compat).
- CLI filter parity in the `pito` TUI Games view.
- Saved-view kind `games` is extended to carry the active filter set and display
  mode (final integration locked in `01d`).

Out of scope:

- IGDB game-data sync changes beyond pulling `platforms` (no metadata refresh
  redesign).
- Re-styling the existing horizontal-scroll skin.
- Adding `acquired_at` / `store` / `notes` fields beyond the agreed v1 columns
  (see open question in `01a`).
- Multi-user permission changes (single-install + multi-user stands; see
  `docs/decisions/0003-drop-tenant-single-install-multi-user.md`).
- Touching any other listing (`/channels`, `/videos`, `/projects`, etc.).

---

## Locked decisions (master agent)

1. **Shelf cover variant size: 65%** of grid (≈ 152 × 203 px against the current
   234 × 312 grid). Architect's recommendation per the user's challenge — "50%
   may be too aggressive." Explicit `:shelf` variant in the cover-rendering
   pipeline; never browser-resize / CSS scaling.
2. **Per-platform ownership table: `game_platform_ownerships`** —
   `id, game_id, platform_id (FK), acquired_at (nullable), store (string, nullable, free-text for now), notes (text, nullable), timestamps`.
   Unique on `(game_id, platform_id)`. (See `01a` open question on whether to
   ship `acquired_at` / `store` / `notes` in v1 or defer to a metadata
   follow-up.)
3. **Platform model: `Platform`** —
   `id, name, slug (FriendlyId), igdb_platform_id (unique), abbreviation, timestamps`.
   Names pulled from IGDB on first sync; phase introduces an initial seed + a
   Sidekiq sync job.
4. **Filter row component: `FilterRowComponent`** — multi-select chips. State in
   URL (`?filters=recorded,ps5,owned`). Click toggles a chip. `[clear all]` link
   appears once at least one filter is active. Empty filter row = show
   everything (locked).
5. **Platform filter precedence** (verbatim from source note §2):
   - Platform filters apply to the platform the user actually owns the game on.
   - For unreleased / not-yet-owned games, the platform filter still matches if
     the game is scheduled on that platform.
   - If the user owns the game on at least one platform, the platform filter
     matches only the platforms the user owns it on.
6. **Filter definitions:**
   - `recorded` — `game.videos.exists?` (linked Video records).
   - `released` — IGDB `first_release_date` in the past.
   - `scheduled` — IGDB `first_release_date` in the future.
   - `owned` / `not owned` — presence / absence of any
     `game_platform_ownerships` row.
7. **Display mode persistence:** `User#preferred_games_display_mode` enum
   (`grid`, `list`, `shelves_by_letter`). Default `grid`. URL param
   `?display=list` may override per-request but does not persist unless the user
   clicks a switcher button.
8. **Display mode switcher:** small control top-right of `/games`, above the
   filter row. Three bracketed-link buttons `[grid]` `[list]` `[shelves]`.
9. **List mode columns:** cover thumb, title, platforms owned, genres, status.
   Sortable. Sticky letter group headings.
10. **Shelves-by-letter:** one shelf per letter; empty letters hidden (per
    source-note lean).
11. **MCP `game_update_local`:** `platform_owned_ids: [int]` plural. Old
    singular `platform_owned_id: int` accepted and auto-wrapped to a one-element
    array for back-compat. Boundary stays yes/no for booleans.

---

## Cross-stack scope

| Surface              | In scope this phase                                          |
| -------------------- | ------------------------------------------------------------ |
| Rails web (`/games`) | YES — full rework (shelves, filter row, three modes, editor) |
| Rails MCP            | YES — `game_update_local` plural; filter parity              |
| `pito` CLI (Rust)    | YES — TUI Games view gets the filter row + plural ownership  |
| Cloudflare website   | NO — marketing surface untouched                             |

---

## Sequencing

Per the Mobile note's dispatch list:

1. **01a — Per-platform ownership data model.** Blocking for filter semantics
   and the show/edit editor. Introduces `Platform`, `GamePlatformOwnership`,
   `game_id ↔ platform_id` unique constraint, IGDB platform sync, factories,
   model specs.
2. **01b — Filter row + platform semantics.** Depends on `01a`. Introduces
   `FilterRowComponent`, `Games::Filter` query object, URL state, request +
   component + system specs for the full filter-combination matrix.
3. **01c — Genres and Collections shelves.** Parallel with `01b`. Top-of-page
   two horizontal shelves, alphabetical, skinned-scroll, `:shelf` cover variant.
4. **01d — Display mode switcher + three modes.** Parallel with `01b` / `01c`.
   Adds `User#preferred_games_display_mode`, the switcher control, Grid / List
   (alpha-grouped) / Shelves-by-letter modes.
5. **01e — Shelf cover art variant.** Parallel with everything. Adds the
   explicit `:shelf` variant entry to the cover-rendering pipeline at 65% of
   grid size.
6. **01f — Game show/edit per-platform ownership UI.** Depends on `01a`. Editor
   checklist of platforms (sourced from IGDB), tick the ones owned; plumbing the
   per-platform metadata (per `01a` v1 decision).
7. **01g — MCP / CLI parity + `game_update_local` plural.** Depends on `01a` and
   `01b`. Extends MCP tool to plural; filter parity for CLI + MCP.

---

## Checkboxes

### 01a — Per-platform ownership data model

- [x] Migration: create `platforms` (slug FriendlyId, `igdb_platform_id` unique,
      abbreviation, name). _(Existing Phase 14 `platforms` table relaxed:
      `igdb_id` made nullable, `slug` made NOT NULL + unique, FriendlyId
      (slugged + history) added. Column name kept as `igdb_id` per the locked
      "if not exists" guard — the existing column was the equivalent of
      `igdb_platform_id`.)_
- [x] Migration: create `game_platform_ownerships` (game_id, platform_id,
      acquired_at, store, notes; unique on `(game_id, platform_id)`).
- [x] Models: `Platform`, `GamePlatformOwnership`, associations on `Game`.
- [x] Factory: `platforms`, `game_platform_ownerships`.
- [x] Service: `Platforms::SyncFromIgdb` (one-shot + idempotent).
- [x] Job: `Platforms::SyncFromIgdbJob` wrapping the service.
- [x] Seed: ensure PS5, Switch 2, Steam, GOG, Epic exist by slug at boot.
- [x] Model specs: validations, associations, scopes, uniqueness, friendly_id.
- [x] Service spec, job spec.
- [x] Drop / repurpose decision for legacy `games.platform_owned_id` (drop
      outright; backfill recipe documented in migration body).

### 01b — Filter row + platform semantics

- [x] `FilterRowComponent` with chip rendering, `[clear all]` link.
      (Also `FilterChipComponent` for single-chip rendering. Both
      include `Games::FiltersHelper` for shared logic.)
- [x] `Games::Filter` query object — composes scopes for each filter token.
      (Lives at `app/queries/games/filter.rb`; partitions tokens into
      Status / Ownership / Platform / Unknown buckets per spec.)
- [x] URL param parser / serializer for `?filters=token1,token2`.
      (`app/helpers/games/filters_helper.rb` — `parse_filter_tokens`,
      `parse_dropped_tokens`, `toggle_filter`, `chip_label`.)
- [x] Scopes on `Game`: `recorded`, `released`, `scheduled`, `owned`,
      `not_owned`, `on_platform(slug)`, `owned_on_platform(slug)`.
      (`owned` / `not_owned` / `owned_on` shipped with 01a;
      `recorded` / `released` / `scheduled` / `on_platform` /
      `released_on` / `scheduled_on` added here. Spec wrote
      `first_release_date` in pseudo-form; the actual schema column
      is `release_date` (date) — day-granular semantics identical.)
- [x] Platform-precedence combinator (matches §2 of source note exactly).
      (P-1 / P-2 / C-1 / C-3 all locked in `Games::Filter#build_results`;
      `contradiction?` predicate surfaces C-3 to the component.)
- [x] yes/no boundary on boolean URL inputs (none in v1; reserved guard).
- [x] Model + query-object + component + request + system spec sweep.
      (16 model + 50 query + 21 helper + 17 chip-component + 18 row-
      component + 16 request + 11 system = 149 new examples, all green.)

### 01c — Genres and Collections shelves

- [x] `Games::GenresShelfComponent`, `Games::CollectionsShelfComponent`.
      (01c-v2 rewrote both as nested partials —
      `app/views/games/_genres_shelf.html.erb` /
      `_collections_shelf.html.erb` for the outer shelves;
      `_genre_sub_shelf.html.erb` / `_collection_sub_shelf_row.html.erb`
      for the per-bucket sub-shelves.)
- [x] Alphabetical ordering. (Preserved across v1 and v2; case-
      insensitive `LOWER()` on both outer buckets and inner games.)
- [x] Use existing skinned horizontal-scroll partial / classes.
      (Reuses the `steam-shelf` Stimulus controller and the same
      `display: flex; overflow-x: auto` shelf-row pattern.)
- [x] Tile = `:shelf` cover variant (depends on `01e`). (01c-v2 —
      each sub-shelf renders `Games::CoverComponent.new(game:,
      variant: :shelf)` per game. Cover-variant pixel width is
      managed by 01e independently; the consumer just opts into the
      `:shelf` variant key.)
- [x] Component specs, system spec. (01c-v2 — rewrote
      `spec/views/games/_genres_shelf.html.erb_spec.rb`, added
      `spec/views/games/_collections_shelf.html.erb_spec.rb`,
      `spec/views/games/_genre_sub_shelf.html.erb_spec.rb`,
      `spec/views/games/_collection_sub_shelf_row.html.erb_spec.rb`,
      rewrote the "01c" describe blocks in
      `spec/system/games_index_spec.rb` and `spec/requests/games_spec.rb`.)

01c-v2 notes:
- The `Game#primary_genre_id` migration + Compositable concern
  extension + Game show/edit primary-genre picker are deferred
  follow-ups (parent dispatch — "no new migrations" / cover-variant
  width is 01e's surface). The implementation falls back to the
  existing `genre.games` join — a multi-genre game appears in
  every sub-shelf its joins touch. Migration is queued.
- The new `_collection_sub_shelf_row.html.erb` partial leads each
  collection sub-shelf with the existing 01h `_collection_sub_shelf`
  leading-tile partial (composite cover when stamped; passthrough
  single cover; `[empty]` placeholder). The 01c-v2 spec's naming
  collision (it pre-reserved `_collection_sub_shelf.html.erb` for
  the row partial) is resolved by suffixing the new file `_row`.
- Empty bucket hidden — when no genre / collection owns any game,
  the outer `<section>` is suppressed end-to-end (no `<h2>`, no
  placeholder copy). Reverses v1's "always render with placeholder"
  rule (01c-v2 locked decision #7).

### 01d — Display mode switcher + three modes

- [x] Migration: add `users.preferred_games_display_mode` (integer enum, default
      0 / `grid`).
- [x] Model: enum on `User` (`grid`, `list`, `shelves_by_letter`).
- [x] `Games::DisplayModeSwitcherComponent` — three bracketed-link buttons.
      (Delivered as the `games/_display_mode_switcher` partial per master
      dispatch; component-vs-partial reframe noted in the session log.)
- [x] Persist on click (PATCH `/users/games_preferences`). (Master-dispatch
      reframed the URL from `/settings/games_display_mode/:mode` to the `users`
      namespace — see session log.)
- [x] Grid view (existing). (Extracted into `games/_grid_mode` for branching.)
- [x] List view — alpha-grouped, sticky letter headings, sortable columns (cover
      thumb, title, platforms owned, genres, status). (Sort-column UI deferred
      until 01a's per-platform ownership shape stabilises; structure +
      letter-head sticky CSS landed.)
- [x] Shelves-by-letter view — one shelf per letter, empty letters hidden.
- [x] yes/no boundary not applicable (no boolean inputs).
- [x] Model + request + view + component + system spec sweep. (System spec
      landed 2026-05-11 re-dispatch as `spec/system/games_display_modes_spec.rb`
      — 13 examples covering default mode, persistence via switcher, URL
      override, shelves-by-letter empty-letter hiding, list mode letter-head
      interleaving, filter-row composition, and CLAUDE.md hard-rule guards.
      The 01a / 01c drift that wedged the controller index also cleared this
      session — `GamesController#index` now resolves `@display_mode` and
      branches the all-games partition into one of the three new partials.)

### 01e — Shelf cover art variant

- [x] Add `:shelf` variant entry to the cover-rendering pipeline at 65% of grid
      (98 × 130 px against the real 150 × 200 grid — the plan's original
      `≈ 152 × 203 px against 234 × 312` was a baseline mismatch; locked
      decision §1 reads "65%", actual baseline is 150 × 200).
- [x] Update the cover-art ViewComponent / helper to accept `variant: :shelf`.
      `Games::CoverComponent` owns the size map (`DIMENSIONS`), the
      `data-variant` attribute, and the `.game-cover--<variant>` CSS modifier.
- [x] Asset pipeline + tests confirm size + cache key differ from `:grid`.
      `:grid` resolves to `t_cover_big`, `:shelf` resolves to `t_cover_small_2x`
      — distinct IGDB CDN tokens, distinct browser cache entries.
- [x] Component spec covering both variants. 38 examples in
      `spec/components/games/cover_component_spec.rb` (happy / sad / edge /
      flaw + friendly-URL preservation + `DIMENSIONS` introspection).

### 01f — Game show/edit per-platform ownership

- [x] On `Game#show`: list platforms the game is released on (from IGDB), with
      ownership state indicators. _(Implemented as
      `Games::OwnedPlatformsChipListComponent` — bracketed chips, one per owned
      platform, alphabetical case-insensitive; each chip links to
      `/games?filters=<slug>,owned`. Empty state renders muted
      `(not owned on any platform)` placeholder.)_
- [x] On `Game#edit`: checklist of release platforms; tick the ones owned.
      _(Editor lives at `/games/:slug/platform_ownerships/edit` — dedicated
      page, not crammed onto the local-fields edit form per the spec's open
      question #1.)_
- [x] Form submits to a nested controller `Games::PlatformOwnershipsController`
      (`PATCH /games/:slug/platform_ownerships`).
- [x] Friendly URL preserved.
- [x] No JS confirm — destructive un-tick of "owned" goes through the in-form
      submit (no separate confirmation page is needed for ownership toggles;
      delete-all goes through `/deletions/...` per project rule).
- [x] Request + system + view spec sweep.

### 01g — MCP / CLI parity

- [x] MCP `game_update_local` accepts `platform_owned_ids: [int]`.
- [x] Singular `platform_owned_id: int` auto-wrapped to one-element array.
- [x] yes/no boundary on every boolean argument.
- [x] MCP tool spec — singular accepted, plural accepted, mixed
      (plural-wins-with-warning) covered.
- [ ] CLI TUI Games view gains the same filter chip set + plural ownership.
      _(MCP half landed; CLI half deferred — see `log.md`.)_
- [ ] Rust tests for the CLI surface. _(deferred with the CLI half above.)_
- [ ] MCP `yt:games_list` `filters: [...]` argument + MCP `yt:game_show` plural
      shape. _(Spec body lists these; plan checkbox set focuses on
      `game_update_local`. Filed as follow-up — both gate on the `01b` filter
      row + `Games::Filter` query object landing.)_

---

## Open questions (surfaced for master agent)

1. **`acquired_at` / `store` / `notes` columns** — ship in v1, or keep a
   skeleton `(game_id, platform_id)` table and defer metadata to a follow-up?
   Architect leans v1 since the columns are nullable and cheap; the editor UI
   can ship with the basics and fill in metadata fields later.
2. **Filter chip default state** — all chips off (show everything) or all chips
   on (show everything explicitly)? Architect leans "all off" per the source
   note's "Empty filter row = show everything."
3. **Existing `games.platform_owned_id`** — drop in this phase, or keep as a
   derived "primary platform" pointer to one of the ownerships? Architect leans
   drop, since the user note treats the new join table as the authoritative
   shape and any "primary" notion can be reintroduced later.
4. **Saved-view integration** — does display-mode + filter row persist via the
   existing saved-view system, OR a separate user preference, OR both? Source
   note says "saved-view system or user preference." Locked decision is
   `User#preferred_games_display_mode` for the user-level default; saved-views
   still capture the filter+display URL state per view.
5. **Sticky letter headings on list mode** — JS-driven (IntersectionObserver for
   swap-in highlights) or pure CSS `position: sticky`? Architect leans pure CSS
   for simplicity; JS only if there's a UX gap.
6. **"(none)" placeholder for empty letters in shelves-by-letter** — hide
   (source note's lean) or show with placeholder? Locked: **hide**.
7. **IGDB platform sync trigger** — on phase startup migration, on each game
   create, or via a rake task? Architect leans seed + Sidekiq job
   (`Platforms::SyncFromIgdbJob`) cron-scheduled weekly; rake task for manual
   one-off refresh.
8. **Shelf cover variant pixel size** — 65% locked. Concretely 152 × 203 px
   against the current 234 × 312 grid. (`01e` carries the asset-pipeline
   detail.)

---

## Quality gates

Standard Beta gates (see `beta.md` §"Per-phase quality gates"). Additional
phase-specific checks:

- Every spec in this phase carries the full pyramid sweep (model / service / job
  / component / helper / validator / lib / MCP / request / system) per
  `docs/agents/architect.md` rule D.
- yes/no boundary applied at every external boolean: URL params, JSON, MCP I/O,
  CLI args.
- No `alert` / `confirm` / `prompt` / `data-turbo-confirm` anywhere. Ownership
  destructive un-ticks go through the form submit; deletion of a `Game` itself
  continues to route through `/deletions/...`.
- Friendly URLs preserved across all touched routes.
- Brakeman + bundler-audit + Dependabot triage clean.

---

## Manual test recipe (high-level)

A detailed recipe per sub-spec lives in the relevant `specs/01*.md` file. The
phase-level smoke test:

1. `bin/setup` (fresh DB) → `bin/rails db:seed` to populate platforms.
2. `bin/dev` → open `http://localhost:3000/games`.
3. Confirm two shelves render at the top (Genres, Collections), alphabetical,
   horizontally scrollable, with `:shelf`-sized covers.
4. Confirm the filter row renders below with chips
   `[recorded] [released] [owned] [not owned] [scheduled] [ps5] [switch2] [steam] [gog] [epic]`.
5. Click `[ps5]` — URL becomes `?filters=ps5`. The grid filters down. A
   `[clear all]` link appears.
6. Click `[owned]` — URL becomes `?filters=ps5,owned`. The grid narrows further
   to games owned on PS5 specifically.
7. Top-right of `/games`, click `[list]` — view switches to alpha-grouped list.
   Refresh — list mode persists for the user.
8. Click `[shelves]` — letter shelves render, empty letters hidden.
9. On any game `show` page, edit per-platform ownership; PS5 + Steam ticked
   shows up correctly in the filter row.
10. From the `pito` CLI, the Games view renders the same chip set; toggling
    `ps5` filters server-side via MCP.

Detailed per-step expected values land in the per-spec manual recipes.

---

## References

- `docs/notes/2026-05-11-11-26-17-games-listing-shelves-filters-display-modes.md`
  (source-of-truth Mobile drop).
- `docs/agents/architect.md` — spec pyramid, pane primitives, yes/no boundary.
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — auth model.
- `docs/design.md` — bracketed-link convention, monospace style, no red outside
  destructive actions.
- `CLAUDE.md` — hard rules (no JS confirm, bulk-as-foundation, secrets in
  credentials).
