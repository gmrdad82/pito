# Manual test playbook — Phase 14 §1: Game data model + IGDB v4 client

**Branch:** `main` (commit `4b2be96`) **Spec:**
`docs/plans/beta/14-game-model-igdb-sync/specs/01-data-model-and-igdb-client.md`
**Log:** `docs/plans/beta/14-game-model-igdb-sync/log.md` **Migrations:**

- `db/migrate/20260510140000_expand_games_for_igdb.rb`
- `db/migrate/20260510140001_create_game_reference_tables.rb`
- `db/migrate/20260510140002_create_game_join_tables.rb`

**Reviewer run:** 2026-05-10 16:05

> **Phase 14 scope reminder.** Spec 02 (bundles + composite covers) and Spec 03
> (Steam-shelf UI + `video_game_link` + 16 MCP tools) are **NOT** part of this
> playbook. This review is bounded to Spec 01 (data model + IGDB v4 client) and
> the 2026-05-10 UX polish riding alongside it (`/games/index.html.erb`
> sortable + bulk + dropped `[search igdb]` button + dropped `[o]` open column;
> `/games/show.html.erb` two-pane revamp).

## Pipeline summary

- Code review: pass — 4 minor concerns, all non-blocking (see below).
- Simplify: pass — 3 opportunistic suggestions (see below).
- Spec slice
  (`spec/models/{game,genre,platform,company,game_*}_spec.rb spec/services/igdb/ spec/jobs/game_igdb_*_spec.rb spec/requests/games_spec.rb`):
  **223 examples, 0 failures**. Logged as 212 in the implementation log; the +11
  delta is the polish-pass UX specs landed alongside the rewrite.
- Test suite (`bundle exec rspec`, full): **2527 examples, 2 failures, 1
  pending**. Both failures are pre-existing and unrelated to Spec 01:
  1. `spec/lint/numeric_formatting_spec.rb:52` flags
     `app/views/projects/index.html.erb:114` (`<%= project.videos.count %>`) — a
     Phase 12 / Phase 4 surface, not Phase 14.
  2. `spec/requests/calendar/month_spec.rb:35` (Phase 15 calendar route
     constraint test) — orthogonal to this dispatch. Treat as pre-existing
     tech-debt; flagged in `## Concerns` for the next polish window. Spec 01's
     full slice is green.
- Lint (`bundle exec rubocop` on the 22 Ruby files this dispatch touched): **0
  offenses**. (Note: passing
  `app/javascript/controllers/igdb_search_controller.js` to rubocop directly
  produces parser noise because the file is JavaScript; rubocop's project config
  already excludes the JS tree, so this is a non- finding when the lint runs
  across the project the usual way.)
- Security static analysis (`bundle exec brakeman -q -w2`): **0 warnings, 0
  errors.** Same 2 obsolete ignore-file entries from Phase 10 surface again —
  noise, not a regression.
- Dependency audit (`bundle exec bundler-audit check --update`): **clean** (1078
  advisories scanned, no vulnerabilities).
- Cross-stack gates: not applicable. Diff is Rails-only — no Rust, no
  `extras/website/`, no docs-side schema changes.

### Reviewer-spec checkpoints (per spec §"Acceptance" + master-agent decisions)

- **Schema audit (Q1 + §"Schema").** `db/schema.rb` lists every column from the
  spec's tables on `games` (26 IGDB-sourced + local-only columns), the 3
  reference tables (`genres`, `platforms`, `companies`), and the 4 join tables
  (`game_genres`, `game_platforms`, `game_developers`, `game_publishers`). All 6
  documented indexes are in place (`igdb_id` unique partial, `igdb_slug` unique
  partial, `release_year`, `external_steam_app_id` partial, `platform_owned_id`,
  `igdb_synced_at`). FK
  `games.platform_owned_id → platforms.id ON DELETE SET NULL` matches Q-locked
  decision Q7. FK cascade-on-game-destroy on every join table.
- **IGDB Client error hierarchy (Q3 + §"IGDB::Client").**
  `Igdb::Client::{Error, RateLimited, ValidationError, ServerError, AuthError, MissingCredentials}`
  all defined; one-shot 401 retry with token invalidation; 429 surfaces
  `Retry-After`; 4xx → ValidationError; 5xx → ServerError; 404 → empty array
  (idiomatic IGDB shape). Pinned by 16 client examples.
