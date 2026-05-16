# Manual test playbook — Phase 27 Games listing rework

**Branch:** `main` **Spec:**
`docs/plans/beta/27-games-listing-shelves-filters-display-modes/plan.md`
**Reviewer run:** 2026-05-11 18:25

Phase 27 reshapes `/games` from a flat grid into a layered surface: nested
top-of-page shelves (Genres outer + per-genre sub-shelves, Custom collections
outer + per-collection sub-shelves), a CSV-state Filter Row (`?filters=`) with
platform-aware semantics, three Display Modes (Grid / List / Shelves-by-letter)
persisted via `User#preferred_games_display_mode`, an explicit 65% `:shelf`
cover variant, per-platform ownership data model + show / edit chip surface,
collection composite covers (six layout variants), and MCP `game_update_local`
plural ownership.

## Pipeline summary

- Code review: 4 non-blocking concerns + 1 BLOCKER (collections cover composer
  is never invoked from production code — see Blockers below).
- Simplify: 3 suggestions (no dead code; some pulldown into SQL would tighten
  the filter query object; per-shelf `count` queries are N+1 ish).
- Test suite: 880 examples, 0 failures across
  `spec/queries/games/filter_spec.rb`, `spec/components/games/`,
  `spec/views/games/`, `spec/requests/games_spec.rb`, `spec/requests/games/`,
  `spec/requests/users/games_preferences_spec.rb`, `spec/system/games_*`,
  `spec/models/{game,platform,game_platform_ownership,collection}_spec.rb`,
  `spec/services/collections/`,
  `spec/jobs/collection_cover_rebuild_job_spec.rb`,
  `spec/mcp/tools/game_update_local_spec.rb`, `spec/services/platforms/`,
  `spec/jobs/platforms/`, `spec/helpers/games/`,
  `spec/helpers/games_helper_spec.rb`. Adjacent suite —
  `spec/models/{game,platform,game_platform_ownership,collection}_spec.rb` — 139
  examples, 0 failures (rerun targeted).
- Security static analysis: Brakeman 8.0.4 — 64 controllers / 66 models / 213
  templates / 0 errors / 0 security warnings. Two obsolete-ignore entries noted,
  both pre-existing.
- Dependency audit: `bundle-audit check --update` — ruby-advisory-db 1080
  advisories, 0 vulnerabilities found.
- Rubocop on touched Ruby files: 22 files inspected, no offenses.
- Cross-stack: no Rust diff this phase (01g CLI half is filed as a follow-up in
  the log — explicitly out of scope here). No website diff.

## Blockers (must clear before user validation passes)

1. **Collection composite cover composer is never invoked from production
   code.** `Collections::CoverComposer.new.call(collection)` has zero callers
   under `app/` (verified with `grep -rn "Collections::CoverComposer" app/`).
   Every reference is either a comment (model / partial / job docs) or a test
   setup. The 01h spec's "Cache hit / miss flow" describes the composer running
   lazily on first miss, and the view partial
   (`app/views/games/_collection_sub_shelf.html.erb`) comments say "composer
   runs lazily on first miss" — but nothing in the page-render path actually
   triggers the call. Result: a Collection with 2+ games always falls to the
   `else` branch and shows `[empty]` because `composite_cover_checksum` stays
   `NULL` forever. Manual test step #5 (six_grid / netflix5 / quad / netflix3 /
   pair variants) cannot pass until a caller is wired in (most likely a
   `before_action` in `GamesController#index` that walks
   `@collections_for_shelf` and invokes the composer, or a controller-level
   `Collections::CoverComposer.new.call(collection)` inside
   `_collection_sub_shelf.html.erb`). The 01h log on 2026-05-11 verifies
   "committed implementation against the spec" but does not document where the
   trigger landed — because it didn't. File the fix to the rails impl agent; the
   composer service, the layout engine, the eviction job, the `Compositable`
   mixin, the model hooks, and the migrations are all fine — only the trigger is
   missing.

## Concerns and suggestions (non-blocking)

