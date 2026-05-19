# Phase 27 — dropped

Scope-drift ledger for `/games` revamp work that was ORIGINALLY scoped in
`plan.md` (01a–01g) but CUT or REPLACED before the phase closed. Each entry
traces back to a log session, ADR, or user-direction note. Append-only;
sorted structural-first, polish-last.

`plan.md` checkbox edits remain forbidden per CLAUDE.md — checkboxes here are
ticked as `[x]` with implementation notes that already mention the v2 spec
that superseded the original scope. This file is the auditable companion.

## Models / data

## 2026-05-17 — `User#preferred_games_display_mode` enum + column

- **Item:** `users.preferred_games_display_mode` integer column +
  enum (`grid`, `list`, `shelves_by_letter`) + `Users::GamesPreferencesController`
  (`PATCH /users/games_preferences`) — all dropped via migration
  `20260516232156_drop_preferred_games_display_mode_from_users.rb`.
- **Rationale:** v2 spec 05 collapsed `/games` to a single shelves-only
  layout. The three-mode switcher and its persistence have no consumer.
- **Plan link:** ticked under `01d — Display mode switcher + three modes`
  checkbox set with v2-spec-05-supersedes annotation.
- **Driver:** `[skipci] 2026-05-17 — v2 spec 05 Games index shelves-only`
  log entry.

## 2026-05-17 — Xbox as canonical platform

- **Item:** Xbox chip-family slug DROPPED from `KNOWN_LOGOS` /
  `Platforms::ChipComponent::SLUG_BRAND`. Xbox-only games render no
  platform chip at all on `/games` or `/games/:id`.
- **Rationale:** User direction round 9 — "full coverage but ignore
  Xbox"; the player does not own Xbox hardware and Xbox games stay in
  the IGDB join without a render surface.
- **Plan link:** removes the addition that landed 2026-05-11 (see
  `additions.md > Xbox added as canonical platform`); the original
  `plan.md` 01a seed list never included Xbox.
- **Driver:** Round 9 + ADR 0014 in the wave A–D log entry.

## 2026-05-17 — GoG + Epic as chip-family rows

- **Item:** GoG and Epic dropped from the chip taxonomy (`KNOWN_LOGOS`)
  and from the filter token set. Steam absorbs the entire PC family at
  the model layer via `Platform::IGDB_ID_TO_CANONICAL_SLUG` collapse.
- **Rationale:** ADR 0014 family-collapse — Steam is the PC ecosystem's
  canonical chip; GoG/Epic-only ownership routes through the same
  `steam` chip token at the chip + filter layer.