- **Apicalypse builder.** Numeric IDs are NOT quoted (`where id = 7346`); string
  searches escape embedded `"` → `\"`; multiple `where` clauses join with `&`;
  `to_s` raises when `fields()` was never called. Pinned by 11 examples in
  `spec/services/igdb/apicalypse_spec.rb`.
- **Token cache (Q2).** Twitch client-credentials grant against
  `https://id.twitch.tv/oauth2/token`; cache key `igdb:twitch_token`; TTL is
  `expires_in - 60s` floored to 60s minimum (defense against a misconfigured
  zero `expires_in`); `MissingCredentials` raised lazily on first network call.
  Pinned by 8 token-cache examples.
- **Rate limiter (Q3).** Process-local 4 req/s + 8 in-flight token bucket;
  block-form returns the block's value; releases the slot on raise; shared
  singleton via `RateLimiter.shared`. Pinned by 6 limiter examples.
- **Last-write-wins (Q5).** `Igdb::SyncGame#call` writes only IGDB-sourced
  attributes via `assign_attributes(map_game(...))`; `map_game` intentionally
  excludes `platform_owned_id`, `played_at`, `notes`, `hours_of_footage_manual`,
  `hours_of_footage_cached`. Pinned by `sync_game_spec.rb` examples ("preserves
  local-only columns" + "last-write-wins on locally edited title").
- **Strict update allowlist.** `GamesController#local_only_params` permits
  exactly four columns (`platform_owned_id`, `played_at`, `notes`,
  `hours_of_footage_manual`). Smuggled `igdb_id` / `cover_image_id` / `summary`
  / `igdb_rating` / `title` are silently dropped — pinned by 5 request specs
  each shaped as "expect change.not_to" against `game.reload.<column>`.
- **Slug-collision guard (Open Question #7).**
  `Igdb::SyncGame#assign_with_slug_collision_guard` rescues
  `ActiveRecord::RecordNotUnique` whose message references `igdb_slug`, retries
  with `igdb_slug: nil`, stamps `last_sync_error`. (No spec example exercises
  the rescue branch directly — see Concerns #4.)
- **Sidekiq cron registration.** `config/sidekiq_cron.yml` carries
  `game_igdb_nightly_refresh` at `0 3 * * *` (03:00 UTC) — pinned by
  `spec/jobs/game_igdb_nightly_refresh_spec.rb` "cron registration"
  describe-block. Sleep 0.3s between enqueues respects the 4 req/s IGDB cap
  before the in-process limiter kicks in.
- **Cascade on Game.destroy.** `dependent: :destroy` on every join association
  on `Game`; the request-spec `DELETE /games/:id` example confirms
  `GameGenre.count` decrements with the game. FK `ON DELETE CASCADE` on every
  join table backs this up at the DB level too.
- **External-boundary booleans (CLAUDE.md hard rule E).** No `true` / `false`
  smuggled into URL params, JSON, or MCP I/O. Internal `retry_on_401:` kwarg is
  internal Ruby state; `developer=true`/`publisher=true` in the mapper reads
  IGDB's JSON shape (their boundary, not pito's). Clean.
- **Tenant-free (ADR 0003 / CLAUDE.md hard rule F).** No `tenant_id`, no
  `Current.tenant`, no `BelongsToTenant` reference anywhere in the new code.
  Verified via `git grep`. Clean.
- **Bracketed-link convention (CLAUDE.md design + reviewer doc rule A).** Every
  clickable element on `/games` and `/games/:id` uses `BracketedLinkComponent`
  or the `[<span class="bl">…</span>]` pattern; the only literal `[no cover]`
  placeholder follows the no-inner-spaces rule. The 2026-05-10 polish dropped
  `[ search igdb ]` and `[o]` per the user's bracket-spacing convention. No
  `[ label ]` (with inner padding) survived outside the `[ ]` / `[x]` checkbox
  shape.
- **No alert/confirm/prompt (CLAUDE.md hard rule).**
  `app/javascript/controllers/igdb_search_controller.js` debounces input and
  only sets `frame.src`; no JS modals.
- **Pane primitives (reviewer doc rule C).** `/games/show.html.erb` uses the
  canonical `.pane-row > .pane` two-pane layout (matches channels/videos); no
  `.framed-block`. Pinned by request spec
  `"renders inside a `.pane-row`of`.pane` children"`.

## Blockers

None. Spec 01 is ship-ready. Validate the Manual test steps below, then the
architect commits.

## Concerns and suggestions

All non-blocking. Triage at the architect's discretion; nothing here gates the
user-facing surface.

1. **(minor / cleanup) — `Game#build_release_metadata` reads the legacy
   `platforms` jsonb column.** `app/models/game.rb:166` calls
   `platforms.map { |p| (p["platform"] || p[:platform]) }` to populate the
   calendar entry's metadata. After Phase 14 §1, the canonical "platforms for
   this game" is `game.platforms_available` (the `has_many :through`
   association). Today the Phase 4 jsonb is still being read because the factory
   still sets it (`spec/factories/games.rb` line 10 documents the carryover).
   When the polish window drops the `platforms` jsonb column,
   `build_release_metadata` will need to switch to
   `platforms_available.pluck(:name)`. Tracking under
   `docs/orchestration/follow-ups.md` as part of the Phase 14 polish bundle.
2. **(minor / sleep in foreground job) — `GameIgdbSync#perform` calls
   `sleep(e.retry_after.to_i.clamp(1, 60))` before re-raising `RateLimited`.** A
   Sidekiq worker thread holding `sleep` for up to 60s blocks one of the
   worker's concurrency slots. Sidekiq's built-in retry already uses exponential
   backoff and would handle the re-raise cleanly without the in-perform sleep.
   Future tightening: drop the sleep, let Sidekiq's backoff schedule the retry.
   (Non-blocking — the 60s cap is bounded and the `concurrency: 5` worker pool
   absorbs it.)
3. **(opportunistic / DRY) — `Igdb::SyncGame#sync_genres` and `#sync_platforms`
   share the same delete-and-recreate-by-igdb_id shape.** The two methods could
   collapse into one private helper parameterized on the join class, the
   source-of-truth association name, and the `map_*` method. Three more
   callsites (`sync_developers`, `sync_publishers`) already share the shape with
   a different mapper entry point. Worth a refactor pass before Spec 02 lands
   its bundle equivalents (which will reproduce this shape). (Non-blocking — the
   current code is correct and covered by 11 sync_game examples.)
4. **(coverage gap, low risk) — slug-collision rescue branch is uncovered by a
   direct example.** `Igdb::SyncGame#assign_with_slug_collision_guard` rescues
   `ActiveRecord::RecordNotUnique` whose message references `igdb_slug`, retries
   with `igdb_slug: nil`, stamps `last_sync_error`. The current
   `sync_game_spec.rb` does not exercise this branch (no spec creates a
   pre-existing Game with the same slug then triggers a sync that would
   collide). Acceptable for v1 — IGDB slugs are stable and unique, so collisions
   are rare — but worth adding a single example before the nightly refresh runs
   against real-world data. Suggested test name:
   `"falls back to NULL slug + stamps last_sync_error on RecordNotUnique"`.
5. **(pre-existing tech-debt — NOT this dispatch's bug, surfaced for
   awareness)** — full-suite has 2 unrelated failures:
   - `spec/lint/numeric_formatting_spec.rb` flags
     `app/views/projects/index.html.erb:114` (`<%= project.videos.count %>`) as
     a missing `number_with_delimiter` wrapper. The Phase 12 column landed
     without going through the formatting linter. Fix is
     `<%= number_with_delimiter(project.videos.count) %>`.
   - `spec/requests/calendar/month_spec.rb:35` raises
     `ActionView::Template::Error: Document tree depth limit exceeded` under the
     route-constraint test. Phase 15 calendar surface, unrelated. Both belong on
     `docs/orchestration/follow-ups.md` for the next polish window — neither
     blocks Phase 14 §1 validation.

## Manual test steps

These walk the operator (you) through the local environment and code surfaces
before flipping to the user-facing UI walkthrough. Each step has an `Action` and
an `Expected`. Stop and roll back via `## Cleanup` if any step diverges.

1. **Bring up infra + run migrations.** Open a terminal at
   `/home/catalin/Dev/pito`.
   - **Action:** `bin/setup` (only if Docker isn't already up); then
     `bin/rails db:migrate`.
   - **Expected:** `bin/rails db:migrate` reports the three Phase 14 §1
     migrations as already applied (they ran during the implementation
     dispatch). If a migration status is `down` somewhere, run `db:migrate`
     again until clean.
2. **Add IGDB credentials in development.**
   - **Action:** `bin/rails credentials:edit --environment development`. Add the
     `igdb:` block:
     ```yaml
     igdb:
       client_id: <twitch_client_id>
       client_secret: <twitch_client_secret>
     ```
     Get the values from
     [https://dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps).
     The Twitch app needs zero scopes; client-credentials grant is enough.
   - **Expected:** Editor closes cleanly. No "missing key" error from Rails.
3. **(Optional) Add IGDB credentials in test for completeness.**
   - **Action:** `bin/rails credentials:edit --environment test`. Add any
     non-nil `client_id` / `client_secret` (the tests stub HTTP via WebMock; the
     values are never used).
   - **Expected:** Editor closes cleanly.
4. **Run the Phase 14 §1 spec slice once more locally.**
   - **Action:**
     ```
     bundle exec rspec \
       spec/models/{game,genre,platform,company,game_*}_spec.rb \
       spec/services/igdb/ \
       spec/jobs/game_igdb_*_spec.rb \
       spec/requests/games_spec.rb
     ```
   - **Expected:** **223 examples, 0 failures.**
5. **Boot the dev server.**
   - **Action:** `bin/dev`. Wait until Tailwind, Puma, and Sidekiq lines have
     all printed.
   - **Expected:** `http://localhost:3000` is up. Sidekiq prints
     `[INFO] Sidekiq … starting`.
6. **Watch a Sidekiq queue while the search runs (optional).** Open a second
   terminal.
   - **Action:** `tail -f log/development.log | grep -E 'GameIgdbSync|Igdb::'`.
   - **Expected:** Empty for now. Will fill on step 13 of `## User Validation`.

## Cleanup

If you want to start the validation walk-through over from a known-clean state:

- **Roll back DB to pre-Phase-14:** `bin/rails db:rollback STEP=3` (drops the 3
  Phase 14 §1 migrations in reverse). Then `bin/rails db:migrate` to come back
  forward.
- **Discard the Twitch token cache:**
  `redis-cli -p $(grep -E '^REDIS_URL' .env.development | sed -e 's|.*://||' -e 's|.*:||' -e 's|/.*||') DEL igdb:twitch_token`
  (or just `redis-cli FLUSHDB` if you don't have other state to keep).
- **Drop seed games:** in `bin/rails console`,
  `Game.where("igdb_id IS NOT NULL").destroy_all`.
- **Reset the Sidekiq queue:**
  `redis-cli -n 0 KEYS 'queue:*' | xargs redis-cli DEL`.

## User Validation

Validate the Phase 14 §1 user-facing surface entirely from the browser. The dev
server from Manual step 5 stays running. No terminal commands here.

[ ] 1. **Land on `/games`.** Open
[http://localhost:3000/games](http://localhost:3000/games). The page heading
reads "games" and the empty-state copy reads "no games yet. type in the search
box above to find one on igdb." A `[+]` button and a `[bulk]` toggle render at
the top of the page. **No** `[ search igdb ]` chip appears next to the input.

[ ] 2. **Search IGDB by typing.** Click into the search input. Type "zelda
breath of the wild". Wait ~300ms for the debounce. The page renders a list of
IGDB game rows below the input, each with a small cover thumbnail (or `[?]`
placeholder when IGDB has no cover), the game's name

- release year in muted parens, and an `[add]` button on the right.

[ ] 3. **Add a game from IGDB.** In the result list, click `[add]` on "The
Legend of Zelda: Breath of the Wild" (or any game you want in your library). The
page redirects to `/games/:id`. A green flash notice reads "added; metadata
loading in background." The page initially shows mostly em-dashes (`—`) because
the IGDB sync job is still running.

[ ] 4. **Watch the metadata hydrate.** Within ~1 second, refresh the page (or
wait for Turbo's auto-refresh if you have morph navigations enabled). The cover
art appears in the left pane; the title, release year, developer/publisher,
summary, ratings (igdb / aggregated / total), the three time-to-beat rows, and
the genres/platforms list all populate. The "synced X minutes ago" line appears
at the bottom of the right pane.

[ ] 5. **Confirm the show page is a two-pane layout.** Visually verify the left
pane (cover + title + summary) sits next to the right pane (ratings

- time-to-beat + local fields form + sync state). The re-sync caveat at the top
  of the right pane reads on two lines: "re-syncing overwrites igdb-sourced
  fields." then "local notes, played-on, footage hours, and platform-owned
  survive."

[ ] 6. **Open the game on IGDB / Steam / GOG / Epic.** If the IGDB row exposes
any of those external IDs, the corresponding bracketed link (`[open on igdb]`,
`[steam]`, `[gog]`, `[epic]`) renders below the title in the left pane. Click
`[open on igdb]`. A new tab opens at `https://www.igdb.com/games/<slug>`. Click
`[steam]` (if present). A new tab opens at
`https://store.steampowered.com/app/<id>/`.

[ ] 7. **Edit the local-only fields.** Back on the show page, scroll to the
"local fields" section in the right pane.

- Pick a platform from the "platform owned" dropdown (the dropdown is populated
  from this game's IGDB platforms_available list).
- Pick a date in "played on".
- Type "loved it" in "notes".
- Type `12` in "footage hours (manual)". Click `[update]`. The page reloads with
  a green flash notice "game updated." All four fields show their new values.

[ ] 8. **Re-sync and confirm last-write-wins on IGDB-sourced fields.** Click
`[resync]` in the breadcrumb action area at the top of the page (or the
`[resync]` button on `/games`'s row action column). The page redirects with a
flash "refreshing from igdb…". Wait ~1 second; refresh. The `igdb_synced_at`
line updates ("synced X seconds ago"). The local fields you set in step 7
(platform owned, played on, notes, footage hours) **survive verbatim** — confirm
by inspection.

[ ] 9. **Confirm IGDB-sourced fields are NOT user-editable on the show page.**
Inspect the form: there is no input for `title`, `summary`, `igdb_rating`,
`cover_image_id`, or any other IGDB-sourced column. The update button only
submits the four local-only fields.

[ ] 10. **Browse `/games` index, sort it.** Navigate to
[http://localhost:3000/games](http://localhost:3000/games). The added game
appears in a row with: title (clickable, opens the show page), release year,
IGDB rating ("X / 100"), played date, last sync ("X minutes ago"), and a
`[resync]` action button. **No** separate `[o]` open-action column renders — the
title cell IS the link. Click the "name" header. The table re-sorts ascending by
title; the URL updates to `?sort=title&dir=asc`. Click "rating". The arrow
indicator on the active column renders as a single directional glyph (no
double-arrow stack).

[ ] 11. **Use bulk mode.** Click `[bulk]`. Checkbox columns appear on the header
and every row. The bulk toolbar appears with `[cancel]`. Tick a row's checkbox.
The `[delete]` action chip appears in the toolbar with a count. Click
`[cancel]`. Bulk mode exits cleanly.

[ ] 12. **Add a second game by direct IGDB ID.** From `/games`, type a search
term in the search box (e.g. "stardew"). Click `[add]` next to "Stardew Valley"
(or any other result). The new game lands at its show page with the same
hydration flow as step 4. Both games are now listed at `/games`.

[ ] 13. **Confirm dedup of IGDB ID.** Search for the same game you added in step
12 (e.g. "stardew"). Click `[add]` on the same result row. The page redirects to
the EXISTING game's show URL with a yellow alert "already in your library."

[ ] 14. **Try to smuggle IGDB-sourced fields via the update form.** Open browser
dev tools on the show page; switch to the network tab. In the local-fields form,
edit `notes` to "second update", then in the dev tools open the form action URL
after submit and inspect the request body under `game[*]`. Now (advanced —
optional) use the dev-tools "edit and resend" feature to add a
`game[title]=hijacked` field to the same PATCH and resend. The response is 302
to the show page; the title is **unchanged** (still IGDB's value). Notes IS
updated to "second update". This validates the controller-level allowlist.

[ ] 15. **Trigger an IGDB validation error.** In `bin/rails console`, run:

```
g = Game.find_by(title: "<your test game>")
g.update_columns(igdb_id: 99_999_999)
GameIgdbSync.perform_async(g.id)
```

(Step out of `bin/rails console` after.) Refresh the game's show page in the
browser ~5 seconds later. The right pane now shows a red banner "igdb error:
igdb error: IGDB has no game with id=99999999" and the `igdb_synced_at`
timestamp is unchanged from before the failed sync. Click `[resync]` again — the
banner persists (still no row on IGDB's side). Restore:
`g.update_columns(igdb_id: <original>)` and resync once more; the banner clears
on the next successful sync.

[ ] 16. **Delete a game, confirm cascade.** From `/games`, navigate into the
test game's show page. Click `[-]` in the breadcrumb action bar (top right of
the page). The action confirmation screen renders ("Delete this game?"). Click
`[confirm]`. The page redirects to `/games` and the game is gone from the list.
Behind the scenes, every `game_genres` / `game_platforms` / `game_developers` /
`game_publishers` join row for that game is also gone (verified by request
spec).
