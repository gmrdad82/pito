# Manual test playbook — Phase 14 Specs 02 + 03 (bundles, composite covers, Steam-shelf, video↔game links, MCP tools)

**Branch:** `main` **Specs:**

- `docs/plans/beta/14-game-model-igdb-sync/specs/02-bundles-and-composite-covers.md`
- `docs/plans/beta/14-game-model-igdb-sync/specs/03-steam-shelf-ui-and-video-game-links.md`

**Reviewer run:** 2026-05-10 18:55

## Pipeline summary

- Code review: pass with 6 non-blocking concerns (C1-C6).
- Simplify: pass with 3 suggestions (S1-S3).
- Test suite (focused Phase 14 §2/§3 slice — models, services, jobs, requests,
  MCP tools, system specs): 354 examples, 0 failures.
- Test suite (full): 3669 examples, 4 failures, 1 pending. All 4 failures
  reproduce green when re-run individually (test-isolation flakes; not Phase 14
  regressions). 2 of the 4 are known and called out in the Spec 03
  implementation log; 2 belong to Phase 16 webhook-allowlist specs.
- Rubocop (touched files — 66 files): clean.
- Brakeman (`bundle exec brakeman -q -w2`): 0 errors, 0 security warnings.
- Bundler-audit (`bundle exec bundler-audit check --update`): no
  vulnerabilities.
- Tenant-residue scan (`git grep 'tenant\|Tenant'` over Phase 14 §2/§3 files):
  zero matches.
- Yes/no boundary scan over MCP tool surface: every write tool gates on
  `Scopes::APP`, validates `confirm` and `is_primary` against `YesNo.yes_no?`,
  and rejects boolean / integer smuggling.
- Spec count delta vs implementation log claim (16 spec'd MCP tools + 1 bonus
  `igdb_search` = 17): verified — 17 tool files, 17 spec files.

## Blockers

None. Both specs land cleanly. The non-blocking concerns below should be queued
(most are operational hardening worth doing before Phase 13 starts hammering the
IGDB CDN / link tables at analytics scale).

## Concerns and suggestions

### C1. `Composite::TileCache#download` has no HTTP timeouts (MEDIUM)

`app/services/composite/tile_cache.rb:47` uses `Net::HTTP.get_response(uri)`
with the gem default timeouts (60s open, 60s read). A hung IGDB CDN response
stalls a Sidekiq worker for a full minute per retry × `BundleCoverBuild`'s
`retry: 5` — worst case, 5 min per bundle build job under CDN flake. Recommend
`http.open_timeout = 5; http.read_timeout = 10; http.write_timeout = 5` on a
`Net::HTTP.start` block, mirroring the Phase 16 F2 fix. Same shape recurs in
`app/services/igdb/client.rb:216` (`Net::HTTP.post`); both are operational
hardening, not security.

### C2. `Igdb::Client.perform_request` + `.post` shares the timeout gap (MEDIUM)

Same root cause as C1. Tracked separately because Phase 14 §1 was already
reviewed; the issue persists across Spec 02/03 because they call
`Igdb::Client.search_games` / `fetch_games_for_*` from the new MCP tools and
`BundlesController#seed_from_igdb`. Fix once at the client level and both
surfaces benefit.

### C3. Picker hard limit at 500 entries silently truncates (LOW)

`VideosController#load_edit_form_locals` (line 246-247) does
`Game.order(:title).limit(500)` and `Bundle.order(:name).limit(500)`. Once a
user crosses 500 games or 500 bundles, items beyond the alphabetic 500th become
unreachable from the link picker. The `link-picker` Stimulus controller also
iterates every option (`optionTargets.forEach`) on every keystroke — at 500
entries this is ~1ms, fine; at 5000 it becomes laggy. For v1 fine; for Phase 13
/ multi-user installs queue a follow-up to either paginate the picker or wire it
to a server-side search.

### C4. `bundles/_tile.html.erb` triggers a per-tile `bundle_members.size` query (LOW, N+1)

