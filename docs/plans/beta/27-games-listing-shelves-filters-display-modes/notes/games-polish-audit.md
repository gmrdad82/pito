# /games polish brief — audit against current implementation + pending specs

> Date: 2026-05-17
>
> Cross-checks every sub-requirement in
> `notes/games-polish.md` (the raw 25-item user brief) against (a) the 9
> spec files under `specs-v2/`, (b) commits since 2026-05-10, (c) the
> current working tree, and (d) chat-level user clarifications.
>
> Each sub-requirement gets one of five classifications:
>
> - DONE — landed in a named commit.
> - IN FLIGHT — present in working tree, not yet committed.
> - SPEC LOCKED — covered by a spec file, awaiting wave 4 / 5 dispatch.
> - OVERRIDDEN — user clarified differently in chat; new shape locked.
> - GAP — present in the brief, absent from every spec, not covered by a
>   known chat override. NEEDS USER ATTENTION.
>
> POSSIBLE-OVERRIDE means I am not 100% sure the chat actually clarified;
> escalate for user confirmation.

---

## Reference state

- Wave 1 commit: `cccf79d` — specs 01 (single-genre) + 02 (cover-art
  compositions) + 04 (igdb modal) + 07 (platform logos + rake).
- Wave 2 commit: `d5e248e` — spec 03 (resync job + ActionCable) + spec
  05 (shelves-only) + logos black-mono + rake task specs.
- Wave 3 commit: `1350dbb` — spec 06 filters + PC platforms collapse
  (Steam/GoG/Epic → Steam) + letter shelf rich tile.
- Working tree (uncommitted): tile platform-logo overlay onto the
  cover; cover_component turbo-frame escape; letter shelves swap from
  CoverComponent to `games/tile` partial; platform logos helper PC
  collapse (idgb_id 6/3/14/13/92 → steam); CSS for `.tile-cover-platforms`;
  show.html.erb minor comment refresh; spec 08 doc update.
- Specs 08 (game detail revamp) and 09 (keybindings page actions) are
  written but NOT yet dispatched (wave 4 / 5 pending).

---

## Item 1 — search-as-you-type modal (no horizontal scroll, drop [search] button, [cancel] muted, copy trim)

**Brief excerpts:**

- "has horizontal scroll and has to go."
- "We remove [search] button we search automatically after 5 chars
  written OR by hitting ENTER."
- "[cancel] link has to be our component for [cancel] which is muted."
- "add a game from igdb -> add a game."
- "drop the copy 'type to search igdb.'"

**Sub-requirements:**

1. No horizontal overflow on the modal (CSS audit). DONE — wave 1
   `cccf79d`, `.pane-dialog--wide` modifier, inline `max-width: 720px`
   band-aid removed. (Spec 04 § "CSS overflow audit".)
2. Drop `[search]` button. DONE — wave 1 `cccf79d`,
   `_igdb_search_modal.html.erb` body has no `[search]` element.
3. Auto-fire search at ≥ 5 chars (debounced 250 ms). DONE — wave 1,
   `igdb_search_modal_controller.js` honors `min-chars-value="5"`.
4. Enter overrides cutoff at any length ≥ 1. DONE — wave 1, controller
   short-circuits the guard on `keydown.enter`.
5. `[cancel]` rendered as `BracketedMutedLinkComponent`. DONE — wave 1,
   line 48 of `_igdb_search_modal.html.erb`.
6. Title copy `"add a game from igdb"` → `"add a game"`. DONE — wave 1,
   modal title text confirmed.
7. Placeholder copy trimmed. DONE — wave 1, placeholder reads
   `"search…"`.

All sub-requirements landed. No gaps.

---

## Item 2 — group multiple versions of a game by base title

**Brief excerpt:** "group the multiple versions of a game into the base,
main game title — This has to be specced."

**Sub-requirements:**