1. `app/views/games/index.json.jbuilder` emits
   `json.platform_owned_slug @filter[:platform_owned_slug]` but
   `GamesController#sanitized_filter` (lines 330–337) only ever sets `:genre_id`
   and `:collection_id`. Real callers (CLI / MCP Phase 21) therefore always see
   `"platform_owned_slug": null`. The view spec at
   `spec/views/games/index.json.jbuilder_spec.rb:12` assigns `@filter` manually
   so the drift is invisible at the spec layer. Decide whether the JSON should
   echo `filter_tokens` from the 01b filter row instead, or drop the key.
2. **N+1 queries on the nested shelves.** `_genre_sub_shelf.html.erb` runs
   `genre.games.count` and `genre.games.order(LOWER(title)).limit(30).to_a` per
   genre. `_collection_sub_shelf_row.html.erb` does the same for collections,
   plus the leading composite tile partial runs `collection.games.count` and
   (when the composer eventually lands) re-queries
   `collection.games.order(LOWER(title)).limit(6).to_a`. For an install with
   many non-empty genres / collections this is 2N–4N queries plus a tile cover
   URL per game. Tighten by preloading + computing the counts in the controller
   (e.g. via
   `Genre.left_joins(:games).group(:id) .having('COUNT(games.id) > 0')` with a
   count alias passed to the partial).
3. **Filter query object materializes intermediate id arrays.**
   `Games::Filter#apply_status` and `#apply_combined_ownership_and_platform`
   call `.ids` on each per-token scope and then `where(id: union_ids)`. The ids
   fetch is a separate `SELECT id FROM games WHERE ...` round-trip per token.
   For small databases this is fine; for a 10k+ row library it does `K` extra
   SELECTs where `K` = active token count. SQL-level OR composition via
   `Game.where(...).or(...)` would keep the relation lazy. Optional — marked
   because the matrix tests cover correctness, only performance is at stake.
4. **`FilterChipComponent` / `_display_mode_switcher` bypass
   `BracketedLinkComponent`.** Both emit the bracket shape inline
   (`[<span class="bl">label</span>]`) rather than rendering the canonical
   component. Visual output is byte-identical to what `BracketedLinkComponent`
   produces (same `bl` span pattern, same `bracketed` class). The chip needs the
   extra `chip--active` modifier and the `data-filter-token` attribute; the
   switcher needs `button_to` form wrapping. Reviewer convention A allows
   hand-rolled HTML "when the wrapper primitive can't carry the required data
   attributes" — but consider extending `BracketedLinkComponent` to accept
   arbitrary `class:` / `data:` so future divergence is curtailed.