`app/views/bundles/_tile.html.erb:9`. The bundles shelf on `/games` fetches up
to 10 bundles; the bundles index has no limit. Each tile fires a count query for
member count. Recommend `bundle_members.size` →
`bundle_members.loaded? ? bundle_members.size : bundle_members.count` in the
worst case, or precompute via
`Bundle.left_joins(:bundle_members).group("bundles.id").select("bundles.*, COUNT(bundle_members.id) AS members_count")`
in `BundlesController#index` and `GamesController#index`. Cheap fix; defer if
`/bundles` stays small.

### C5. `Bundle#enqueue_cover_build_if_changed` enqueues on every save (LOW)

`app/models/bundle.rb:115-119`. The condition
`saved_change_to_id? || needs_cover_rebuild?` enqueues a build on every new
bundle (correct) and on every save where the checksum drifts (correct). However,
`needs_cover_rebuild?` issues `bundle_members.size` +
`bundle_members.includes(:game).map(&:game)` queries every time the bundle is
saved (e.g., a `name` rename triggers `after_save` → 2-3 queries to confirm "no,
no rebuild needed"). For low edit volume fine; at scale add a memoized
`@checksum_inputs_for_save` or guard on `saved_change_to_composite_cover_path?`
or `previous_changes`. Note this also masks one concrete edge case: editing a
name on a 0-member bundle would `enqueue_cover_build_if_changed` →
`needs_cover_rebuild?` returns `false`, no enqueue. Verify no test relies on
that.

### C6. `Composite::Builder#call` write isn't atomic (LOW)

`app/services/composite/builder.rb:48`: `composite.jpegsave(path.to_s, ...)`
writes to the destination directly. A crash mid-write leaves a corrupt JPEG that
the auth-gated `/composites/:filename.jpg` endpoint will happily serve.
Recommend `composite.jpegsave("#{path}.tmp", ...)` followed by
`File.rename("#{path}.tmp", path.to_s)`. Defense-in-depth; today libvips is
reasonably crash-safe internally.

### S1. `Bundle#sweep_composite_cover_file` and `BundleCoverBuild` race on destroy (informational)

`Bundle#before_destroy` deletes the on-disk JPEG. If a `BundleCoverBuild` job is
in flight at the time of destroy, the job's `Bundle.find_by(id: bundle_id)`
returns nil and the job exits cleanly — but if the FIND happens before the
DELETE commits, the job will rebuild the JPEG that the destroy then tries to
delete. The job's `update!` would then 422 on the deleted bundle. Today
`Composite::Builder#call` uses `update!` on the bundle; a deleted-bundle save
will raise. This is caught by `BundleCoverBuild`'s `rescue StandardError` block
but the file would remain orphan (the rake task `pito:bundles:reap_orphans`
handles this case explicitly per the Spec 02 implementation log). Worth noting
as an operational quirk; reap_orphans covers it.

### S2. `link.target` returns `nil` when both `game_id` and `bundle_id` are nil (informational)

`app/models/video_game_link.rb:39-41`: `link_game? ? game : bundle`. If a row
somehow has `link_type=:game` but `game_id=nil` (only possible via raw-SQL
bypass — the DB CHECK constraint forbids it), `target` returns `nil` and
`_link_row.html.erb:14-21` falls through to the `target_label = "—"` branch.
Correct fallback; flagged so future readers know it's intentional.

### S3. `composite_cover_url` skips a leading-slash sanity check (informational)

`app/models/bundle.rb:53-56` returns `/composites/#{File.basename(...)}` which
is correct as long as `composite_cover_path` is a relative path under
`composites/`. The path is stamped by `Composite::Builder#call` via
`path.relative_path_from(Pito::AssetsRoot.root).to_s` so it's always shaped
correctly. The auth-gated `CompositesController#show` also validates the
basename against `FILENAME_REGEX` (`/\A[a-z_]+-\d+\z/`). Defense-in-depth is in
place; flagged so future readers don't worry.

## Manual test steps

### Setup preamble

1. **Pull and migrate.**
   - **Action:** `git pull --rebase` then `bin/rails db:migrate`.
   - **Expected:** Migrations `20260510160000_create_bundles` and
     `20260510180000_create_video_game_links` run cleanly.
2. **Confirm IGDB credentials.**
   - **Action:** `bin/rails credentials:edit --environment development` and
     verify the `igdb:` block is set per Spec 01 manual playbook.
   - **Expected:** `client_id` and `client_secret` present.
3. **Boot dev.**
   - **Action:** `bin/dev` in one terminal.
   - **Expected:** Web Puma + Sidekiq + Tailwind watcher all green.
4. **Seed test data via the Spec 01 IGDB add flow.**
   - **Action:** Visit `/games`. Use the `[search igdb]` box at the top to add
     at least 5 games (varying genres / platforms — pick ones with cover art).
     For each, click `[add]` from the search dropdown. Wait ~3-5s per game for
     `GameIgdbSync` to hydrate.
   - **Expected:** 5 game tiles render in the `all games` grid with covers,
     release years, and ratings.
5. **Mark a couple as recently played.**
   - **Action:** On 2-3 game show pages, set `played on` to a recent date and
     click `[update]`.
   - **Expected:** Form succeeds; field persists.
6. **Run focused suites.**
   - **Action:**
     ```
     bundle exec rspec \
       spec/models/bundle_spec.rb \
       spec/models/bundle_member_spec.rb \
       spec/models/video_game_link_spec.rb \
       spec/services/composite/ \
       spec/jobs/bundle_cover_build_spec.rb \
       spec/jobs/bundle_cover_invalidate_spec.rb \
       spec/requests/bundles_spec.rb \
       spec/requests/bundle_members_spec.rb \
       spec/requests/composites_spec.rb \
       spec/requests/video_game_links_spec.rb \
       spec/requests/games_spec.rb \
       spec/system/bundle_show_spec.rb \
       spec/system/games_steam_shelf_spec.rb \
       spec/system/video_link_picker_spec.rb \
       spec/mcp/tools/{bundle_,game_,igdb_search,video_link_,video_unlink}*
     ```
   - **Expected:** 354 examples, 0 failures.
7. **Run full suite.**
   - **Action:** `bundle exec rspec`.
   - **Expected:** 3669 examples, 4 failures (test-isolation flakes — each
     passes when re-run individually), 1 pending. None are Phase 14 regressions.
8. **Run quality gates.**
   - **Action:** `bundle exec rubocop` (touched files),
     `bundle exec brakeman -q -w2`, `bundle exec bundler-audit check --update`.
   - **Expected:** All green / zero new findings.
9. **Tenant residue scan.**
   - **Action:**
     `git grep -nE 'tenant|Tenant' app/models/bundle*.rb app/models/video_game_link.rb app/services/composite/ app/jobs/bundle_cover_*.rb app/mcp/tools/{bundle_,game_,video_link_,video_unlink,igdb_search}*`.
   - **Expected:** Zero matches.

### Spec 02 — bundles + composite covers

10. **Verify on-disk composites root resolves.**
    - **Action:**
      `bin/rails runner 'puts Pito::AssetsRoot.path("composites").to_s'`.
    - **Expected:** Absolute path under `<PITO_ASSETS_PATH>/composites`.
11. **Migrate verification.**
    - **Action:**
      `bin/rails runner 'puts ActiveRecord::Base.connection.tables.grep(/bundle/i)'`.
    - **Expected:** `bundles` and `bundle_members` listed.
12. **Bundle CRUD smoke (custom).**
    - **Action:** Through the UI, create a `custom` bundle named "Soulslikes".
      Add 3 game members from the picker.
    - **Expected:** 3 BundleMember rows; cover build enqueued (visible in
      `/sidekiq/queues/default`); within ~3-5s the composite cover renders
      600×800 with the Netflix layout.
    - **Verify on disk:**
      ```
      ls $PITO_ASSETS_PATH/composites/
      ls $PITO_ASSETS_PATH/composites/_tiles/
      ```
      One `custom-<id>.jpg` plus 3 cover_image_id-keyed tiles.
13. **Layout transitions.**
    - **Action:** Add a 4th game; observe the cover regenerates with the Quad
      layout. Remove the first; observe Netflix returns. Add 6 more games (10
      total); observe NineGridWithOverflow with "+2" caption on the bottom-right
      tile.
14. **Idempotent rebuild.**
    - **Action:** From `bin/rails console`:
      `BundleCoverBuild.new.perform(<bundle_id>)` twice.
    - **Expected:** Same `composite_cover_checksum` after both runs; file mtime
      updates but byte-identical.
15. **Game cover change → bundle cover regen.**
    - **Action:** Manually flip a member game's `cover_image_id`:
      `Game.find(<id>).update!(cover_image_id: "co1xyz")`.
    - **Expected:** `BundleCoverInvalidate` enqueues, evicts the old tile, then
      enqueues `BundleCoverBuild` for every bundle the game belongs to.
16. **IGDB-seeded path.**
    - **Action:** Create a `series` bundle with `igdb_source_type: franchise`,
      `igdb_source_id` from a real IGDB franchise (try `1` for "Mario"). Click
      `[ seed from igdb ]`.
    - **Expected:** Members populate; missing local Game rows are created and
      queued for hydration; existing rows untouched; flash reports the count.
17. **Bundle delete sweep.**
    - **Action:** Delete a bundle (click `[ - ]`, confirm via the action
      screen).
    - **Expected:** `bundles`, `bundle_members` rows gone; on-disk
      `<type>-<id>.jpg` deleted.
18. **Reap-orphans rake.**
    - **Action:** `bin/rails pito:bundles:reap_orphans`.
    - **Expected:** Reports `reaped 0` on a healthy install.
19. **`/composites/:filename.jpg` is auth-gated.**
    - **Action:** Log out (or open a private window). Navigate to
      `/composites/<existing>.jpg`.
    - **Expected:** Redirect to `/login` (NOT a 200 image).

### Spec 03 — Steam-shelf + video↔game/bundle links + MCP tools

20. **Visit `/games` index.**
    - **Action:** Open `/games`.
    - **Expected (with populated library + ≥1 bundle):** bundles shelf at top,
      then `recently played`, then per-genre shelves (alphabetical by genre
      name, capped at 8), then per-platform shelves, then the `all games` grid.
      `[see all]` per shelf where a filter route applies. Mouse-wheel scroll on
      a shelf scrolls horizontally; click-and-drag also scrolls.
21. **`[see all]` filter routes.**
    - **Action:** Click `[see all]` on a per-genre shelf.
    - **Expected:** URL becomes `/games?genre=<id>`; the all-games grid filters
      to that genre. Repeat for a platform shelf → `/games?platform_owned=<id>`.
22. **Filter route smuggle guard.**
    - **Action:** Visit `/games?genre=evil`, then `/games?platform_owned=-1`.
    - **Expected:** No filter applied (silently dropped); page renders all
      games.
23. **Visit `/bundles` index.**
    - **Action:** Open `/bundles`.
    - **Expected:** Flat tile grid (NOT a table). Composite covers render.
      Bundle name + member count below each. Empty bundles show the `—` em-dash
      placeholder.
24. **Add a video↔game link via the edit form.**
    - **Action:** Open `/videos/:id/edit` for any video. Scroll to "linked games
      / bundles" fieldset. Type a game name; click the `[game] <title>` row.
    - **Expected:** Page reloads with a new link row in the table; flash
      `link added.` (or similar).
25. **Toggle `is_primary`.**
    - **Action:** On the link row, click the `[ ]` (or `[★]`) toggle.
    - **Expected:** Badge flips; flash `link updated.`.
26. **Add a video↔bundle link.**
    - **Action:** From the same picker, click a `[bundle] <name>` row.
    - **Expected:** Both kinds coexist in the fieldset.
27. **Duplicate-link UX.**
    - **Action:** Try adding the same game / bundle a second time.
    - **Expected:** Flash `already linked.` (NOT a 500).
28. **Remove a link via action-screen.**
    - **Action:** Click `[remove]` on a link row.
    - **Expected:** Routes to `/deletions/video_game_link/<id>` action-screen
      page. Submit "yes" → link gone.
29. **`Game#hours_of_footage_cached` recompute.**
    - **Action:** Pick a video with `duration_seconds` set (e.g. 7200). Link it
      to a game (primary or not). Open the linked game's show page.
    - **Expected:** `hours_of_footage_cached` reflects the rounded sum (7200 /
      3600 = 2). Unlink → recomputed back down.
30. **Multi-user remove (per ADR 0003).**
    - **Action:** As User A, create a link. Log out. Log in as User B (use the
      secondary seeded user from Phase 8 reseed, or create one). Open the same
      video edit page; click `[remove]` on User A's link.
    - **Expected:** Removal succeeds; per ADR 0003 anyone signed in has full
      access (no per-user permissions).
31. **MCP smoke — `game_search` / `igdb_search`.**
    - **Action:** From Claude Mobile or curl against the MCP HTTP surface (see
      `bin/mcp-web`):
      ```
      game_search { q: "zelda" }
      igdb_search { q: "Hollow Knight Silksong" }
      ```
    - **Expected:** Both return hit lists; `igdb_search` returns IGDB ids.
32. **MCP smoke — write tools confirm flow.**
    - **Action:** Run each twice, once with `confirm: "no"`, once with
      `confirm: "yes"`:
      ```
      game_add_from_igdb { igdb_id: 7346 }
      bundle_create { name: "Smoke", bundle_type: "custom" }
      bundle_member_add { bundle_id: <id>, game_id: <id> }
      video_link_game { video_id: <id>, game_id: <id> }
      video_link_set_primary { id: <link_id>, is_primary: "yes" }
      video_unlink { ids: [<link_id>] }
      bundle_destroy { id: <bundle_id> }
      game_destroy { id: <game_id> }
      ```
    - **Expected:** `confirm: "no"` returns a preview payload; `confirm: "yes"`
      performs the action. Boolean / integer smuggling (`confirm: true`,
      `is_primary: 1`) returns 422 with a clear "use 'yes' or 'no'" message.
33. **MCP scope gate.**
    - **Action:** Hit any of the 17 new tools with a token missing the `app`
      scope.
    - **Expected:** 401-equivalent error from `Mcp::ToolAuth.require_scope!`.

## Cleanup

```bash
# Roll back local state if you want a clean retry
bin/rails db:rollback STEP=2          # undo Spec 02 + 03 migrations
rm -rf $PITO_ASSETS_PATH/composites/  # purge built composites + tile cache
git checkout -- .                     # only if you accidentally edited files
```

For a full reset:

```bash
bin/rails db:reset
bin/rails db:seed
```

## User Validation

[ ] 1. **Bundles index empty state.** With no bundles created, visit `/bundles`.
Confirm the page shows `no bundles yet. [ add bundle ] to create one.` and the
`[add bundle]` link in the header.

[ ] 2. **Create a bundle.** Click `[add bundle]`. Pick
`bundle_type:        custom`, name "Soulslikes". Submit. Confirm redirect to the
bundle show page with `[no cover]` placeholder (no members yet).

[ ] 3. **Add three members.** On the bundle show page, type into the picker.
Click each member's `[add]` button. Confirm a member row appears per add, the
picker clears, and within ~3-5s the composite cover image renders. Confirm the
layout transitions (1 → Single → 2 → Pair → 3 → Netflix). Hard-refresh once to
confirm the cover persists.

[ ] 4. **Add a fourth member; confirm Quad layout.** Add one more game. Confirm
the cover regenerates with a 2×2 grid.

[ ] 5. **Remove a member; confirm regen back to Netflix.** Click `[remove]` next
to a row. Confirm the action-screen renders. Submit. Confirm the row disappears
and the cover regenerates within ~3-5s with the Netflix layout.

[ ] 6. **IGDB-seeded bundle.** Click `[add bundle]` again. Pick
`bundle_type: series`. Set `igdb_source_type: franchise` and `igdb_source_id` to
a real IGDB franchise ID. Save. On the show page click `[seed from igdb]`.
Confirm members populate and the cover builds.

[ ] 7. **Last-error inline copy.** Force a bad seed: edit the bundle in the
console (`Bundle.last.update_columns(igdb_source_id: 999999999)`) then click
`[seed from igdb]`. Confirm the show page surfaces a red "couldn't build cover;
will retry on next change." paragraph with the underlying error in muted text.

[ ] 8. **Bundle delete via action-screen.** Click `[ - ]` on the Soulslikes
bundle. Confirm the action-screen page appears (NOT a JS confirm dialog). Submit
"yes". Confirm the bundle and members are gone. Refresh `/bundles` to confirm
absence.

[ ] 9. **Auth-gated composite cover.** Open a private/incognito window and paste
an existing `/composites/<filename>.jpg` URL. Confirm the browser redirects to
`/login` (not a raw image).

[ ] 10. **Steam-shelf shape on `/games`.** With ≥1 bundle and ≥3 games visible,
open `/games`. Confirm the order top to bottom: `bundles` shelf,
`recently played` shelf, per-genre shelves, per-platform shelves, `all games`
grid.

[ ] 11. **Mouse-wheel horizontal scroll.** Hover a shelf with more tiles than
fit on screen. Spin the mouse wheel vertically. Confirm the shelf scrolls
horizontally (not the page).

[ ] 12. **Click-and-drag scroll.** Click and hold inside a shelf row and drag
left/right. Confirm the shelf follows the drag.

[ ] 13. **Tile hover caption.** Hover a game tile. Confirm the browser title
attribute (or visible caption) shows `Title (year) ★ rating`.

[ ] 14. **`[see all]` filter route — genre.** Click `[see all]` on a per-genre
shelf. Confirm the URL becomes `/games?genre=<id>` and the all-games grid
filters to just that genre's games.

[ ] 15. **`[see all]` filter route — platform.** Repeat on a per-platform shelf.
Confirm `/games?platform_owned=<id>`.

[ ] 16. **Filter smuggle guard.** Manually navigate to `/games?genre=evil`.
Confirm no error and no filter applied (page shows all games).

[ ] 17. **Bundles flat grid.** Open `/bundles`. Confirm a flat wrapping tile
grid (NOT a table) with composite covers, names and member counts.

[ ] 18. **Linked-games fieldset on video edit.** Open `/videos/:id/edit` for a
video. Scroll to the "linked games / bundles" fieldset. Confirm picker, no-links
empty state.

[ ] 19. **Add a game link via the picker.** Type a game name in the picker.
Click the `[game] <title>` row. Confirm a new link row appears above with
kind=game.

[ ] 20. **Toggle primary star.** Click the `[ ]` cell on a link row. Confirm it
flips to `[★]`. Click again; confirms it flips back. Reload to confirm
persistence.

[ ] 21. **Add a bundle link via the picker.** Type a bundle name in the picker.
Click the `[bundle] <name>` row. Confirm both link kinds coexist in the table.

[ ] 22. **Duplicate-link UX.** Try adding the same game a second time. Confirm
the page shows `already linked.` flash (NOT a crash).

[ ] 23. **Remove a link.** Click `[remove]` on a link row. Confirm the
action-screen page renders. Submit "yes". Confirm the link row is gone.

[ ] 24. **Game show "linked videos".** Open `/games/:id` for a game you linked a
video to. Confirm the "linked videos" section lists the video; if the link is
primary, confirm `[★]` next to the title.

[ ] 25. **Bundle show "linked videos".** Open `/bundles/:id` for a bundle you
linked a video to. Confirm the same shape.

[ ] 26. **Hours-of-footage cache.** On a linked game's show page, confirm the
local-fields panel reflects the cached footage hours (rounded). Add another
linked video; refresh; confirm the number increases. Unlink one; refresh;
confirm decrease.

[ ] 27. **Empty `/games` copy carries through.** With NO games (in a fresh DB),
visit `/games`. Confirm `no games yet.` empty-state copy renders above the
`[search igdb]` add form (per Spec 01 carry-through).

[ ] 28. **Empty bundles fallback in tile.** Create a bundle with NO members.
From `/bundles` confirm the tile shows the `—` em-dash fallback in place of a
composite cover.

[ ] 29. **No JS confirms anywhere in the new surface.** Click every destructive
action you can find (`[remove]`, bundle `[ - ]`). Confirm none trigger a JS
`confirm()` / `alert()` / `prompt()` dialog. All destructive flows route through
the shared action-screen page.