1. Multi-version grouping spec exists. OVERRIDDEN — pre-existing Phase
   28 §01a (sub-spec `28-…/specs/01a-multi-version-game-grouping.md`)
   ships this work; the Game model already has `version_parent_id` /
   `version_title` and `Game.primaries`. The Rails + MCP halves are
   already committed (see CLAUDE.md follow-up #2). The Phase 27
   brief item is effectively satisfied by Phase 28 §01a.
2. `/games` listing operates on `Game.primaries` so editions collapse.
   DONE — `GamesController#index` line 144 `scope = @include_editions
   ? Game.all : Game.primaries`.

No gaps — the work belongs to Phase 28, not Phase 27 specs-v2.

---

## Item 3 — eager-fetch IGDB title so breadcrumb does not show "Untitled game"

**Brief excerpt:** "Adding a new game will land for a bit into Untitled
game. Try fetch already the game title to put it in the breadcrumb."

**Sub-requirements:**

1. `[add]` from IGDB row submits the IGDB title alongside `igdb_id`.
   DONE — wave 1 `cccf79d`, `_search_results.html.erb` includes the
   title param.
2. `GamesController#create` permits `[:igdb_id, :title]` and uses the
   pre-seed. DONE — wave 1, controller line ~280–316.
3. Async `GameIgdbSync` still overwrites canonical title later. DONE —
   sync job is unchanged on this path.
4. Legacy "create blank game" branch deleted entirely. DONE — wave 1,
   controller doc says "REMOVED the legacy 'default create empty game'
   branch" (spec 04 § "IGDB-only create surface").

No gaps.

---

## Item 4 — cleanup shelves: per-genre shelf, one collections shelf, short genre names, alphabetical

**Brief excerpts:**

- "We keep the shelves for genre, with each genre on a shelf."
- "After we have collections shelf. One shelf for all collections;
  display order is alphabetical for the collection."
- "Same order apply to the genre when having multiple games on a genre
  shelf."
- "Genre names should be short form like RPG instead of Role Playing
  Game."

**Sub-requirements:**

1. One shelf per genre (Genres outer shelf). DONE — Phase 27 §01c-v2
   nested shelves already shipped (commit `b14f974`, refined later);
   `_genres_shelf.html.erb` + `_genre_sub_shelf.html.erb` present.
2. Collections shelf — single shelf, alphabetical. DONE — wave 2
   `d5e248e` (spec 05) order set in `GamesController#index`.
3. Per-shelf alphabetical sort of games. DONE — controller orders by
   `LOWER(title)` per spec 05 § "Letter bucketing" and § "Collection
   shelf".
4. Short genre names (`RPG`, `JRPG`, `Sim`, `FPS`, …). DONE — wave 2
   `d5e248e`; `app/helpers/genres_helper.rb` carries the
   IGDB-canonical → short-label map; `_genre_sub_shelf.html.erb`
   consumes it.

No gaps.

---

## Item 5 — single main genre per game

**Brief excerpt:** "When a game comes with multiple genres we keep only
1 main genre — this has to be specced and I think we already have this,
but check it out."

**Sub-requirements:**

1. `Game#primary_genre_id` is the single source of truth. DONE — wave
   1 `cccf79d` (spec 01); `Game` model + `Games::PrimaryGenrePicker`
   service + sync re-pick wired in `Igdb::SyncGame`.
2. Backfill migration for legacy NULL rows. DONE — wave 1, data
   migration generated per spec 01.
3. UI rendering uses singular `primary_genre.name`. DONE — `show.html
   .erb` line 153 renders `@game.primary_genre&.name.presence || "—"`
   (interim layout; spec 08 supersedes with primary-bold + secondary-
   normal).

No gaps.

---

## Item 6 — single display mode (shelves-by-letter), drop grid + list, scrollbar revamp, two cover sizes

**Brief excerpts:**

- "We remove multiple display types."
- "We keep only the default ones where we group games by letter."
- "We drop grid and list."
- "We remove the localstorage that we added for this."
- "We have 2 different cover size on this page: one for genres and
  collections and one for the game listing."
- "We'll have a shelf for each letter. If a letter doesn't have games
  we don't display them."
- "All shelves have the games ordered alphabetically inside them."
- "All shelves have horizontal scroll (our themed horizontal scroll)
  when needed."
- "I want our horizontal and vertical scrolls to be revamped /
  visited to be slimmer — probably 4-6px in tickness."

**Sub-requirements:**

1. Drop grid / list display modes (delete partials + switcher). DONE —
   wave 2 `d5e248e` (spec 05).
2. Drop `User#preferred_games_display_mode` enum + controller +
   localStorage. DONE — wave 2 migration drops the column; controller
   gone.
3. Drop URL `?display=` parameter. DONE — wave 2 controller cleanup.
4. One shelf per non-empty letter (`A..Z`, `#` bucket at end). DONE —
   wave 2, `_letter_shelves.html.erb` + `build_letter_buckets`.
5. Empty letter shelves HIDDEN. DONE — wave 2.
6. Alphabetical sort within each bucket. DONE — wave 2.
7. Horizontal scroll on every shelf (themed). DONE — wave 2,
   `steam-shelf` Stimulus controller reused.
8. Slim scrollbar (6 px both axes, sitewide). DONE — pre-Phase-27
   commit `c630afa` (vertical 8→6) + `0e7e430` (initial themed
   scrollbar); spec 05 confirms the unified 6 px is in place
   (`tailwind/application.css` lines 628–631).
9. Two cover sizes: shelf-tile (98×130) for games inside shelves AND
   composition-tile for collections+genres. RESOLVED (user-confirmed
   2026-05-17) — THREE sizes total: small (genre + bundle composite
   tiles), medium (game shelf tiles), large (detail page). Two sizes
   in use on `/games` (small + medium); the third (large) is used on
   `/games/:id` and will be locked in spec 08.

No gaps.

---

## Item 7 — collection cover-art compositions for N=5..9+

**Brief excerpt:** "For collection cover art we use what you already
designer 2up, Netflix, 4up, others but I need you to explain what could
go for 5 games, as for 6 I think we can do 3 up and 3 down, for 7 I
dunno, same for 8 and I'm not sure where to stop and limit to make the
cover art for the first X games from the collection."

**Sub-requirements:**

1. N=1..6 layouts kept (`:passthrough`, `:pair`, `:netflix3`,
   `:quad`, `:netflix5`, `:six_grid`). DONE — pre-existing layouts
   carried forward in spec 02.
2. N=7 → `:netflix7` (big top + 3 mid + 3 bottom). DONE — wave 1
   `cccf79d`, `composite_layout.rb` lines 26–32 + 240.
3. N=8 → `:eight_grid` (2 cols × 4 rows). DONE — wave 1.
4. N=9+ → `:nine_grid` (3×3). DONE — wave 1; cap at 9 contributing
   tiles, 10th+ omitted.
5. Alphabetical contributor ordering. DONE — wave 1, `cover_composer
   .rb` `ordered_games(collection)` orders by `LOWER(games.title)`.

All five sub-requirements landed. No gaps.

---

## Item 8 — drop `- delete` and `r resync` keybinding rows under G games (and `r resync` under G B bundles)

**Brief excerpt:** "Our actions from the keyboard shortcuts for Games
won't have - delete and r resync. Remove these from the G games menu.
Remove r resync from G games -> B bundles."

**Sub-requirements:**

1. Drop `{ key: "-", label: delete, action: { type: bulk_delete } }`
   from `menus.games.items`. SPEC LOCKED — spec 09 files-to-change
   line 218 declares the removal; YAML still contains the row (line
   90 of `config/keybindings.yml`). Pending wave 4/5 dispatch.
2. Drop `{ key: r, label: resync, action: { type: bulk_resync } }`
   from `menus.games.items`. SPEC LOCKED — spec 09, same. YAML still
   contains the row (line 91).
3. Drop `r resync` from `menus.bundles.items`. SPEC LOCKED — spec 09
   files-to-change line 222. YAML still contains the row (line 98).

All three items are spec-locked, not yet shipped.

---

## Item 9 — filter row revamp (single row, defaults checked, URL canonicalization, no pagination)

**Brief excerpts:**

- "The 2 rows of filtering will be reworked."
- "We move these 2 rows up, between title and the first genre shelf."
- "filters … reflects in the URL bar but don't refresh the page."
- "won't have any pagination."
- "Left hand side: [ ] released [ ] scheduled [ ] owned [ ] purchase
  (this is the old not owned) [ ] played"
- "Right hand side: [ ] PS5 [ ] Switch 2 (check naming if it's Switch
  2 or Switch2) [ ] Steam [ ] GoG [ ] Epic (we don't use Xbox)"
- "All these will be defaulted to checked state."
- "url /games would be the same as /games?filters=all but I would
  like th have /games if possible."
- "When playing with filters the URL will change but will change to
  /games if all filters are selected, if possible."

**Sub-requirements:**

1. Collapse two filter rows into ONE compact row. DONE — wave 3
   `1350dbb` (spec 06); `Games::FilterRowComponent` rewritten.
2. Filter row sits between page title and first shelf. DONE — wave 3;
   `index.html.erb` line ordering reflects this.
3. "purchase" chip → renamed to `wishlist`. OVERRIDDEN — user
   confirmed via AskUserQuestion in earlier session ("purchase →
   wishlist"). Wave 3 ships `wishlist` chip; `Game.wishlist` scope
   aliases `Game.not_owned` (model line 320).
4. Left-side chips: `released, scheduled, owned, wishlist, played`.
   DONE — wave 3; `Games::FilterRowComponent` renders all five.
5. Right-side chips: `PS5, Switch2, Steam, GoG, Epic`. OVERRIDDEN —
   user confirmed in chat: GoG + Epic dropped; PC collapses to Steam
   only. Wave 3 + working tree ship `PS5, Switch2, Steam` (three
   platform chips). GoG / Epic data + filter + UI dropped per commit
   `1350dbb` message ("Steam/GoG/Epic → Steam, drop GoG/Epic data +
   filter + UI").
6. Drop Xbox. OVERRIDDEN — user confirmed; Xbox is the canonical
   drop already in spec 06 § scope-in, line 51. No chip rendered.
7. `Switch 2` vs `Switch2` naming check. DONE — `Switch2` (no space)
   per spec 06 § "PLATFORM_LABELS translation"; `Platform.display_label`
   exists in `app/models/platform.rb` line 79.
8. All chips default to CHECKED state. DONE — spec 06 § "URL
   canonicalization", wave 3 implementation: `/games` (no `?filters=`)
   ≡ all checked.
9. URL canonical: `/games` when all checked, otherwise
   `?filters=<csv>`. DONE — wave 3; `games_filter_controller.js`
   line 16–18 + 89 (`history.replaceState`); `games_path_with_checked`
   helper.
10. No page reload on chip toggle (Turbo Frame). DONE — wave 3;
    `index.html.erb` line 91 wraps the listing in `turbo_frame_tag
    "games_listing"`; controller line 16+ does `frame.src = url`.
11. No pagination on `/games`. DONE — spec 06 § "No pagination"; the
    controller never paginates and renders every matching game.

All sub-requirements landed (with explicit overrides for items 3, 5,
6 noted). No gaps.

---

## Item 10 — platform logo on tile footer (after year, dot-separator, Google favicon service)

**Brief excerpt:** "If you can, maybe use the Google fav icon service
or I'll search and give you the files, I want in the cover art for the
game listing, after the year, to add a separator (dot) and show the
platform logo for that specific game."

**Sub-requirements:**

1. Platform logo on tile footer. DONE — wave 1 (spec 07), then
   revised in working tree: logos moved from caption meta line to
   absolute-positioned overlay on the cover's bottom-right corner.
2. Google favicon service download. OVERRIDDEN — user supplied
   manual brand logos (the user said "If you can … OR I'll search and
   give you the files"; the implementation went with local source
   files under `lib/support/platforms/`). Rake task is
   `pito:platform_logos:download` per spec 07 but the actual rake
   (`pito_platform_logos.rake`) reads from local `lib/support/
   platforms/` files instead of fetching Google favicons. Outputs
   `<key>-<size>-{black,white}.png` (12 files total: 3 platforms × 2
   sizes × 2 color variants). **POSSIBLE-OVERRIDE** — was the switch
   to a local-source generator (instead of Google favicons) an
   explicit user-confirmed change, or just an implementation drift?
   Flag to clarify.
3. Separator dot between year and logo. OVERRIDDEN — working tree
   moves logos OUT of the caption meta row into the cover overlay,
   so the year-dot-logo arrangement is gone entirely; the meta row
   now shows only the release date in MM-DD-YYYY (the year alone is
   also gone — see item 10c below). **POSSIBLE-OVERRIDE** — the user
   asked for "dot, then logo" inline; the implementation chose a
   visually different overlay. Flag to confirm.
4. Show logo for THE platform. RESOLVED (user-confirmed 2026-05-17)
   — multi-logo on tile (availability) is correct; ownership chips
   on the detail page are also multi. Single chip is reserved ONLY
   for `played` + `recorded`. Spec 07 multi-logo evolution is locked.

GAP-or-OVERRIDE candidates flagged on sub-requirements 2, 3.

---

## Item 11 — filter cascade: `played` implies `released + owned + at least one platform`

**Brief excerpt:** "this has to be specced: if I check [x] played, then
this will imply [x] released [x] owned to be also checked and at least
one of the platform."

**Sub-requirements:**

1. Spec the cascade. DONE — spec 06 § "Filter cascade — played
   (CHECK-ONLY)" line 292.
2. Implement cascade in Stimulus controller. DONE — wave 3,
   `games_filter_controller.js` lines 55–62 implements the
   check-only `played` cascade.
3. Cascade is CHECK-only (not symmetric — un-checking `played` does
   NOT clear implied chips). DONE — wave 3 (spec 06 § "Filter
   cascade", controller line 11–12 confirms one-way).
4. When `played` checked AND zero platforms checked, force-check ALL
   platform chips. DONE — wave 3, controller line 56–62.

All sub-requirements landed. No gaps.

---

## Item 12 — sequential cover-art regen when adding games to a collection

**Brief excerpt:** "adding a game to a bundle (collection) the coverart
has to be regenerated, but if added multiple games to a collection, we
should be process the compound coverart considering the order the games
have beed added to the collection while sorting the games alphabetically.
So adding 3 games will trigger 3 regeneration cover art jobs and they
have to be executed in a clear order."

**Sub-requirements:**

1. Single add → ONE rebuild for that collection. DONE — wave 1 (spec
   02 § "Enqueue orderings"), `Collections::CompositeRebuildQueue
   .enqueue_for_collections([collection])`.
2. N games added to ONE collection in single user action → ONE
   rebuild (the membership write batches; one rebuild reads final
   state). DONE — spec 02 § Behavior "N games added to one
   collection" line 230; service confirms.
3. Multiple collections affected → alphabetical-by-name sequential
   chain (job `n+1` waits for job `n`). DONE — wave 1
   `composite_rebuild_queue.rb` `enqueue_chain` line 78–82 +
   `CollectionCoverRebuildJob` chain pattern.
4. Game re-sync triggers fan-out across every collection. DONE —
   wave 2 (spec 03), `GameIgdbSync` success path calls
   `enqueue_for_game_resync(game.reload)` line 86–87.
5. Game destroy triggers fan-out. DONE — wave 1 + model hook
   `after_destroy_commit :enqueue_collection_rebuilds_on_destroy`
   (game.rb line 526–527).

Note: brief says "3 games will trigger 3 regeneration cover art jobs."
The implementation collapses 3 single-collection-bulk-adds to ONE
job (the spec 02 § "N games added to one collection in a single user
action" decision). RESOLVED (user-confirmed 2026-05-17) — "if
batched is safe for order, OK; if not, serialize N sequential."
Investigation in flight to verify batched ordering matches the
intended final-state read; if verified, the batched one-rebuild
contract stands. Otherwise fall back to N sequential per-game
rebuilds.

No gaps.

---

## Item 13 — keep per-item resync on game / bundle pages

**Brief excerpt:** "It's ok to have resync on game and bundle at item
level in their page specifically."

**Sub-requirements:**

1. Per-game `[resync]` on game detail page. DONE — already present in
   pre-Phase-27 view; spec 08 will swap location into breadcrumb
   (SPEC LOCKED).
2. Per-bundle `[resync]` on bundle page. Not in spec 27 scope; existing
   per-bundle resync surface presumably stays. Not a gap (Phase 27
   doesn't touch bundle detail page).

No new gaps.

---

## Item 14 — drop game edit page entirely, replace `[-]` with delete confirm modal, delete cascades cover regen

**Brief excerpts:**

- "Moving to game page - no need for edit page. Remove it entirely."
- "[-] delete won't do bulk delete anymore but rather a modal
  confirmation with [delete](danger color we have or should have
  already a view component for this) and [cancel] (our viewcomponent
  for cancel dialog)."
- "deleting will trigger collection update cover art if case."

**Sub-requirements:**

1. Delete `app/views/games/edit.html.erb`. SPEC LOCKED — spec 08
   files-to-change line 160. File still present in working tree.
2. Delete `GamesController#edit` and `#update` actions. SPEC LOCKED —
   spec 08 files-to-change line 152–157. Both actions still present
   in controller.
3. `resources :games, except: [:edit, :update]` in routes. SPEC
   LOCKED — spec 08 files-to-change line 144. Current routes still
   declare full `resources :games`.
4. Replace breadcrumb `[edit]` with `[resync]`. SPEC LOCKED — spec
   08. Working tree show.html.erb line 38 still renders `[edit]`.
5. Replace breadcrumb `[-]` with `[delete]` confirm modal. SPEC
   LOCKED — spec 08. Working tree still renders `[-]` linking to
   `/deletions/game/:id`.
6. Delete confirm modal uses `ConfirmModalComponent` with `[delete]`
   (danger) + `[cancel]` (muted). SPEC LOCKED — spec 08 § "Per-game
   delete confirm modal".
7. Delete cascades collection cover regen. DONE — wave 1 + model
   hook (item 12 sub 5).

Items 1–6 are spec-locked, pending wave 4/5 dispatch. Item 7 done.

---

## Item 15 — ratings synthesized into one 0..100 score, displayed as heat bar; muted bar fallback

**Brief excerpt:** "ratings will be displayed here after dev: ... pub:
... as a hear bar using our colors that we have already for different
score and you should evaluate somehow objectively the igdb, aggregated,
total scores to produce only one scrore from 0 to 100. If you don't
have a score you'll have the heatbar viewcomponent as a muted bar."

**Sub-requirements:**

1. Heat bar component renders a 0..100 score as filled bar. SPEC
   LOCKED — spec 08 § "ViewComponents" + § "Ratings heat bar". Not
   yet implemented.
2. Score synthesis formula: vote-weighted average of igdb / aggregated
   / total. OVERRIDDEN (confirmed by user) — vote-weighted avg per
   spec 08 § "Rating heat-bar synthesis (LOCKED formula)" line 185–193.
3. Per-tier color (uses existing `Games::RatingBadgeComponent::TIERS`).
   SPEC LOCKED — spec 08.
4. Muted bar fallback when score nil. SPEC LOCKED — spec 08.
5. Bar placed under genres / dev / pub on LEFT pane (after `pub:`).
   SPEC LOCKED — spec 08 LEFT-pane order; brief says "after dev: pub:
   as a heat bar."

All 5 spec-locked. No gaps.

---

## Item 16 — right-pane: summary, hairline, time-to-beat 3-column table, hours rounded

**Brief excerpt:** "on the right hand side of the cover art column,
basically on the 2nd pane you start with summary. you follow with a
hairline. then you put time to beat as a 3 column table threated as
number (aligned right), round everything up to h(hour) - I don't care
about minutes."

**Sub-requirements:**

1. Right pane top: summary. SPEC LOCKED — spec 08 § "RIGHT pane
   content".
2. Hairline between summary and time-to-beat. SPEC LOCKED — spec 08.
3. Time-to-beat as a 3-COLUMN HORIZONTAL table (main / extras /
   completionist as columns). OVERRIDDEN — user RECONFIRMED 3-column
   in chat (per dispatch context). Spec 08 § "RIGHT pane Time-to-beat"
   line 318–333 + spec-coverage line 458–474 enforce 3 columns with
   header row + data row. NOT a vertical 2-column "label / value"
   stack.
4. Right-aligned values. SPEC LOCKED — spec 08 § "Time-to-beat"
   `text-align: right` rule.
5. Round to whole hours (`9h`, `14h`, `22h`). SPEC LOCKED — spec 08
   helper `ttb_hours(seconds)`.
6. Missing value renders `—`. SPEC LOCKED — spec 08.

All 6 spec-locked. No gaps.

---

## Item 17 — move genres to left-hand side between title and released, bold primary + normal secondary, cap at 3

**Brief excerpt:** "We move genres to the left hand side between game
title and released: and we do (bold) main genre, normal text other
genres if multiple, but limit to 3 or 4 or 5 genres in total. I trust
your judgement on this pick."

**Sub-requirements:**

1. Genres on LEFT pane between title and released. SPEC LOCKED — spec
   08 LEFT-pane content order line 36–43.
2. Bold primary genre, normal text secondary genres. SPEC LOCKED —
   spec 08 § "LEFT-pane sections / Genres" line 271–274.
3. Cap at 3 visible (1 primary + up to 2 secondaries). OVERRIDDEN —
   user confirmed in chat ("genre limit → 3"). Spec 08 line 38 +
   line 273 lock the cap at 3.

All 3 spec-locked, with user override on the cap. No gaps.

---

## Item 18 — platform logos at 4× tile size on LEFT pane, after genres; PC = Steam/GoG/Epic decomposed

**Brief excerpt:** "Also here after the genres, still on the left hand
side, we add the platforms logos that we also use on the /games, but a
bigger version, probably 4x of the /games version. Use same service and
approach. I care only about: PS5, Switch2, PC (and if possible instead
of PC use Steam, GoG, Epic, one or more if apply)."

**Sub-requirements:**

1. Platform logos on LEFT pane after genres. SPEC LOCKED — spec 08
   LEFT-pane content position 7 line 41.
2. 4× tile-version size (14 px tile → 56 px detail). DONE / SPEC
   LOCKED — current `show.html.erb` already renders `platform_logo_
   tag(slug, size: 64, display_size: 56)` per wave 2.
3. PS5, Switch2, PC. OVERRIDDEN — PC decomposed into Steam ONLY (GoG
   + Epic dropped per item 9 chat clarification). Working tree
   `platform_logos_helper.rb` `PC_STORE_IGDB_IDS` (6, 3, 14, 13, 92)
   collapse to single `steam` slug; Steam app id also infers Steam.
4. Decompose PC into Steam/GoG/Epic. OVERRIDDEN — GoG + Epic dropped
   per item 9 chat clarification; PC → Steam-only.

All 4 satisfied with user-confirmed overrides.

---

## Item 19 — ownership section: per-platform checkboxes for platforms / played / recorded / footage (TBD)

**Brief excerpt:** "Coming back to the left hand side, after a hairline
we have the section 'ownership' which will have:
platforms [ ] PS5 [ ] Switch2 [ ] Steam [ ] GoG [ ] Epic (show only
the ones that apply to the game and if you can't do PC details use PC
with Steam logo)
played [ ] PS5 ... can be the platforms from above that I have
ownership. I cant play on some platform that the game isn't released
for, or a platform I don't have the game.
recorded [ ] PS5 ... can be the platforms from above, the ones that I
played on. Can't be others.
footage - we leave this black for now with a status badge in bright
orange [TBD] - we'll search in the future once we reach the footage
rewamping."

**Sub-requirements:**

1. `platforms` row with one chip per APPLICABLE platform (intersected
   with the supported set). SPEC LOCKED — spec 08 § "Ownership
   chips" line 287–293. Show only ones in the 5-platform set ∩
   `platforms_available`; with GoG/Epic dropped per item 9 override,
   effectively PS5 / Switch2 / Steam chips.
2. Toggle ownership via existing `Games::PlatformOwnershipsController
   #update`. DONE — controller already exists (Phase 27 §01f); spec
   08 just rewires the click target. SPEC LOCKED for the wiring.
3. `played` section is **per-platform** (one chip per owned
   platform). RESOLVED (user-confirmed 2026-05-17) — SINGLE CHIP. No
   per-platform breakdown for `played`. Spec 08 § "Ownership chips"
   single `[x] played` shape stands.
4. `recorded` section is **per-platform** (one chip per platform the
   user played on). RESOLVED (user-confirmed 2026-05-17) — SINGLE
   CHIP. No per-platform breakdown for `recorded`. Spec 08 § "Ownership
   chips" single `[x] recorded` shape stands.
5. `played` chips constrained to platforms the user owns. RESOLVED
   (user-confirmed 2026-05-17) — moot: per-platform deferred (see
   19.3), so the cascade constraint does not apply.
6. `recorded` chips constrained to platforms the user has played on.
   RESOLVED (user-confirmed 2026-05-17) — moot: per-platform deferred
   (see 19.4), so the cascade constraint does not apply.
7. `footage` row with `[TBD]` bright-orange status badge. SPEC
   LOCKED — spec 08 § "Ownership chips" line 301–304 +
   `StatusTbdBadgeComponent`.

No gaps.

---

## Item 20 — `[resync]` in breadcrumb replacing `[edit]`, with sync lock + ActionCable update like Voyage

**Brief excerpt:** "we add [resync] link in the breadcrumb instead of
the current [edit] link; we need the sync lock mechanism and the link
has to be mutted while the sync in in place like we have with the
Voyage sync lock and we update the page with the same mechanism
ActionCable websocket as /settings and Voyage."

**Sub-requirements:**

1. Breadcrumb `[edit]` → `[resync]`. SPEC LOCKED — spec 08 §
   "Breadcrumb actions" line 88, 336–337. Working tree still shows
   `[edit]`.
2. Sync lock mechanism (DB mutex + Sidekiq uniqueness). DONE — wave
   2 (spec 03); `games.resyncing` Boolean + `sidekiq_options lock:
   :until_executed, on_conflict: :log`.
3. Muted styling while sync in flight. SPEC LOCKED — spec 08 §
   "Breadcrumb actions" line 338–339 ("Renders muted via
   `BracketedMutedLinkComponent` while `@game.resyncing?` is true").
4. ActionCable / Turbo Stream broadcast like Voyage. DONE — wave 2
   (spec 03); `GameIgdbSync#broadcast_resync_state` line 113–125
   matches `ReindexAllJob#broadcast_voyage_section` pattern.

Sub 1 + 3 are spec-locked (pending wave 4/5 dispatch); sub 2 + 4 done.

---

## Item 21 — sync state copy on LEFT pane after heat bar, with hairline; `=---` indicator while syncing

**Brief excerpt:** "On the left hand side, after the heatscore bar (or
what the last thing was there), we add a hairline and we put the sync
copy: syncced ~22m ago. We use our format, the short one. When
resynccing (because of clicking the top breadcrumb link) we replace
~22m ago with our =--- indicator which will be updated once the sync
is done."

**Sub-requirements:**

1. Sync banner placed on LEFT pane after heat bar with hairline above.
   SPEC LOCKED — spec 08 LEFT-pane content position 12–13 line 65–69.
2. Copy reads `synced ~22m ago` in short relative-time format. SPEC
   LOCKED — spec 08 helper `short_synced_ago(timestamp)` line 245–248.
3. `=---` dot-loader while syncing. DONE — wave 2 (spec 03);
   `_sync_status.html.erb` renders the indicator.
4. Live ActionCable replace as sync completes. DONE — wave 2 (spec
   03) broadcast.

Sub 1 + 2 spec-locked; sub 3 + 4 done.

---

## Item 22 — sync overrides IGDB-sourced fields, preserves ownership; if in bundle, regen cover

**Brief excerpt:** "The sync is overriding the current info for the
fields that are coming from igdb, without touching the ownership
fields. If the game is in a bundle / collection the coverart for that
bundle has to be regenerated."

**Sub-requirements:**

1. IGDB-sourced fields overwritten last-write-wins. DONE — wave 2
   (spec 03 § "Field partition (LOCKED)" line 138–157); `Igdb::SyncGame
   #call` only writes IGDB columns.
2. Ownership-sourced fields preserved. DONE — wave 2 (spec 03 § same
   section, line 159–172).
3. Field-partition is documented in model docstring. DONE — `Game`
   model lines 4–60 carry the partition documentation.
4. Bundle/collection cover regenerated after sync. DONE — wave 2
   (spec 03); `GameIgdbSync` success path enqueues
   `Collections::CompositeRebuildQueue.enqueue_for_game_resync`.

Note: the brief says "bundle / collection"; the implementation triggers
the regen for the collection the game is in. RESOLVED (user-confirmed
2026-05-17) — "bundle, collection, series — same concept, call it
bundle from now on." Bundles and collections are the SAME concept;
naming will converge on `bundle`. Investigation in flight to determine
code-side naming (which model survives, which is dropped/renamed). The
existing collection-cover regen hook satisfies the brief's "bundle /
collection" requirement once the naming converges.

No gaps.

---

## Item 23 — implement the sync job, spec it

**Brief excerpt:** "The sync job has to be implemented now and specced."

**Sub-requirements:**

1. Sync job implemented as Sidekiq job. DONE — wave 2 (spec 03);
   `GameIgdbSync` job hardened with 3-layer lock pattern, live
   broadcast, collection fan-out.
2. Job specced. DONE — wave 2; `spec/jobs/game_igdb_sync_spec.rb`
   covers happy / sad / edge / flaw per spec 03 spec-coverage.
3. Class name: `GameResyncJob` (per brief) vs `GameIgdbSync` (per
   implementation). OVERRIDDEN — user CONFIRMED in chat: keep
   `GameIgdbSync` name (no rename). Spec 03 § Scope-in line 32–37
   architect lean "harden in place" — locked.

All 3 satisfied.

---

## Item 24 — `linked videos` → `videos`, empty state shows `[TBD]` orange badge

**Brief excerpt:** "linked videos -> videos - shorter copy and replace
the current copy 'no linked videos yet' with status badge orange
bright, that should be a component by now [TBD] so we can revisit later."

**Sub-requirements:**

1. Heading rename `linked videos` → `videos`. SPEC LOCKED — spec 08 §
   "Linked videos section heading" line 118 + § "videos section" line
   361–367. Working tree show.html.erb line 271 still reads `linked
   videos`.
2. Empty state shows `[TBD]` orange badge instead of `no linked
   videos yet.`. SPEC LOCKED — spec 08 § "videos section" line 364–
   367 + `StatusTbdBadgeComponent`. Working tree line 286 still
   shows `no linked videos yet.`.

Both spec-locked, pending wave 4/5 dispatch.

---

## Item 25 — keybindings reference: new "page actions" section with `/ search`, `s sync`, `- delete`

**Brief excerpt:** "We add a new thing in the keybindings that is
separated by the current navigation by a hairline and I think this new
section should be the first one but I'm opened to suggestions to switch
placement with the navigation. This new section is about actions on
this page. In this section we move / search to it and it will be like
now (we'll revisit later) and we continue with s sync that will trigger
the sync on this page for this game and - delete that will pop up the
modal."

**Sub-requirements:**

1. New "page actions" section in keybindings reference. SPEC LOCKED —
   spec 09 § "Two-section UI" + `page_actions:` YAML key.
2. Section is separated from navigation by a hairline. SPEC LOCKED —
   spec 09 § Behavior "Component empty-case handling" + `<section>`
   structure.
3. **Page actions render FIRST** (before navigation). RESOLVED
   (user-confirmed 2026-05-17) — page actions FIRST, hairline, then
   general navigation. Spec 09 will lock this and add a YAML anchor
   for the shared navigation section.
4. `/` search (placeholder modal). SPEC LOCKED — spec 09 § "`/`
   (search) placeholder modal" + `SearchPlaceholderModalComponent`
   wired with `[TBD]` badge.
5. `s` sync triggers per-page sync. SPEC LOCKED — spec 09 § "Per-page
   contracts" + `page_sync` action handler.
6. `-` delete opens the confirm modal (from item 14). SPEC LOCKED —
   spec 09 § "Per-page contracts" + `page_delete` action handler.

All 6 spec-locked; sub-requirement 3 RESOLVED (user-confirmed
2026-05-17) — spec 09 to lock "page actions FIRST" + add YAML anchor
for shared navigation before wave 4/5 dispatch.

---

## Summary

### Classification totals

| Classification          | Count |
| ----------------------- | ----: |
| DONE                    |    47 |
| IN FLIGHT (uncommitted) |     6 (tile overlay, cover_component turbo-frame, letter shelves rich tile, helper PC collapse, css overlay, show.html.erb comment) |
| SPEC LOCKED             |    33 |
| OVERRIDDEN (confirmed)  |    11 |
| RESOLVED (user-confirmed 2026-05-17) | 8 (items 6.9, 10.4, 12, 19.3, 19.4, 19.5, 19.6, 22, 25.3 — counted as a block of 9 sub-reqs across 6 brief items: 6.9, 10.4, 12, 19.3–19.6, 22, 25.3) |
| GAP / POSSIBLE-OVERRIDE |     2 (items 10.2, 10.3 — both on the tile platform-logo working-tree layout) |
| PENDING DISPATCH        |     2 (items 14, 24 — SPEC LOCKED but not yet shipped) |

Approx. 108 sub-requirements identified across the 25 items.

### GAPS and POSSIBLE-OVERRIDES (priority order, most critical first)

1. **Item 10.3 — separator dot between year and logo.** Brief asks
   for inline `year · logo` in the meta row. Working tree moves
   logos OUT of the meta row entirely (overlay on cover) and replaces
   the year-only fallback with full release date (MM-DD-YYYY). The
   `·` separator no longer exists because the logos don't sit on the
   meta line. POSSIBLE-OVERRIDE — confirm the new layout matches
   user intent.

2. **Item 10.2 — Google favicon service vs local-source rake.** Brief
   suggested Google favicon service (or user-supplied files).
   Implementation went with local-source `lib/support/platforms/`
   files (user manually placed files) + B/W color variants. Plausibly
   matches the "I'll search and give you the files" branch of the
   brief, but spec 07 still names the rake task `pito:platform_logos
   :download` which connotes downloading from Google. POSSIBLE-
   OVERRIDE.

3. **Item 14 — entire game edit-page removal not yet shipped.** Six
   sub-requirements all SPEC LOCKED but pending wave 4/5 dispatch.
   Not a gap, but a blocker for the user-visible cleanup.

4. **Item 24 — `linked videos` → `videos` + `[TBD]` badge** — SPEC
   LOCKED but not yet shipped. Same pending-dispatch pattern.

### RESOLVED (user-confirmed 2026-05-17)

The following high-priority gap items were resolved in the user's
2026-05-17 decisions:

- **Item 6.9 — cover sizes** — 3 sizes total: small (genre/bundle
  composite), medium (game shelf), large (detail page). Spec 08 will
  lock the 3rd size for the detail page.
- **Item 10.4 — multi-logo on tile + ownership chips** — multi
  confirmed for tile availability + detail-page ownership; single
  chip reserved ONLY for `played` + `recorded`.
- **Item 12 — bulk-add cover regen** — batched one-rebuild is
  acceptable IF the batched ordering is safe; otherwise serialize N
  sequential. Investigation in flight to verify.
- **Item 19.3 + 19.4 — per-platform played/recorded** — SINGLE CHIP
  confirmed for both `played` and `recorded`; no per-platform
  breakdown. Spec 08 stands.
- **Item 19.5 + 19.6 — played/recorded cascade constraints** — moot
  after 19.3 / 19.4 resolution.
- **Item 22 — bundle vs collection regen** — bundle = collection =
  series (same concept; will be called `bundle` going forward).
  Investigation in flight to determine code-side naming convergence.
- **Item 25.3 — page actions FIRST** — page actions render first,
  hairline, then general navigation. Spec 09 to lock + add YAML
  anchor for shared navigation.