5. **Inline `<style>` blocks in two partials.** `_list_mode.html.erb` declares a
   `<style>` block for the sticky letter-head and table layout;
   `_display_mode_switcher.html.erb` carries inline styles per button. The
   pattern reads cleanly and is documented in-line (the list mode comment says
   "Sticky-heading CSS is intentionally inlined here … so the partial is
   self-contained and the system spec can verify"), but it does mean the
   assets-pipeline + Tailwind story for this surface is split between
   `app/assets/tailwind/application.css` (cover variants) and the partials
   (mode-specific layout). Non-blocking — flag if the design system later wants
   every partial-level style block in the stylesheet.

## Known issues to address before validation (rolled forward)

- Collection cover composer trigger missing (see Blocker #1). Until fixed, step
  #5 of the manual walkthrough below will fail visually — every multi-game
  collection sub-shelf will render `[empty]`.
- 01g CLI half (`extras/cli/src/api/games.rs`, `views/games.rs`, the Rust tests)
  is filed as a deferred follow-up in the phase log. The phase plan's
  `01g — MCP / CLI parity` block has three unticked checkboxes (CLI TUI filter
  row, Rust tests, MCP `yt:games_list` filters arg / `yt:game_show` plural). Not
  Phase 27's blocker — out of scope here.
- `01c-v2` `Game#primary_genre_id` migration + `Game#primary_genre`
  association + Game show / edit primary-genre picker — deferred per master
  dispatch ("no new migrations"). Multi-genre games appear in every sub-shelf
  their `game_genres` rows touch. Documented.

## Manual test steps (setup preamble)

These steps confirm the dev-server side of the rework before you exercise the
UI. Skip if you already ran `bin/setup` recently in this branch.

1. **Action:** From the repo root, `bin/setup` (idempotent) then `bin/dev`
   (start Postgres + Redis + Puma + Sidekiq + Tailwind watcher). **Expected:**
   all four services come up; Puma logs `Listening on http://127.0.0.1:3000`.
2. **Action:** `bin/rails db:seed` to seed the five Phase 27 platform rows (PS5,
   Switch 2, Steam, GOG, Epic). **Expected:** Console prints
   `5 platform rows present.` (or N ≥ 5 if you already had others).
3. **Action:** `bin/rails console` → `Game.count`, `Genre.count`,
   `Collection.count`, `Platform.count`. **Expected:** Non-zero counts. If
   empty, hydrate via the IGDB add-game flow or fixtures.
4. **Action:** Seed at least one Custom Collection with 2, 3, 4, 5, and 6+ games
   respectively so the composite-cover variants have something to render
   against. (Console:
   `c = Collection.create!(name: "Pair test"); Game.where("title ILIKE 'a%'").limit(2).update_all(collection_id: c.id)`
   — repeat with 3 / 4 / 5 / 6+.) **Expected:** Each collection's `.games.count`
   returns the seeded number.

## Manual test steps (gated quality probes)

5. **Action:**
   `bundle exec rspec spec/queries/games/filter_spec.rb spec/components/games/ spec/views/games/ spec/requests/games_spec.rb spec/system/games_index_spec.rb spec/system/games_display_modes_spec.rb spec/system/games_platform_ownerships_spec.rb spec/system/games_steam_shelf_spec.rb spec/models/game_spec.rb spec/models/platform_spec.rb spec/models/game_platform_ownership_spec.rb spec/services/collections/ spec/jobs/collection_cover_rebuild_job_spec.rb spec/mcp/tools/game_update_local_spec.rb spec/requests/games/ spec/requests/users/games_preferences_spec.rb spec/helpers/games/ spec/helpers/games_helper_spec.rb spec/services/platforms/ spec/jobs/platforms/`
   **Expected:** `880 examples, 0 failures`.
6. **Action:** `bundle exec brakeman -q -w2 --no-progress`. **Expected:**
   `Security Warnings: 0`. Two obsolete-ignore entries shown, both pre-existing.
7. **Action:** `bundle exec bundler-audit check --update`. **Expected:**
   `No vulnerabilities found`.

## Cleanup

```bash
# Drop seeded composites if you regenerated them mid-session.
rm -f tmp/pito-assets/composites/collection-*.jpg

# Re-run db setup if your local state has drifted from main.
bin/rails db:drop db:create db:migrate db:seed

# Reset display-mode preference for the validating user (sets back to grid).
bin/rails runner 'User.find_by(email: ENV["VALIDATE_AS"]).update!(preferred_games_display_mode: :grid)'
```

---

## User Validation

[ ] 1. **`/games` loads with nested top shelves.** Visit
`http://localhost:3000/games` while logged in. Above the filter row, confirm an
outer `<section data-shelf="outer-genres">` titled **genres** (lowercase per the
design system), and below it an outer `<section data-shelf="outer-collections">`
titled **custom collections**. Inside each outer section, one sub-shelf per
non-empty genre / collection, each with an `<h3>` row showing the bucket name on
the left.

[ ] 2. **Empty buckets are hidden end-to-end.** Create a brand-new Genre (or
Collection) via the rails console (`Genre.create!(name: "Empty test genre")`)
that owns zero games. Refresh `/games`. Confirm the new genre's name does NOT
appear anywhere in the outer Genres shelf — no muted placeholder, no empty
`<h3>`, the bucket is suppressed entirely. Same rule for Collections.

[ ] 3. **`[see all]` sub-shelf overflow link.** Pick a genre that owns more than
30 games (or temporarily attach 31 games to one genre via the rails console:
`g = Genre.first; Game.limit(31).each { |x| x.genres << g unless x.genres.include?(g) }`).
Refresh `/games`. Confirm the sub-shelf shows a `[see all]` bracketed link to
the right of the genre's `<h3>`. Click it. The URL becomes `/games?genre=<slug>`
(or `?genre=<id>` fallback) and the all-games partition below narrows to that
genre.

[ ] 4. **Sub-shelf game tiles render at 65% (98×130).** Right-click any game
tile inside a sub-shelf → Inspect Element. Confirm the outer `<a>` carries
`class="game-cover game-cover--shelf"` and inline
`style="...width: 98px; height: 130px;"`. The `<img>` inside should be 98×130
too. (Compare against an all-games-grid tile below the filter row — those carry
`game-cover--grid` and 150×200.)

[ ] 5. **Collection cover composite renders per layout variant.** **THIS STEP IS
BLOCKED — see Blockers above.** With composer wiring in place, each Custom
collection sub-shelf would render an
`<img class="collection-cover-composite" width="98" height="130">` as its
leading tile. For 2 games → 1 × 2 side-by-side pair; 3 → big left + 2 small
stacked right (netflix3); 4 → 2 × 2 quad; 5 → big left + 2 × 2 right (netflix5);
6+ → 3 × 2 six_grid. Until the trigger lands, every multi-game collection's
leading tile shows `[empty]` instead.

[ ] 6. **Filter row click narrows the all-games grid.** Below the shelves,
confirm a row of ten bracketed chips in this exact order:
`[recorded] [released] [owned] [not owned] [scheduled] [ps5] [switch2] [steam] [gog] [epic]`.
Click `[owned]`. The URL becomes `/games?filters=owned`; the all-games grid
below narrows to games with at least one `game_platform_ownerships` row. A
`[clear all]` link appears flush-right of the chips.

[ ] 7. **Combine filters across buckets (AND).** With `[owned]` still active,
click `[released]`. URL becomes `/games?filters=owned,released` (or
`released,owned`; order preserves click sequence). Then click `[ps5]`. URL
becomes `/games?filters=owned,released,ps5`. The grid narrows to games released,
owned by you, and specifically on PS5 (per filter precedence rule P-2 — "owned
on platform-X").

[ ] 8. **`[clear all]` resets the filter row.** Click `[clear all]`. URL drops
`?filters=` entirely (preserves `?display=` / `?genre=` / `?collection=` if any
were set). All ten chips revert to the inactive state; the grid shows every game
again.

[ ] 9. **Contradiction notice for `owned + not_owned`.** Click `[owned]` then
click `[not owned]`. URL becomes `/games?filters=owned,not_owned`. Confirm a
muted notice renders below the chip row reading
`(owned and not owned together — no        matches)`. The chip row continues to
render normally; no red, no JS dialog, no `data-turbo-confirm`. The all-games
grid shows "no games match this filter." (or the empty-state copy).

[ ] 10. **URL round-trip preserves filter state.** With several filter chips
active (e.g. `?filters=ps5,owned`), reload the page (`Cmd-R` / `Ctrl-R`).
Confirm the same chips remain active and the grid is still narrowed. Open the
URL in a fresh incognito window (logged in) — same state.

[ ] 11. **Display mode switcher — `[grid] [list] [shelves]`.** Top-right of
`/games`, flush with the `<h1>games</h1>` row, confirm three bracketed buttons.
The currently active mode carries the `active` class (visible via
`data-active-mode="grid"` on the wrapper `div`). Click `[list]`: the page
reloads with `?display=list`, the all-games partition rerenders as an
alpha-grouped table with sticky letter-head rows, and the `[list]` button now
carries `active`. Refresh — the list mode persists (your
`User#preferred_games_display_mode` enum was written via PATCH
`/users/games_preferences`). Click `[shelves]`: the partition rerenders as one
shelf per first-letter bucket, empty letters hidden. Click `[grid]` to return.

[ ] 12. **`?display=list` URL override is per-request only.** With your
persisted preference still set to `:shelves_by_letter` from step #11, visit
`/games?display=list`. The page renders as a list. Visit `/games` (no display
param). The page returns to the persisted preference (`:shelves_by_letter`).
Per-request override DID NOT persist.

[ ] 13. **New user defaults to grid.** Sign out, register a fresh user (or have
the rails console create one —
`User.create!(email:         "fresh@example.test", password: "verylongpassword123")`),
sign in as them, visit `/games`. The grid mode is active by default (the
`preferred_games_display_mode` column defaults to integer `0` = `grid` via the
migration's `default: 0`).

[ ] 14. **Game show page — per-platform ownership chip list.** Visit any
`/games/:slug` show page. Inside the **local fields** table, the **owned on**
row shows one bracketed chip per platform the user owns the game on
(alphabetical case-insensitive), followed by a `·` separator and an
`[edit ownership]` link. If no platforms are owned, the row shows the muted
`(not owned on any platform)` placeholder followed by the edit link. Each
ownership chip href is `/games?filters=<slug>,owned` — clicking it filters the
index.

[ ] 15. **Game edit — per-platform ownership editor.** From the show page click
`[edit ownership]`. URL becomes `/games/:slug/platform_ownerships/edit`. The
form shows one fieldset per platform the game is released on (sourced from IGDB
`platforms_available`) PLUS any platforms the user already owns the game on,
alphabetical. Each row carries a `_own` yes/no checkbox (leading hidden field
locks the default to `"no"`), plus optional `acquired_at` date input, `store`
text input, `notes` textarea. Tick PS5 + Steam, set `store: "official"` on one,
save. Redirect lands on the show page with `notice: ownership updated.` Re-open
the editor and confirm the persisted state matches what you saved.

[ ] 16. **MCP `game_update_local` plural ownership.** From an MCP client (or the
rails console + `Mcp::Tools::GameUpdateLocal.call` directly), invoke the tool
with `{ id: "<slug>", platform_owned_ids: [1, 2], confirm: "yes" }`. Response
includes `platform_owned_ids: [1, 2]`, the back-compat scalar
`platform_owned_id: 1` (first element), and no warning. Re-invoke with one
unknown platform id (e.g. `[1, 9999]`) — response includes a `warning` field
reading `unknown platform_id(s) dropped: 9999.` and the persisted ownership
reflects only id 1. Re-invoke with BOTH the singular and plural forms supplied —
response includes a warning reading `both \`platform_owned_id\` and
\`platform_owned_ids\` supplied; plural
wins.`Re-invoke with        `platform_owned_id:
null`(singular null) — no ownership         change occurs (no-op per legacy back-compat). Re-invoke with        `platform_owned_ids:
[]` (explicit empty plural array) — all ownership rows are wiped (un-owned
everywhere).

[ ] 17. **Tile two-line meta.** On the all-games grid, hover any tile. Confirm
the cover image is 150 × 200, the title renders below on its own line
(ellipsis-truncated when too long), and a second muted line shows
`★ <RR> · <YYYY>` where `<RR>` is the zero-padded `igdb_rating` (`5 → 05`,
`93 → 93`, `100 → 100`) and `<YYYY>` is the `release_year`. Find a game with no
rating — the line collapses to just `<YYYY>`. Find a game with neither rating
nor year — the second line is omitted entirely (only the title shows).

[ ] 18. **No JS confirm anywhere.** With the browser DevTools Network + Console
tabs open, exercise the destructive surfaces Phase 27 touches: un-tick an owned
platform in the editor and save (step #15); delete a game via the `[-]`
breadcrumb link on a show page (that routes through `/deletions/...` per project
convention). Confirm zero `window.confirm` / `window.alert` /
`data-turbo-confirm` calls in the Console or DOM. The platform-ownership editor
relies on form submit; game deletion routes through the action-confirmation
page.

[ ] 19. **Bracket convention — no inner padding.** Inspect any chip in the
filter row, the `[clear all]` link, the display-mode switcher buttons, and the
`[see all]` overflow links. None of them render as `[ label ]` with inner
padding; all render flush-bracket `[label]` per the design system. The only
permitted inner spaces are the checkbox shapes `[ ]` / `[x]`, which do not
appear on `/games`.

[ ] 20. **Cross-stack sweep (CLI / website unaffected).** Open the `pito` TUI
binary (`extras/cli/`) and confirm the games view renders. (The 01g CLI half is
filed as a follow-up; the TUI should still render the legacy shape — confirm no
regression.) Visit `extras/website/` locally (or production `pitomd.com`) — the
marketing surface is untouched.