- **Plan link:** rewrites the `01a` seed checkbox ("ensure PS5, Switch
  2, Steam, GoG, Epic exist by slug at boot"); GoG + Epic seed rows
  may persist as `Platform` records but do not surface as chip families.
- **Driver:** ADR 0014; round 10 + 11 in the wave A–D log entry.

## Display + layout modes

## 2026-05-17 — Three-mode display switcher (grid / list / shelves)

- **Item:** `Games::DisplayModeSwitcherComponent` (delivered as
  `games/_display_mode_switcher` partial) + the three mode partials
  (`_grid_mode.html.erb`, `_list_mode.html.erb`,
  `_shelves_by_letter_mode.html.erb`) deleted. The
  `?display=grid|list|shelves` URL param no longer resolved.
- **Rationale:** v2 spec 05 — `/games` collapsed to a single shelves
  layout. The three-mode UX was the original 01d plan; user direction
  reframed `/games` as one dense browse surface.
- **Plan link:** rewrites `01d — Display mode switcher + three modes`.
- **Driver:** v2 spec 05 log entry; spec
  `specs-v2/05-games-index-shelves-only.md`.

## 2026-05-17 — List-mode sortable columns + sticky letter headings

- **Item:** Sort-column UI, sortable header HTML, sticky-letter heading
  CSS, `tr.letter-head` rows, bulk-select `[ ]` checkbox column on the
  list-mode table — all deleted with the list-mode partial.
- **Rationale:** Same as above — list mode no longer exists.
- **Plan link:** ticked under `01d` list-mode bullets with
  v2-spec-05-supersedes annotation.
- **Driver:** v2 spec 05 log entry.

## 2026-05-17 — Per-platform shelves on `/games` (`@platforms_shelves`)

- **Item:** `GamesController#index` `@platforms_shelves` assignment
  + the per-platform shelf render in `index.html.erb` removed.
- **Rationale:** v2 spec 05 layout dropped per-platform shelves; the
  `owned_on=<slug>` filter-row token is the canonical per-platform
  surface now.
- **Plan link:** outside the original checkbox set (this was an
  in-flight 01b extension); cut in v2 spec 05.
- **Driver:** v2 spec 05 log entry.

## Game show / edit page

## 2026-05-17 — `/games/:id/edit` page (and `Game#edit` action)

- **Item:** `resources :games` lost `:edit` + `:update`;
  `GamesController#edit` + `#update` deleted; `app/views/games/edit.html.erb`
  deleted; `local_only_params` helper deleted.
- **Rationale:** Wave C rebuilt `/games/:id` around inline interactions
  (ownership chips toggle directly, `[resync]` POSTs from the
  breadcrumb, `[delete]` opens the confirm modal). No standalone edit
  form survives.
- **Plan link:** rewrites `01f — Game show/edit per-platform ownership
  UI` — the show side stayed (per-platform chips); the edit side was
  retired.
- **Driver:** Wave C1 in the wave A–D log entry.

## 2026-05-17 — Game show right-pane stores + ratings + details tables

- **Item:** RIGHT pane stripped of: stores section (Steam / GoG / Epic
  store links table), ratings table (multiple per-source rows), detail
  time-to-beat table (replaced by single 3-column row), local-fields
  table, RIGHT-pane platforms heading + chip row.
- **Rationale:** Wave C7 rewrote the RIGHT pane to `<section
  class="game-summary">` + hairline + `<section class="game-ttb">`
  only.
- **Plan link:** outside the original 01f checkbox set (the surfaces
  were not enumerated as plan items, but they shipped historically and
  were cut here for the audit trail).
- **Driver:** Wave C7 in the wave A–D log entry.

## 2026-05-17 — Per-game-platform played/recorded breakdown

- **Item:** Per-platform `played` + `recorded` indicators (e.g. "played
  on PS5, recorded on Steam") REJECTED by the user. Single `[played]`
  and `[recorded]` chips render instead, both as visual placeholders
  derived from `@game.played_at` and `@game.video_game_links.exists?`.
- **Rationale:** Wave C4 architect proposed per-platform breakdown;
  user pushed back as scope creep on a polish wave.
- **Plan link:** outside plan; cut before shipping.
- **Driver:** Wave C4 in the wave A–D log entry.

## Per-tile chrome

## 2026-05-17 — Platform-logo PNG pipeline (lib/tasks/pito_platform_logos.rake)

- **Item:** `lib/tasks/pito_platform_logos.rake` deleted; its spec
  deleted; `public/platforms/*.png` (12 files), `lib/support/platforms/*.png`
  (3 files), `spec/fixtures/files/platforms/*.png` (3 files) deleted;
  `spec/assets/tailwind/tile_platform_logos_css_spec.rb` deleted;
  `platform_logos_helper.rb` shrank from 223 → ~137 lines (dropped
  `LOGO_SIZES`, `LOGO_COLORS`, `LOGO_ALT_LABELS`, `platform_logo_tag`,
  `platform_logo_img`); `.platform-logo--{black,white}` CSS block
  stripped from `application.css`.
- **Rationale:** User direction 2026-05-17 — switch to text chips with
  a single color set for both themes (see `additions.md > Platform
  chips replace platform-logo PNG pipeline`). The rake task + PNG
  pipeline had no consumer post-rewrite.
- **Plan link:** retires the v2 spec 07 work entirely.
- **Driver:** Wave B in the wave A–D log entry; user memory
  `project_platform_logos_to_text_chips`.

## 2026-05-17 — Release year on tile caption row

- **Item:** Release-year fragment removed from the letter-shelf rich
  tile caption row. Tile now: cover image with chip overlay on
  bottom-right corner + caption row with title only.
- **Rationale:** Round-4 user direction — tile chrome optimized for
  scan density; release year belongs on the game detail page.
- **Plan link:** outside original plan; refines the 01c rich-tile
  shape.
- **Driver:** Round 4 in the wave A–D log entry.

## 2026-05-17 — `MutedCountBadgeComponent` (parenthesized count text)

- **Item:** `MutedCountBadgeComponent` slated for deletion in favour of
  canonical `StatusBadgeComponent.new(label: count.to_s, kind: :neutral)`.
  Earlier rendered shelf-heading counts as parenthesized text `(2)`;
  wrong shape vs the badge family taxonomy.
- **Rationale:** Round-4 user direction — shelf-heading game counts
  use the muted-badge primitive, not a parallel text-span shape.
- **Plan link:** outside plan; correction within the badge family.
- **Driver:** Round 4 in the wave A–D log entry.

## Filter row

## 2026-05-17 — `recorded` filter chip + `Games::RecordedChipComponent`

- **Item:** `recorded` filter token dropped from the locked chip set;
  `Games::RecordedChipComponent` (Wave C4 addition) slated for removal;
  the recorded row on `/games/:id` ownership section dropped.
- **Rationale:** User direction round 7 — "drop recorded as played and
  recorded is the same thing." The played chip absorbs the signal.
- **Plan link:** rewrites the `01b` chip set definition
  (`recorded — game.videos.exists?`).
- **Driver:** Round 7 in the wave A–D log entry; ADR 0013.

## 2026-05-17 — Platform-precedence combinator (P-1 / P-2 / C-1 / C-3)

- **Item:** The 01b platform-precedence combinator (P-1 unchecked-owned
  + platform-X; P-2 owned-checked + platform-X; C-1 not_owned + platform-X;
  C-3 contradiction) REPLACED by ADR 0013's 4-axis cascade with
  conditional mutex.
- **Rationale:** The original semantics couldn't express
  `owned + played + wishlist` (valid per ADR 0013 cascade) or
  per-platform played binding. User reported zero-result query that
  motivated the rewrite.
- **Plan link:** rewrites `01b — Platform-precedence combinator`
  checkbox.
- **Driver:** ADR 0013; round 7 in the wave A–D log entry.

## 2026-05-17 — `?display=` query-string preservation on filter row

- **Item:** Filter row `query_string_overrides:` hash dropped the
  `display:` key. Only `genre:` and `collection:` survive.
- **Rationale:** v2 spec 05 retired display-mode persistence; no
  consumer left for `?display=`.
- **Plan link:** rewrites `01b` chip-href preservation contract.
- **Driver:** v2 spec 05 log entry.

## Genre + collection shelves

## 2026-05-17 — Outer `<h2>genres</h2>` heading on Genres outer shelf

- **Item:** Outer `<h2>genres</h2>` heading dropped from
  `_genres_shelf.html.erb`. Per-sub-shelf `<h3>` headings carry the
  genre label now.
- **Rationale:** 2026-05-11 polish bundle Fix 1 — denser shelf layout;
  the outer label was redundant against the per-sub-shelf headings.
- **Plan link:** outside original plan; polish.
- **Driver:** `2026-05-11 — /games polish bundle` log entry.

## 2026-05-17 — `★` star glyph on rating display

- **Item:** App-wide retirement of the `★` star glyph; new
  `GamesHelper#game_rating_display(game)` returns `<NN>/100`.
  `STAR_GLYPH` constant preserved on the helper but unused.
- **Rationale:** 2026-05-11 polish bundle Fix 5 — terser numeric-only
  rating display fits the dense layout better.
- **Plan link:** outside plan; polish.
- **Driver:** `2026-05-11 — /games polish bundle` log entry.

## 2026-05-17 — `Demo Collection` seed

- **Item:** `Demo Collection` seed row renamed to `currently playing`;
  new `now playing` collection seed (`Pragmata` + `Red Dead Redemption
  2`) added.
- **Rationale:** Six-bundled-follow-ups dispatch — `Demo Collection`
  was a placeholder name; user asked for descriptive seed.
- **Plan link:** outside plan; seeds.
- **Driver:** `2026-05-11 — six bundled /games follow-ups` log entry.

## 2026-05-11 — Original 01c outer-shelf-of-sub-shelves design

- **Item:** v1 `_genres_shelf` / `_collections_shelf` design (one tile
  per genre, one tile per collection) REPLACED by 01c-v2 nested shelves
  (each outer shelf iterates one sub-shelf per non-empty bucket; each
  sub-shelf is a horizontally-scrolling row of game tiles at the
  `:shelf` cover variant).
- **Rationale:** 01c-v2 user direction — denser browse surface than
  flat tiles. Empty buckets hidden end-to-end (reverses v1's "always
  render with placeholder" rule).
- **Plan link:** rewrites `01c — Genres and Collections shelves`.
- **Driver:** `[skipci] 2026-05-11 — sub-spec 01c-v2 Nested shelves`
  log entry.

## 2026-05-11 — 01c-v2 per-collection sub-shelves of game tiles

- **Item:** 01c-v2 collections layout REPLACED by single-row
  tile-per-collection + modal (see `additions.md > Collections shelf
  restructure`). The `_collection_sub_shelf_row.html.erb` partial
  deleted.
- **Rationale:** User direction mid-session — "collections is just one
  row with the compound cover art."
- **Plan link:** rewrites `01c` post-v2.
- **Driver:** `2026-05-11 — Collections shelf restructure` log entry.

## Index page chrome

## 2026-05-17 — `<h2>all</h2>` "all-games partition" heading

- **Item:** `<h2>all</h2>` heading retired from `/games`. The letter
  shelves wrapper is the whole listing in v2 spec 05.
- **Rationale:** Single-layout collapse made the partition sentinel
  redundant.
- **Plan link:** outside plan (polish Fix 8 had renamed it `all games`
  → `all`); v2 spec 05 retires it entirely.
- **Driver:** v2 spec 05 log entry.

## 2026-05-17 — `[+N editions]` badge on the index

- **Item:** The `[+N editions]` multi-version badge no longer renders
  on the `/games` index. Game show page is the canonical surface for
  the badge.
- **Rationale:** v2 spec 05 letter shelves use
  `Games::CoverComponent` directly (no rich-tile chrome); the badge
  has no slot on the bare-cover tile.
- **Plan link:** outside plan; consequence of v2 spec 05's layout
  rewrite. If a follow-up wants the badge back on the index, extend
  `Games::CoverComponent` with an optional overlay or restore the
  rich `_tile.html.erb` partial in the letter shelves' tile slot.
- **Driver:** v2 spec 05 "Open / deferred" notes.

## 2026-05-17 — `status` column on list-mode table

- **Item:** `status` computed column (`recorded` / `released` /
  `scheduled` / `unreleased` token) dropped from the list-mode table.
- **Rationale:** 2026-05-11 polish bundle Fix 3 — `released` column
  carries the same signal; status was a derived field, not a
  persisted one. Later moot — list mode itself dropped in v2 spec 05.
- **Plan link:** outside plan; polish that was then mooted.
- **Driver:** `2026-05-11 — /games polish bundle` log entry.

## Keybindings

## 2026-05-17 — Bulk leader-menu rows (`- bulk_delete`, `r bulk_resync`)

- **Item:** `menus.games.items` lost `[- bulk_delete]` + `[r bulk_resync]`;
  `menus.bundles.items` lost `[r bulk_resync]`.
- **Rationale:** Wave D D4 + spec 09 + user brief item 8 — bulk
  operations on the games listing were never wired up; the leader
  rows were aspirational.
- **Plan link:** outside plan; keybinding cleanup.
- **Driver:** Wave D4 in the wave A–D log entry.

## 2026-05-18 — Non-/games surfaces on the leader root menu

- **Item:** `menus.root.items` lost `h` (help), `c*` (channels),
  `C*` (videos), `V*` (videos again), `P*` (projects), `N*`
  (notifications), and the original `G+` entry. Root trimmed to
  `Gl games` + `S settings` + `q quit` (TUI-only) + `Q logout`.
- **Rationale:** User direction — keep the root menu narrow; per-page
  affordances live in `page_actions:`.
- **Plan link:** outside plan; user-direction sweep.
- **Driver:** `2026-05-18 leader menu popup restructure` log entry.
