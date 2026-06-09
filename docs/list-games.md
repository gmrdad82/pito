# list games — table, platforms, release date, suggestions

> Status: Running (plan-runner) — current branch `cleanup-fixups`.

## Sign-off

- [x] Drafted
- [x] Audited

## Context

`list games` is the games-domain list command in the conversational shell. Four
problems, all traced to root cause in the current branch:

1. **Multi-column table collapses to a vertical list.** `list games with developer,
   publisher, genres, release date, year, platforms` renders each header on its own
   line instead of a table. Root cause: `Pito::Event::SystemComponent#table_grid_cols`
   builds a Tailwind arbitrary class at *runtime* (`grid-cols-[max-content_…_1fr]`).
   Tailwind v4 only compiles classes it scans in source (`@source "../../components"`);
   the only literal in source is the 2-col `grid-cols-[max-content_1fr]`. Any N≥3 string
   is never compiled → the element keeps `display:grid` with **no** `grid-template-columns`
   → one implicit column → vertical stack. User wants columns that **wrap** and stay
   compact — not `max-content` columns that expand to full content width.

2. **Platforms show raw IGDB names.** The platform column joins `g.platforms` verbatim →
   "Google Stadia, Xbox Series X|S, PlayStation 4, Nintendo Switch 2, PC (Microsoft
   Windows)…". User wants ONLY 3 pito tokens, labelled **PlayStation / Switch / Steam**
   (Xbox/Google/Mac/PC names dropped). A working token mapping already exists but is
   private to the detail card (`app/components/pito/game/detail_component.rb:13-69`,
   `IGDB_TO_TOKEN` + `platform_tokens`/`platforms_label`). Raw names stay stored; only
   display + sort normalize.

3. **Release date column isn't routed through a formatter.** User wants it formatted via
   `Pito::Formatter` like "June 09, 2026". `Game#release_label` (`app/models/game.rb:76-97`)
   already produces this for full-precision dates (and partial labels / "TBA" otherwise)
   but the logic lives in the model, not in the `Pito::Formatter::*` family of pure
   functions.

4. **Autocomplete is wrong after `list games`.** After `list games ` the ghost should be
   ` with` but the user sees "channels"; `list games with ` offers no fields. Root cause:
   the server engine *does* compute clause ghosts (`Pito::Suggestions::ListClauseGhost`)
   but the JS client never defers to it for the `list` verb — `_computeLocalGhost` resolves
   the static `:noun` slot locally (`app/javascript/controllers/pito/suggestions_controller.js:583-653`).
   And nothing suggests the ` with` connector after the noun (`ListClauseGhost.ghost`
   returns nil unless a `with`/`sorted by` clause is already present). The `with` options
   must be exactly platform|platforms, genre|genres, developer|dev, publisher, release
   date, year — **no channels** in the `with` list (`ListClauseGhost.registry_for` already
   excludes channels). The bare `list ` "channels" default is fine and stays. Channel
   filtering is the separate Shift+Tab handle mechanism (`chat_form_controller.js`), out of
   scope. Videos/channels suggestions are a later session — focus is `list games`.

Outcome: clean wrapping multi-column table; platforms shown as PlayStation/Switch/Steam
only; release date via a `Pito::Formatter`; and `list games` autocomplete that ghosts
` with` then the field tokens, never "channels". Specs added in both Rails (RSpec) and JS
(vitest).

## North star

`list games with developer, publisher, genres, release date, year, platforms` renders a
compact, word-wrapping table; platform cells read "PlayStation, Switch, Steam"; release
dates read "June 09, 2026"; and the input ghosts ` with` → field tokens as you type.

## Locked decisions

- **Reuse the existing mapping — don't reinvent.** The detail card already has the working
  mechanism: `IGDB_TO_TOKEN` (an `[regex, token]` array) + `#platform_tokens` +
  `#platforms_label` (`app/components/pito/game/detail_component.rb:13-69`). We **extract
  that verbatim** into a shared module and **broaden the existing regexes** in place — same
  array shape, same method semantics.
- **Platform labels:** `ps → PlayStation`, `switch → Switch`, `steam → Steam`. Three buckets,
  matched case-insensitively against each raw IGDB name (broadened `IGDB_TO_TOKEN` entries):
  - **PlayStation** ← `/playstation|ps\s?\d/i` (PS5, PS4, PlayStation 3, Playstation 4, …).
  - **Switch** ← `/switch/i` (Nintendo Switch, Switch 2, Switch Gen 1, …).
  - **Steam** (PC bucket) ← `/steam|pc|windows|gog|epic|amazon|battle\.?net/i`.
  Everything else is **dropped** from display — Xbox*, Google Stadia, Mac, etc. Generation-
  specific labels rejected (buckets are coarse).
- **Platforms stored unchanged.** Only display + the platform sort key normalize.
- **Table grid uses a CSS class + a `data-cols` attribute** (like `data-accent`) selecting
  static, compiled `.pito-data-grid[data-cols="N"]` rules. **No inline style, no runtime
  Tailwind arbitrary classes.** First two columns (`#`, Game/key) are content-sized
  defaults; every extra `with` column is an equally-spaced, wrap-capable `1fr` track.
- **Single source of truth for `list` ghosts is the server.** The JS client defers the whole
  `list` verb to `POST /suggestions` (returns `null` from `_computeLocalGhost`); the server's
  `ListClauseGhost` + `compute_ghost` drive noun completion, the ` with` connector, the
  `with`/`sorted by` field tokens, and channel exclusion.
- **Noun vocab order unchanged** (`%w[channels videos games]` — natural to the user). The bare
  `list ` default ghost stays "channels"; that is acceptable. Scope is `list games` only —
  videos/channels suggestions are a later session.
- Plan tiers `[manual|low|high]`; no `[skipci]`; current branch (`cleanup-fixups`); specs on;
  plain imperative commit messages, no co-author trailer.
- **Drop misaligned legacy.** When a verb is redefined, remove everything that no longer
  matches the new direction — code, specs, comments, copy, confirmations — for that verb.
  No dead leftovers. Applies to every verb rework below.
- **`--help` is always ghost-suggested.** ANY command/context that accepts `--help` must
  ghost-complete toward `--help` the moment the user types `-` / `--` / `--h` (etc.).
  Universal — chat verbs (done, Phase 7 T7.3) AND hashtag verbs/actions (via the hashtag
  suggestion ghost) AND any future `--help`-accepting input.
- **Aliases stay active and are preserved across every rework** (id-only changes *argument
  resolution*, never verb/action aliases). Canonical sets:
  - `list` ← {list, **ls**}; `delete` ← {delete, **rm**}.
  - confirm ← {**confirm, yes, ok, approve, true**, y}; cancel ← {**cancel, no, false, discard**, n}.
  - column `with`-aliases unchanged (platform/platforms, genre/genres, developer/dev, …).
  `confirm`/`cancel` currently only have yes/y and no/n (`ACTION_ALIASES` in
  `follow_up/handlers/confirmation.rb`) — the fuller sets (ok/approve/true, false/discard) are
  ADDED (T36.2).
- **Hashtag commands infer from the `#hashtag` target — list vs detail:**
  - **Detail** targets (`#show-game-hashtag`, `#show-video-hashtag`): the subject AND its id
    are implied (the message is about one specific game/video). Actions take **no primary
    id** — `delete`, `reindex`, `footage <path>`, `link to video <id>`, `unlink from
    video <id>`. Only the **cross-entity** ref stays.
  - **List** targets (`#list-games-hashtag`, `#list-videos-hashtag`): you must pick an item,
    so the **id stays** — `show <id>`, `delete <id>` (`#list-channels-hashtag visit @handle`).
  - Chat verbs always keep the explicit noun (app-wide, no context). Two separate copy
    trees: chat `pito.copy.chat_help.*` and hashtag `pito.copy.hashtag_help.*` (hence two
    "show" entries).

## Execution discipline & order

- **Orchestration:** one Sonnet sub-agent per atomic task (or a tight cohesive unit) — no
  big batches. Sub-agents NEVER `git commit` and NEVER edit this doc. Escalate to an Opus
  sub-agent on repeated failure.
- **Checkboxes:** `[ ] → [-]` on dispatch, `[-] → [x]` on verify (each its own edit). The
  phase's Commit task flips `[x]` immediately before `git commit`; that commit stages this
  doc alongside the code. Plain imperative messages, no co-author trailer.
- **Tests:** during a task run ONLY the touched specs; run the **full** `bundle exec rspec`
  + `npm test` at each **phase end** (before the phase commit). Cross-cutting phases
  (25, 30, 35) always end on a full run.
- **Spec count:** record the full-suite baseline ONCE at execution start (T0 below); compare
  ONLY full runs to it; a subset run is labelled "subset", never quoted as the total
  (>4000 examples currently).
- **Order / dependencies:** Phase 7 chat `--help` infra = DONE (v1, single-verb). **Phase 38**
  (CommandHelp v2, noun-aware/both-levels) must land BEFORE the noun-split chat `--help` phases
  (9/11/13/17/19/21/23) — it supersedes Phase 7's copy + specs. **Phase 35** (hashtag `--help`
  infra) must land BEFORE the hashtag `--help` tasks in 27/31/32/33/34 and 25.5.
  **Phase 25** (add/remove columns) lands WITH or right after Phases 31 & 33 so
  game_list/video_list handlers are edited once. Drops (26/29/30) can precede their
  dependents. Reworks that change parsing (10/12/14/16/18/20/22/24) can run independently.

### T0 — Baseline (do first)

- [x] T0.1 Baseline recorded: **`bundle exec rspec` = 4373 examples, 0 failures**; **`npm test` (vitest) = 329 tests, 0 failures** (commit `8e8f8df1`+). Compare only FULL runs to this. complexity: [manual]

## Investigation findings (uncertainties → resolutions)

Read-only code investigation done before execution. Drives the task details below.

1. **confirm/cancel = one path (RESOLVED).** Route via `FollowUp::Router` (`reply_handle`) →
   `ChatController#handle_follow_up` → `FollowUpDispatchJob`; `FollowUp::Handlers::Confirmation`
   (`:append`, actions confirm/cancel) stamped with `make_followupable!(target:"confirmation")`.
   The `Hashtag::Handlers::Reply` + `confirmation_handle` + `Normalizer.call_ops(:hashtag)` path
   is **dead/legacy** (pre-P14 fallback; one `chat_hashtag_spec` documents it). ⇒ **T25.6 (drop
   legacy add/remove-metrics) is SAFE** for confirm/cancel; update that spec on drop.
2. **per-action consume mode (RESOLVED, scoped).** Mode is per-TARGET today
   (`Registry.mode_for(target)`, read in `handle_follow_up` BEFORE the handler runs). For mixed
   actions: add `action_modes` DSL on `FollowUp::Handler`; `Registry.mode_for(target, action:)`;
   in `handle_follow_up` extract `action = rest.split.first` and pass it. ~3 files + handler
   decls. ⇒ **T25.2 approach locked.**
3. **Phase 7 chat_help copy must be REWRITTEN + noun-aware (RESOLVED).** The 11
   `pito.copy.chat_help.*` keys use `<title>`/"#id", one key per verb. Noun-split + id-only-no-#
   phases must **rewrite** them and make `CommandHelp.call` **(verb, noun)-aware** —
   key structure `chat_help.<verb>.<noun>` (e.g. `chat_help.show.game`); the dispatcher passes the
   noun. **Both levels** (mirrors hashtag): bare `<verb> --help` lists the noun forms;
   `<verb> <noun> --help` shows the specific page. ⇒ **owned by Phase 38 (CommandHelp v2), a
   prerequisite for the noun-split `--help` phases (9/11/13/17/19/21/23); supersedes Phase 7.**
4. **hashtag `--help` ghost = server-side (RESOLVED).** No hashtag ghost today; hashtag arg-stage
   is server-driven (`_scheduleArgFetch`/`_fetchArgSuggestions`). Add the `-`→`--help` ghost in the
   SERVER hashtag completion (`engine.rb` `hashtag_*_completions`, mirroring free-mode
   `engine.rb:563-566`); client applies automatically. ⇒ **T35.3 is server-side, low complexity.**
5. **list videos/channels OK; themes Sidebar EXISTS (RESOLVED).** `list videos` works (table;
   with-cols game/duration/views/likes/comments) and `list channels` works (cards, no args) →
   Phase 8 T8.2/T8.3 accurate. **`/themes` is a working slash command that opens the themes
   Sidebar** (`Pito::Sidebar::Themes::Component` + `_theme_sidebar.turbo_stream.erb` +
   `theme_nav_controller.js`); the Sidebar does preview/apply. ⇒ **Phase 26 only removes themes
   from the chat verbs (drop the `theme_list` chat/hashtag follow-up); the `/themes` Sidebar is
   untouched.**
6. **shared resolver = per-verb flag (RESOLVED).** `Pito::Chat::TargetResolution#find_by_ref`
   (id OR title ILIKE) is shared by show/delete/sync/reindex (link/unlink resolve manually).
   id-only is safe **per-verb** via a handler flag (e.g. `resolve_by :id_only`); `import game
   [title]` keeps title (intercepted before the handler). ⇒ **id-only phases (10/16/18/20/22/24)
   set the per-verb flag; don't change the shared default globally.**
7. **schedule = enter LOCAL, convert to UTC at the YouTube boundary (RESOLVED).** Today all times
   are `Time.utc`; `Channel` has no tz column. Decision: input `dd-mm-yyyy hh:mm` is parsed in the
   **app local zone** (`Time.zone`), ≥30 min from now; convert to UTC **only when the YouTube API
   requires it** (at send time); display local. **No per-channel tz column.** ⇒ T22.3/T21.3.
8. **baseline spec count — deferred to T0** (can't run in plan mode; >4000 examples).

## Phase index

- **Phase 1 — Platform tokens (display + sort), PlayStation/Switch/Steam**
- **Phase 2 — Release date via `Pito::Formatter`**
- **Phase 3 — Wrapping multi-column table grid**
- **Phase 4 — `list games` autocomplete: ` with` connector + field tokens**
- **Phase 5 — Help message rewrite + `list games --help`**
- **Phase 6 — Polish (post-review tweaks) + platform engine**
- **Phase 7 — `--help` man page for every chat verb**
- **Phase 8 — Per-noun `list --help` (games ✅ / channels / videos)**
- **Phase 9 — `show game --help` / `show video --help`**
- **Phase 10 — Fix `show game` / `show video` implementation**
- **Phase 11 — `import videos --help` / `import game --help`**
- **Phase 12 — Fix `import videos` / `import game` implementation**
- **Phase 13 — `sync videos --help` / `sync channels --help`**
- **Phase 14 — Rework `sync` implementation (drop `sync game` + legacy forms)**
- **Phase 15 — `footage game --help`**
- **Phase 16 — Rework `footage game` implementation (id only, no title)**
- **Phase 17 — `delete game --help` / `delete video --help`**
- **Phase 18 — Rework `delete game` / `delete video` implementation (id only)**
- **Phase 19 — `reindex game --help` / `reindex video --help`**
- **Phase 20 — Rework `reindex game` / `reindex video` implementation (id only)**
- **Phase 21 — `publish video --help` / `unlist video --help` / `schedule video --help`**
- **Phase 22 — Rework `publish` / `unlist` / `schedule` video implementation (id only)**
- **Phase 23 — `link`/`unlink` `game`/`video` `--help`**
- **Phase 24 — Rework `link` / `unlink` implementation (local ids only)**
- **Phase 25 — Repurpose `add` / `remove` → list-column mutation (game_list/video_list)**
- **Phase 26 — Drop `theme_list` chat/hashtag flow (`/themes` Sidebar only)**
- **Phase 27 — `#list-channels-hashtag` (visit only; drop reindex)**
- **Phase 28 — Drop `#id` row from `Channel::ItemComponent`**
- **Phase 29 — Drop `game_enhanced` follow-up (no hashtag on the Enhanced message)**
- **Phase 30 — Make `channel_visit`/`consume` internal-only (hide hashtag, keep flow)**
- **Phase 31 — `#list-videos-hashtag` (show / delete video)**
- **Phase 32 — `#show-video-hashtag` (delete / reindex / link / unlink video)**
- **Phase 33 — `#list-games-hashtag` (show / delete)**
- **Phase 34 — `#show-game-hashtag` (delete / footage / link / unlink; drop resync)**
- **Phase 35 — Hashtag `--help` infra (prerequisite for 27/31–34)**
- **Phase 36 — `#confirmation-hashtag` `--help` (man style)**
- **Phase 37 — Final verification (CI runs the WHOLE suite)**
- **Phase 38 — Chat `--help` noun-aware infra (CommandHelp v2, both levels) — prereq for 9/11/13/17/19/21/23**

---

## Phase 1 — Platform tokens (display + sort)

- [x] T1.1 Create `docs/list-games.md` with this file's full content. complexity: [manual]
- [x] T1.2 Move the existing `IGDB_TO_TOKEN` array, `#platform_tokens`, and `#platforms_label` verbatim out of `detail_component.rb` into new `app/services/pito/game/platform_tokens.rb` (module `Pito::Game::PlatformTokens`, `module_function`), keeping the `[regex, token]` shape; methods take `platforms` instead of reading `@game`. complexity: [low]
- [x] T1.3 Broaden the moved `IGDB_TO_TOKEN` regexes in place to the three buckets (Locked decisions): PlayStation `/playstation|ps\s?\d/i`, Switch `/switch/i`, Steam `/steam|pc|windows|gog|epic|amazon|battle\.?net/i`. complexity: [low]
- [x] T1.4 Expose `tokens(platforms)` and `labels(platforms)` as the module's public entrypoints (label = the existing `I18n.t(...platform_label.#{token})` join). complexity: [low]
- [x] T1.5 Update the label key from `pito.game.detail.platform_label` to a shared `pito.game.platform_label` in `config/locales/pito/game/en.yml`; set `switch: Switch` (was "Nintendo Switch"). complexity: [low]
- [x] T1.6 Replace `DetailComponent#platform_tokens`/`#platforms_label` with thin calls to `Pito::Game::PlatformTokens` (pass `@game.platforms`); the template keeps calling `platforms_label`. complexity: [low]
- [x] T1.7 Change the `:platform` column `value:` proc in `app/services/pito/message_builder/game/list_columns.rb` to `->(g) { Pito::Game::PlatformTokens.labels(g.platforms).to_s }`. complexity: [low]
- [x] T1.8 Change the `:platform` `SORT_SPECS` key in the same file to sort on `PlatformTokens.labels(g).to_s` so sort matches display. complexity: [low]
- [x] T1.9 Create `spec/services/pito/game/platform_tokens_spec.rb`: assert each bucket (PS5/PS4/"PlayStation 3"→ps; "Nintendo Switch 2"/"Switch Gen 1"→switch; Steam/"PC (Microsoft Windows)"/GOG/Epic/Amazon/Battle.net→steam), Xbox*/Google Stadia/Mac dropped, and de-dup (PS4+PS5 → one PlayStation). complexity: [low]
- [x] T1.10 Add a `list_columns` spec example asserting the platform cell renders normalized labels (no raw IGDB names). complexity: [low]
- [x] T1.11 Update the detail-component spec for the "Switch" label (was "Nintendo Switch") and the moved locale key. complexity: [low]
- [x] T1.12 Run `bundle exec rspec` for the touched specs; `bin/rubocop` clean. complexity: [low]
- [x] T1.13 Commit: "Normalize game platforms to PlayStation/Switch/Steam in list + detail". complexity: [manual]

## Phase 2 — Release date via Pito::Formatter

- [x] T2.1 Create `app/services/pito/formatter/release_date.rb` — `Pito::Formatter::ReleaseDate.call(game)` returning the precision-aware label (full date → `I18n.l(date, format: :long)` = "June 09, 2026"; month/quarter/year fallbacks; "TBA"). complexity: [low]
- [x] T2.2 Move the body of `Game#release_label` into the formatter; make `release_label` delegate to `Pito::Formatter::ReleaseDate.call(self)`. complexity: [low]
- [x] T2.3 Change the `:release_date` column `value:` proc in `list_columns.rb` to `->(g) { Pito::Formatter::ReleaseDate.call(g).to_s }`. complexity: [low]
- [x] T2.4 Create `spec/services/pito/formatter/release_date_spec.rb` covering full date "June 09, 2026", month-year, quarter, year-only, and TBA. complexity: [low]
- [x] T2.5 Run `bundle exec rspec` for the touched specs (incl. existing `Game#release_label` spec); `bin/rubocop` clean. complexity: [low]
- [x] T2.6 Commit: "Route release date through Pito::Formatter::ReleaseDate". complexity: [manual]

## Phase 3 — Wrapping multi-column table grid

- [x] T3.1 Add `.pito-data-grid` to `app/assets/tailwind/application.css`: base `display:grid; column-gap:0.5rem; row-gap:0.25rem;` + per-count rules `.pito-data-grid[data-cols="N"]` (N=2..8) where the first two columns are `max-content` and the rest are `repeat(N-2, minmax(0,1fr))` equally-spaced wrap-capable tracks. complexity: [low]
- [x] T3.2 Delete `SystemComponent#table_grid_cols`; add `table_col_count(n)` returning `[n,2].max` for the `data-cols` attribute (no inline style). complexity: [low]
- [x] T3.3 In `system_component.html.erb` (line ~111) replace the grid `class`/`<%= table_grid_cols %>` with `class="pito-data-grid<%= body ? ' mt-2 border-t border-line-default pt-2' : '' %>" data-cols="<%= table_col_count(n_cols) %>"`. complexity: [low]
- [x] T3.4 Apply the same replacement at the second grid site (line ~146, html branch). complexity: [low]
- [x] T3.5 Confirm non-`#` cells have no `whitespace-nowrap` so values wrap; leave heading cells nowrap (single-word headings). complexity: [low]
- [x] T3.6 Update `spec/components/pito/event/system_component_spec.rb` expectations that asserted the old `grid-cols-[…]`/`--pito-cols` → assert `pito-data-grid` + `data-cols="N"` and N spans. complexity: [low]
- [x] T3.7 Add an 8-column example (`#`, Game + 6 with-cols) asserting one `pito-data-grid` container, `data-cols="8"`, and 8 heading spans (no vertical-stack regression). complexity: [low]
- [x] T3.8 Run `bundle exec rspec spec/components`; `bin/rubocop` clean. complexity: [low]
- [x] T3.9 Commit: "Render list/data tables with a wrapping data-cols grid". complexity: [manual]

## Phase 4 — list games autocomplete: with connector + field tokens

(No noun-vocab reorder — bare `list ` "channels" default is intentional and untouched.)

- [x] T4.1 Extend `Pito::Suggestions::ListClauseGhost.ghost`: when registry present and no `with`/`sorted by` clause, add a connector branch that ghosts `with` after a completed noun (require noun + `\s+`; partial = last token; non-connector partials → no ghost). complexity: [high]
- [x] T4.2 In `suggestions_controller.js` `_computeLocalGhost`, after the chat-spec gate, `return null` when `chatSpec.name === "list"` so the client always defers the `list` verb to `POST /suggestions`. complexity: [low]
- [x] T4.3 Verify `_fetchDynamicGhost` applies `data.ghost.complete_current` (it does, line ~944) — no client ghost-apply change needed. complexity: [low]
- [x] T4.4 Add `list_clause_ghost_spec.rb` examples: `list games ` → ghost "with"; `list games w` → "ith"; `list games with ` → "platform"; `list games with d` → "eveloper"; `list games rpg` (filter partial) → no connector ghost. complexity: [low]
- [x] T4.5 Add `engine_spec.rb` example: `free_completions("list games ")` returns ghost "with" (server is the source of truth); confirm bare `list ` still ghosts "channels" (unchanged). complexity: [low]
- [x] T4.6 Add vitest cases to `spec/javascript/suggestions_controller.test.js`: typing `list games with ` defers to fetch and renders the mocked server ghost "platform"; `list games ` renders mocked "with"; assert the client does not locally resolve the `list` noun slot (defers instead). complexity: [high]
- [x] T4.7 Run `bundle exec rspec` (suggestions specs) and `npm test` (vitest); `bin/rubocop` clean; `node --check app/javascript/controllers/pito/suggestions_controller.js`. complexity: [low]
- [x] T4.8 Commit: "Drive list-games autocomplete from the server: with connector + field tokens". complexity: [manual]

## Phase 5 — Help message rewrite + `list games --help`

North star: the standard `help` message is a Standard (system) message with ONE
group for now — **GAMES** (yellow title) — containing a single kv-table row
`list games` → `use --help for more info`. And `list games --help` returns a
Standard message explaining the optional `with` columns and their aliases. **All
user-facing text comes from `Pito::Copy`** (`config/locales/pito/copy/en.yml` under
`pito.copy.*`). No inline style.

- [x] T5.1 Inspect `Pito::MessageBuilder::Help::FollowUpActions`, `Pito::Chat::Handlers::Help`, the `sections`/yellow rendering in `system_component.html.erb`, and the `Pito::Copy.render` API + copy-key layout. complexity: [low]
- [x] T5.2 Add `Pito::Copy` keys for the help message under `pito.copy.help.*` (`games_group_title` → "GAMES", `list_games_label` → "list games", `list_games_hint` → "use --help for more info"). complexity: [low]
- [x] T5.3 Rewrite `Pito::Chat::Handlers::Help#call` to use new `Pito::MessageBuilder::Help::Commands` — a visible `html: true` payload: yellow bold **GAMES** title + a kv-table row (`list games` → `use --help for more info`), all text via `Pito::Copy`. complexity: [high]
- [x] T5.4 Detect `--help` on the `list` verb: in `Pito::Chat::Handlers::List#call`, when `message.raw` matches `/(?:\A|\s)--help(?:\s|\z)/`, short-circuit to `games_list_help` instead of listing. complexity: [low]
- [x] T5.5 Add `Pito::Copy` keys (`pito.copy.list.games_help.*`) + `Pito::MessageBuilder::Game::ListHelp` building an "Option/Aliases" kv-table whose rows derive from `ListColumns::COLUMNS` (aliases stay in sync). complexity: [high]
- [x] T5.6 Specs: help handler renders a GAMES group + the `list games` row; `list games --help` returns the columns explanation (asserts each of the 6 columns appears); `list games` (no flag) still lists normally. complexity: [low]
- [x] T5.7 Run `bundle exec rspec` for the touched specs; `bin/rubocop` clean. complexity: [low]
- [x] T5.8 Commit: "Rewrite help message (GAMES group) + add list games --help columns guide". complexity: [manual]

## Phase 6 — Polish (post-review tweaks) + platform engine

Iterative refinements from live review. No inline style (data attributes only).

- [x] T6.1 Rework `list games --help` into an `nvim --help` man page (`Usage:` / `Options:` / `Columns:`, aligned token→description), drop the intro line + the Option/Aliases table. New `.pito-help-block` CSS + `pito.copy.list.games_help.*` keys. complexity: [high]
- [x] T6.2 Pluralize the list intro copy: "1 game" not "1 games" — `%{noun}` placeholder in all list_intro variants, builder passes `noun:`. complexity: [low]
- [x] T6.3 Right-align the `#` column heading (heading now a `{text,class:"text-right"}` cell; cells already right-aligned). complexity: [low]
- [x] T6.4 Right-align the Release + Year columns — headings (`heading_cells`) + row cells (`text-right`, year `tabular-nums`). complexity: [low]
- [x] T6.5 Release + Year as content-hugging trailing tracks (canonical order via `ListColumns.canonical_order`); others split `1fr`. `data-fixed-trailing` attribute + static CSS rules. complexity: [high]
- [x] T6.6 Centralized platform engine (`Pito::Game::PlatformTokens`): groups PS4/PS5→`ps`, Switch variants→`switch`, PC/Steam/GOG/Epic/Amazon/Battle.net→`steam`; single source that outputs labels or SVG (`icons_html`); enforces order **PS → Switch → Steam**. complexity: [high]
- [x] T6.7 SVGs moved to `public/platforms/{playstation,switch,steam}.svg`; logos render at ≤16px height via `.pito-platform-icon`; used in BOTH the list table (html cell) AND the detail card. complexity: [high]
- [x] T6.8 Specs for pluralization, alignment, fixed-width attribute, platform order, html-cell, and logo rendering. complexity: [low]
- [x] T6.9 Commit(s) per cohesive change. complexity: [manual]
- [x] T6.10 `/help` content: removed `ctrl+|`, `shift+r`, `esc`, backtick, and `space` from `pito.slash.help.keybindings`. complexity: [low]
- [x] T6.11 Bug: `Ctrl+Shift+R` (browser reload) no longer hijacked by the `shift+r` reply prefix (plain Shift+R only). complexity: [low]
- [x] T6.12 Bug: `list games --h` ghosts `elp` (`--help` added as a connector candidate). complexity: [low]
- [x] T6.13 Bug: `list games so` ghosts `rted by` (`sorted by` added to connector candidates). complexity: [low]
- [x] T6.14 Bug: TBA **sorting** — TBA (no date/year) now sorts AFTER all known dates ascending (and first descending) by treating unknown as the far future (`Date.new(9999,12,31)` / year `9999`) instead of `Date.new(0)`/`0`. Release stays **right-aligned** (correct). complexity: [low]
- [x] T6.15 `shift+tab`/`shift+space` cyclers wrapped in a focus-gated `filterHints` target (visible ⟺ focused); `m chat` hint is its inverse (visible ⟺ not focused) — mutually exclusive; dropped the leading separator before `m`. Shared `pito--chatbox-hints` controller covers `/` and `/not_found` via the same focus tracking. complexity: [high]

## Phase 7 — `--help` man page for every chat verb

North star: every chat verb supports `<verb> --help`, returning the SAME nvim/Linux
man-page format as `list games --help` (`Usage:` + `Arguments:`/`Options:` sections,
aliases included, `Columns:` only where a `with` clause exists). Typing `-` (or part
of `--help`) after a recognised verb ghosts `--help`. ALL copy from `Pito::Copy`.

Infra (shared, do first):
- [x] T7.1 Shared `Pito::MessageBuilder::ManPage.render(usage:, groups:)` renderer (extracted from `Game::ListHelp`, which now delegates to it — `list games --help` byte-identical). complexity: [high]
- [x] T7.2 `Pito::MessageBuilder::CommandHelp.call(verb:)` (:list→ListHelp; others read `pito.copy.chat_help.<verb>`) + dispatcher intercepts `/(?:\A|\s)--help(?:\s|\z)/` → CommandHelp. complexity: [high]
- [x] T7.3 Generic `--help` ghost hint: `-`/`--h` after a recognised verb ghosts `--help` (JS `_computeLocalGhost` + server `compute_ghost`; `list` via `ListClauseGhost`). complexity: [high]

Per-verb man pages (one atomic task each — author `pito.copy.chat_help.<verb>` + confirm the handler routes `--help`):
- [x] T7.4 `show --help` — copy added (`pito.copy.chat_help.show`); routes via dispatcher. complexity: [low]
- [x] T7.5 `find --help` — DROPPED. `find` is a grammar spec with NO handler (dead verb → `verb_not_implemented`); the speculative `chat_help.find` copy was removed. A dispatcher spec documents the `find`-has-no-handler behaviour. complexity: [high]
- [x] T7.6 `import --help` — copy added (accurate: `import <noun> [title]`, videos/game forms). complexity: [low]
- [x] T7.7 `sync --help` — copy added (all five sync sub-forms listed). complexity: [low]
- [x] T7.8 `footage --help` — copy added (`footage <title> <path>`). complexity: [low]
- [x] T7.9 `delete --help` — copy added. complexity: [low]
- [x] T7.10 `reindex --help` — copy added. complexity: [low]
- [x] T7.11 `publish --help` — copy added. complexity: [low]
- [x] T7.12 `unlist --help` — copy added. complexity: [low]
- [x] T7.13 `schedule --help` — copy added (`<title> <when>`, UTC time). complexity: [low]
- [x] T7.14 `link --help` — copy added (explains `game <ref> to video <ref>`). complexity: [low]
- [x] T7.15 `unlink --help` — copy added. complexity: [low]
- [x] T7.16 Specs: `ManPage` + `CommandHelp` (parametrized over all verbs) + dispatcher + `-`→`--help` ghost (Rails + vitest). complexity: [high]
- [x] T7.17 Commit(s) per cohesive change. complexity: [manual]

## Phase 8 — Per-noun `list --help`

`list <noun> --help` must be noun-aware (today it always shows the games man page).

- [x] T8.1 `list games --help` — games columns man page (done, Phase 5/6).
- [ ] T8.2 `list channels --help` — `Usage: list channels` + one random witty line from a ~50-variant `Pito::Copy` pool (no args: "there's nothing here" / "what did you expect?" / "found what you were looking for" tone).
- [ ] T8.3 `list videos --help` — games-style man page with the **video** columns: `game, games` / `duration` / `views` / `likes` / `comments` (copy from `Pito::Copy`).

## Phase 9 — `show game --help` / `show video --help`

Same man style. Each accepts a **title or an id** (id = the plain number, **no `#`**);
multi-word titles must be wrapped in `"…"`. (Implementation of `show` itself is known-bad
and will be revisited — these tasks are the `--help` man pages only.)

- [ ] T9.1 `show game --help` — `Usage: show game <title|id>`; accepts a game title (multi-word in `"…"`) or a game id (plain number). Copy from `Pito::Copy`.
- [ ] T9.2 `show video --help` — `Usage: show video <title|id>`; accepts a video title (multi-word in `"…"`) or a video id (plain number). Copy from `Pito::Copy`.

## Phase 10 — Fix `show game` / `show video` implementation

The real `show` behavior is currently wrong (hallucinated during earlier implementation).
These tasks fix the actual commands so they accept a title (multi-word in `"…"`) or a
plain id (no `#`) and resolve/show the right entity. Exact bugs to be specified when we
get here.

- [x] T10.1 Fix `show game` — bug found: quoted multi-word titles weren't quote-stripped before ILIKE so `show game "Elden Ring"` never matched. Fixed in `TargetResolution#strip_noun`; renders Game::Detail. complexity: [high]
- [x] T10.2 Fix `show video` — same quote-stripping fix; `show video "…"` resolves; renders Video::Detail. complexity: [high]

## Phase 11 — `import videos --help` / `import game --help`

Same man style. Copy from `Pito::Copy`.

- [ ] T11.1 `import videos --help` — `Usage: import videos [for @handle]`; explains: imports for ALL channels when shift+tab is `@all`, for the selected channel when shift+tab has one, or for `@handle` when `for @handle` is given.
- [ ] T11.2 `import game --help` — `Usage: import game [game title]`; explains: opens the IGDB import Sidebar with the title prefilled (if given) and runs an IGDB search.

## Phase 12 — Fix `import videos` / `import game` implementation

Real behavior is currently wrong (hallucinated). Fix to match the above.

- [x] T12.1 Fix `import videos` — implemented the missing `for @handle` override (parses `for @handle`, overrides shift+tab scope; unknown → error); @all/blank → all channels. complexity: [high]
- [x] T12.2 Fix `import game` — added the game branch → opens the IGDB import Sidebar with the optional title prefilled (mirrors `/games import`; chat-controller fast-path opens it in prod). complexity: [high]

## Phase 13 — `sync videos --help` / `sync channels --help`

Same man style. Copy from `Pito::Copy`. The `with <items>` clause is a parsed comma-list
built to be extensible (today `videos`; future `analytics` for both forms).

- [ ] T13.1 `sync videos --help` — `Usage: sync videos [only id,id,id]`; scope = shift+tab channel (`@all` = all channels); `only` takes one or more **local numeric ids** (comma-separated, **no titles**). (Future: optional `with analytics` — not now.)
- [ ] T13.2 `sync channels --help` — `Usage: sync channels [with <items>]`; scope = shift+tab channel (`@all` = all channels); `with` is a comma-list of sync targets (today `videos`; future `analytics`) — e.g. `with videos`, `with videos,analytics`.

## Phase 14 — Rework `sync` implementation (drop `sync game` + legacy forms)

New `sync` = exactly two forms. **Drop completely** (code, specs, comments, copy,
confirmations): `sync game <ref>` (use `import game` to resync instead), the single
`sync video <ref>` path, and the hardcoded `sync channel` / `sync channel with videos`
forms.

- [x] T14.1 `sync videos [only id,id,id]` — scope by shift+tab (`@all` = all channels); optional `only <ids>` = local numeric ids (comma-separated, no titles). Removed the old single-video path. complexity: [high]
- [x] T14.2 `sync channels [with <items>]` — scope by shift+tab; optional `with <items>` parsed via a vocab map (today `videos`; extensible to `analytics`, not hardcoded). Removed the old hardcoded channel forms + `sync game` (confirmation builders + executor branches + copy). complexity: [high]

## Phase 15 — `footage game --help`

Same man style. Copy from `Pito::Copy`.

- [ ] T15.1 `footage game --help` — `Usage: footage game <id> <path>`; `<id>` = local game id (plain number, **no title**); `<path>` = local folder where the footage is stored.

## Phase 16 — Rework `footage game` implementation (id only, no title)

Current `footage <ref> <path>` accepts a title and uses a bare ref — not aligned. Rework to
the explicit `footage game <id> <path>` form: require a **local game id** (drop title ILIKE
resolution); keep the path. Drop misaligned code/specs/comments/copy per the global rule.

- [x] T16.1 Rework `footage game <id> <path>` — resolve game by local id only (no title); keep the local footage path; drop the title-resolution path and align copy/specs.

## Phase 17 — `delete game --help` / `delete video --help`

Same man style. Copy from `Pito::Copy`. Both accept a **local id only** (plain number, no
`#`) — **never a title**. (Implementation rework to enforce id-only is deferred — `--help`
man pages only for now.)

- [ ] T17.1 `delete game --help` — `Usage: delete game <id>`; `<id>` = local game id (plain number, no title).
- [ ] T17.2 `delete video --help` — `Usage: delete video <id>`; `<id>` = local video id (plain number, no title).

## Phase 18 — Rework `delete game` / `delete video` implementation (id only)

Current `delete` accepts title or `#id` — not aligned. Rework to **local id only** (plain
number, never title). Drop title resolution + misaligned copy/specs per the global rule.

- [x] T18.1 Rework `delete game <id>` — resolve by local id only (drop title); align copy/specs. (Added reusable `id_only_resolution!` flag to `TargetResolution`.)
- [x] T18.2 Rework `delete video <id>` — resolve by local id only (drop title); align copy/specs.

## Phase 19 — `reindex game --help` / `reindex video --help`

Same man style. Copy from `Pito::Copy`. Both accept a **local id only** (plain number, no
`#`) — **never a title**.

- [ ] T19.1 `reindex game --help` — `Usage: reindex game <id>`; `<id>` = local game id (re-embed in Voyage).
- [ ] T19.2 `reindex video --help` — `Usage: reindex video <id>`; `<id>` = local video id (re-embed in Voyage).

## Phase 20 — Rework `reindex game` / `reindex video` implementation (id only)

Rework to **local id only** (never title). Drop title resolution + misaligned copy/specs.

- [x] T20.1 Rework `reindex game <id>` — resolve by local id only (drop title); align copy/specs.
- [x] T20.2 Rework `reindex video <id>` — resolve by local id only (drop title); align copy/specs.

## Phase 21 — `publish` / `unlist` / `schedule` video `--help`

Same man style. Copy from `Pito::Copy`. All accept a **local video id only** (plain number,
no `#`) — **never a title**.

- [ ] T21.1 `publish video --help` — `Usage: publish video <id>`; `<id>` = local video id (sets YouTube visibility public).
- [ ] T21.2 `unlist video --help` — `Usage: unlist video <id>`; `<id>` = local video id (sets YouTube visibility unlisted).
- [ ] T21.3 `schedule video --help` — `Usage: schedule video <id> <date>`; `<id>` = local video id; `<date>` = `dd-mm-yyyy hh:mm`, **local time**, at least **30 min** from now.

## Phase 22 — Rework `publish` / `unlist` / `schedule` video implementation (id only)

Rework to **local video id only** (never title). Drop title resolution + misaligned
copy/specs per the global rule.

- [x] T22.1 Rework `publish video <id>` — resolve by local id only; align copy/specs.
- [x] T22.2 Rework `unlist video <id>` — resolve by local id only; align copy/specs.
- [x] T22.3 Rework `schedule video <id> <date>` — local video id only; date `dd-mm-yyyy hh:mm` parsed in the **app local zone** (`Time.zone`, currently `UTC`), ≥30 min from now; stored/sent UTC; displayed local. **No per-channel tz column.** Align copy/specs.

## Phase 23 — `link`/`unlink` `game`/`video` `--help`

Same man style. Copy from `Pito::Copy`. Both sides are **local ids only** (plain numbers,
no `#`, never titles). `link` connector = `to`; `unlink` connector = `from`.

- [ ] T23.1 `link game --help` — `Usage: link game <id> to video <id>` (e.g. `link game 12 to video 32`).
- [ ] T23.2 `link video --help` — `Usage: link video <id> to game <id>`.
- [ ] T23.3 `unlink game --help` — `Usage: unlink game <id> from video <id>` (e.g. `unlink game 12 from video 32`).
- [ ] T23.4 `unlink video --help` — `Usage: unlink video <id> from game <id>`.

## Phase 24 — Rework `link` / `unlink` implementation (local ids only)

Current `link`/`unlink` take a free body (titles/refs) — not aligned. Rework to two-sided
**local-id** forms: `link game <id> to video <id>` / `link video <id> to game <id>`;
`unlink game <id> from video <id>` / `unlink video <id> from game <id>`. Drop title/ref
resolution + misaligned copy/specs per the global rule.

- [x] T24.1 Rework `link` — parse `game <id> to video <id>` / `video <id> to game <id>` (local ids only); link the pair; align copy/specs.
- [x] T24.2 Rework `unlink` — parse `game <id> from video <id>` / `video <id> from game <id>` (local ids only); unlink the pair; align copy/specs.

## Phase 25 — Repurpose `add` / `remove` → list-column mutation (game_list/video_list)

`add` / `remove` are **list**-hashtag actions that add/remove COLUMNS on `game_list` /
`video_list`. They mutate the SAME list message (`:mutate`) and **do NOT consume** the
handle, so `#<list-handle> add …` / `remove …` can run repeatedly. Columns, ghost, and
`--help` use the exact `with`-column vocab (`Game::ListColumns` / `Video::ListColumns`).
These are the only user-facing repeatable (non-consuming) follow-ups (theme_list/game_enhanced
dropped; channel_visit internal).

SEPARATE from `confirm` / `cancel`, which belong to the **confirmation** hashtag kind
(`#confirmation-hashtag`, its own target + Phase 36) — do not mix the two. The old
`Normalizer` / `confirmation_handle` add/remove-**metrics** ops (if still present) are a
distinct dead path; drop them on their own (T25.6), not as the basis for column add/remove.

Ordering: do T25.1/T25.2 **with or right after** Phases 31 & 33 (game_list/video_list
follow-up handlers) so those handlers are edited once; T25.4 after Phase 35 (hashtag `--help`
infra).

- [ ] T25.1 Implement `add <columns>` / `remove <columns>` as `game_list` + `video_list` follow-up actions (`:mutate`, non-consuming) that re-render the SAME list message with columns added/removed; columns via the `with`-column vocab (game vs video by kind); ignore unknown/dupes. complexity: [high]
- [ ] T25.2 Extend follow-up dispatch for **per-action** consume behavior — one target (`game_list`/`video_list`) carries `:append` consuming actions (show/delete) AND `:mutate` non-consuming actions (add/remove). complexity: [high]
- [ ] T25.3 Ghost: after `#<list-handle> add ` / `remove `, suggest the exact `with` columns (reuse the `with`-column ghost vocab; game vs video by kind). complexity: [high]
- [ ] T25.4 `add --help` / `remove --help` (man style, hashtag copy) on `#list-games-hashtag` + `#list-videos-hashtag` — `Usage: add <columns>` / `remove <columns>`, columns = the with-column list. (Depends on Phase 35.) complexity: [low]
- [ ] T25.5 Specs: repeated add/remove mutate columns WITHOUT consuming the handle; show/delete still consume; ghost suggests columns; `--help` renders; game vs video vocab correct. complexity: [high]
- [ ] T25.6 Drop the legacy `Normalizer`/`confirmation_handle` add/remove-**metrics** segment-edit ops if dead (verify unused first) — separate from the column add/remove and from confirm/cancel; no leftovers. complexity: [high]

## Phase 26 — Remove themes from chat verbs (`/themes` Sidebar stays)

`/themes` is a slash command that already opens the Sidebar, and the Sidebar does preview/apply.
This phase ONLY removes themes from the chat/hashtag side — the `theme_list` follow-up
(preview/apply on a chat message) + its chat message + confirmation. The `/themes` Sidebar is
untouched and remains the sole preview/apply UX.

- [x] T26.1 Verified the `/themes` Sidebar does preview+apply on its own; dropped the `theme_list` follow-up + `Theme::List` builder + the `/themes list` chat path (now opens the Sidebar) + copy/grammar/specs. Bare/`list`/`ls` `/themes` all open the Sidebar. complexity: [high]

## Phase 27 — `#list-channels-hashtag` (visit only; drop reindex)

Hashtag replies to a channel list. Keep ONLY `visit`; drop `reindex`. `visit` takes a
channel **@handle** (never an id). `consume` (channel_visit) stays internal — triggered by
`visit`, never exposed as a verb/grammar/help. Man-style `--help`, copy from `Pito::Copy`.
(Depends on shared hashtag `--help` routing/ghost infra — see note below.)

- [ ] T27.1 `#list-channels-hashtag visit --help` — man style; `Usage: visit @handle`; `@handle` = channel handle (**never id**). Copy from `Pito::Copy`.
- [ ] T27.2 Drop the `reindex` action from `channel_list` — code, specs, comments, copy, grammar. Leaves `visit` as the only action.
- [ ] T27.3 `visit @handle` impl — resolve by channel **@handle** only (never id); visit as today; keep `consume` internal/hidden behind `visit`; align wording (visit, not consume).

## Phase 28 — Drop `#id` row from `Channel::ItemComponent`

The `#<id>` line under each channel card is rendered by the shared
`Pito::Channel::ItemComponent` (used by the `list channels` strip AND the game-detail
enhanced message). Remove it from the component itself so it disappears from both.

- [x] T28.1 Remove the `#id` row from `Pito::Channel::ItemComponent` (drop from the component → both `list channels` and the game-detail enhanced message); update specs.

## Phase 29 — Drop `game_enhanced` follow-up (no hashtag on the Enhanced message)

`game_enhanced` (actions `reindex`, `channel`) is not follow-up-able anymore. The Enhanced
(recommendations) message no longer gets a reply handle / hashtag.

- [x] T29.1 Remove the `game_enhanced` follow-up handler (`reindex`, `channel`); stop stamping the Enhanced message as follow-up-able (no `reply_handle`/hashtag); drop related code, specs, comments, copy, grammar. complexity: [high]

## Phase 30 — Make `channel_visit`/`consume` internal-only (hide hashtag, keep flow)

`consume`/`channel_visit` is a machine flow (auto-visit JS → `Channels::VisitsController#consume`
→ mutate visit message to `:visited`). Keep it working, but make it fully invisible to the
user: no `#handle` shown on the visit message, `consume` not typeable, and
`channel_visit`/`consume` excluded from the `#hashtag` palette + `#help`.

Solution = EXTEND the follow-up mechanism (additive), do NOT change the shared path the
other follow-upables use (game_detail / game_list / video_* / channel_list / confirmation
keep their hashtags, palette entries, and `#help` untouched):

- [x] T30.1 Added `internal` flag to the follow-up handler DSL (`self.internal true` on `ChannelVisit`); `Help::FollowUpActions` skips internal handlers (gone from `#help`/palette). complexity: [high]
- [x] T30.2 Dropped `make_followupable!` from the visit message (no `reply_handle`); kept `reply_target` + new `anchor: true` payload flag so `dom_id` still renders `event_<id>`; consume already routes by `event.id`. Visiting→visited intact. complexity: [high]
- [x] T30.3 Specs: visit message has no handle but keeps its anchor; `channel_visit` absent from `#help`; other targets unchanged; consume flow still flips to :visited. complexity: [low]

## Phase 31 — `#list-videos-hashtag` (show / delete video)

Hashtag replies to a video list. Actions: `show`, `delete`/`rm`. Entity (video) inferred
from the target — usage omits the noun. Both take a **local id only** (plain number, never
title). Man-style `--help`, hashtag copy (`pito.copy.hashtag_help.*`).

- [ ] T31.1 `#list-videos-hashtag show --help` — `Usage: show <id>`; `<id>` = local video id (never title).
- [ ] T31.2 `#list-videos-hashtag delete --help` — `Usage: delete <id>` (alias `rm`); `<id>` = local video id (never title).
- [ ] T31.3 Impl `show <id>` — resolve the video by local id only (never title); align copy/specs.
- [ ] T31.4 Impl `delete <id>` / `rm` — resolve the video by local id only (never title); align copy/specs.

## Phase 32 — `#show-video-hashtag` (delete / reindex / link / unlink video)

Hashtag replies to a video **detail** — the video is the subject (implied by the target),
so actions take **NO primary id**; only the cross-entity `game` id stays in link/unlink.
`link` uses `to`, `unlink` uses `from`. Man-style `--help`, hashtag copy.

- [ ] T32.1 `#show-video-hashtag delete --help` — `Usage: delete` (alias `rm`); deletes this video.
- [ ] T32.2 `#show-video-hashtag reindex --help` — `Usage: reindex`; Voyage re-embed of this video.
- [ ] T32.3 `#show-video-hashtag link --help` — `Usage: link to game <id>`; links this video to a game (local id, e.g. `link to game 7`).
- [ ] T32.4 `#show-video-hashtag unlink --help` — `Usage: unlink from game <id>`; local game id.
- [ ] T32.5 Impl `delete` / `rm` — delete the detail's video (resolved from the source event); align copy/specs.
- [ ] T32.6 Impl `reindex` — re-embed the detail's video; align copy/specs.
- [ ] T32.7 Impl `link to game <id>` — link the detail's video to the given local game id; align copy/specs.
- [ ] T32.8 Impl `unlink from game <id>` — local game id; align copy/specs.

## Phase 33 — `#list-games-hashtag` (show / delete)

Hashtag replies to a game list. Actions: `show`, `delete`/`rm`. Both take a **local game id
only** (plain number, never title). Man-style `--help`, copy from `Pito::Copy`.

- [ ] T33.1 `#list-games-hashtag show --help` — `Usage: show <id>`; `<id>` = local game id (never title).
- [ ] T33.2 `#list-games-hashtag delete --help` — `Usage: delete <id>` (alias `rm`); `<id>` = local game id (never title).
- [ ] T33.3 Impl `show <id>` — resolve by local game id only (never title); align copy/specs.
- [ ] T33.4 Impl `delete <id>` / `rm` — resolve by local game id only (never title); align copy/specs.

## Phase 34 — `#show-game-hashtag` (delete / footage / link / unlink; drop resync)

Hashtag replies to a game detail. Keep `delete`/`rm`, `footage`, `link`, `unlink`, and
**`reindex`** (Voyage re-embed); **drop `resync`** (re-importing an existing game via
`import game` re-fetches IGDB and preserves video↔game links + footages — verified in
`sync_game.rb`). All ids are **local** (plain numbers, never titles). `link` uses `to`,
`unlink` uses `from`. Man-style `--help`, copy from `Pito::Copy`.

Game **detail** — the game is the subject (implied by the target), so actions take **NO
primary id**; only the cross-entity `video` id stays in link/unlink. `link` uses `to`,
`unlink` uses `from`.

- [ ] T34.1 `#show-game-hashtag delete --help` — `Usage: delete` (alias `rm`); deletes this game.
- [ ] T34.2 `#show-game-hashtag footage --help` — `Usage: footage <path>`; local footage path for this game.
- [ ] T34.3 `#show-game-hashtag link --help` — `Usage: link to video <id>`; links this game to a video (local id, e.g. `link to video 5`).
- [ ] T34.4 `#show-game-hashtag unlink --help` — `Usage: unlink from video <id>`; local video id.
- [ ] T34.5 Drop the `resync` action from `game_detail` — remove the action + the `game_resync` confirmation/executor path + copy/specs/comments (per the global drop rule). Keep rm/delete, footage, link, unlink, reindex.
- [ ] T34.6 Impl `delete` / `rm` — delete the detail's game (resolved from the source event); align copy/specs.
- [ ] T34.7 Impl `footage <path>` — set the footage path for the detail's game; align copy/specs.
- [ ] T34.8 Impl `link to video <id>` — link the detail's game to the given local video id; align copy/specs.
- [ ] T34.9 Impl `unlink from video <id>` — local video id; align copy/specs.
- [ ] T34.10 `#show-game-hashtag reindex --help` — `Usage: reindex`; Voyage re-embed of this game.
- [ ] T34.11 Impl `reindex` as a `game_detail` action — re-embed the detail's game in Voyage (reuse the existing reindex/Voyage confirmation path); align copy/specs.

## Phase 35 — Hashtag `--help` infra (prerequisite for 27/31–34)

The hashtag equivalent of Phase 7's chat infra. Reuses the shared `ManPage` renderer.
**Must land before** the per-target hashtag `--help` tasks (Phases 27/31/32/33/34).
**Both granularities:** `#<handle> --help` → a TARGET page listing all the target's actions;
`#<handle> <action> --help` → a single ACTION page.

- [ ] T35.1 `Pito::MessageBuilder::HashtagHelp.call(target:, action: nil)` — `action: nil` → TARGET man page (Usage + an `Actions:` list of the target's actions). `action:` given → that single action's page. Reads the target's actions (FollowUp registry / handler `actions`) + `pito.copy.hashtag_help.<indicator>` (incl. per-action copy); usage shaped list-vs-detail (list → `<action> <id>`, detail → `<action>` / cross-entity refs). Returns nil for internal/unknown targets/actions. complexity: [high]
- [ ] T35.2 Route in the SINGLE follow-up path (`FollowUp::Router` → `ChatController#handle_follow_up`, which already resolves handle → event → `reply_target`): if `rest == "--help"` → `HashtagHelp.call(target:)` (target page); if `rest` matches `<action> --help` → `HashtagHelp.call(target:, action:)` (action page); else normal `FollowUpDispatchJob`. (Not the legacy `Reply`/`confirmation_handle` path.) Internal (channel_visit) / dropped targets never reach here. complexity: [low]
- [ ] T35.3 Hashtag `-`→`--help` ghost — extend the hashtag suggestion path (engine hashtag mode + JS) so typing `-`/`--h` after a `#<handle>` (or its action) ghosts `--help`. complexity: [high]
- [ ] T35.4 Specs (Rails + vitest): `HashtagHelp` renderer per target; `#<handle> --help` routing; the `-`→`--help` hashtag ghost. complexity: [high]

## Phase 36 — `#confirmation-hashtag` `--help` (man style)

`confirmation` is its **own hashtag kind** (`#confirmation-hashtag`), actions `confirm` /
`cancel` (no args — detail-like, no id). Its `--help` **shares the man style** with the
other hashtag `--help` (via `HashtagHelp` / `ManPage`) — not witty. Copy from
`pito.copy.hashtag_help.confirmation`. (Depends on Phase 35.)

- [ ] T36.1 `#confirmation-hashtag --help` — man style; `Usage: confirm | cancel`; Actions: `confirm` (run the pending action; aliases yes/ok/approve/true), `cancel` (abort it; aliases no/false/discard). No args; list the aliases. Copy from `Pito::Copy`. complexity: [low]
- [ ] T36.2 Expand `ACTION_ALIASES` in `follow_up/handlers/confirmation.rb` — confirm ← {confirm, yes, ok, approve, true, y}; cancel ← {cancel, no, false, discard, n}. Update specs. complexity: [low]

## Phase 37 — Final verification (CI runs the WHOLE suite)

- [ ] T37.1 Confirm CI runs the FULL `bundle exec rspec` + `npm test` (not a silently-sharded or partial subset that drops files); the CI example count matches the local full-suite baseline (T0.1). If CI runs a subset, fix the CI config. complexity: [low]
- [ ] T37.2 Final full `bundle exec rspec` + `npm test` + `bin/rubocop` + `node --check`; all green; count == baseline (± intended new specs). complexity: [manual]

## Phase 38 — Chat `--help` noun-aware infra (CommandHelp v2, both levels)

Supersedes Phase 7's single-verb `--help`. **Prerequisite** for the noun-split chat `--help`
phases (9/11/13/17/19/21/23). Mirrors the hashtag "both levels" decision: bare `<verb> --help`
lists the noun forms; `<verb> <noun> --help` shows the specific page. Single-entity verbs
(publish/unlist/schedule = video; footage = game) have one form, so verb-level == that form.

- [ ] T38.1 Rework `Pito::MessageBuilder::CommandHelp.call(verb, noun: nil)` — `noun: nil` → verb-level page listing the noun forms (`<verb> game …` / `<verb> video …`); `noun:` given → that noun's page. complexity: [high]
- [ ] T38.2 Restructure `pito.copy.chat_help.*` → `chat_help.<verb>.<noun>` (+ a verb-level usage/intro); REWRITE the 11 existing Phase 7 keys (id-only, no `#`, no `<title>`); update `command_help_spec`. complexity: [high]
- [ ] T38.3 Dispatcher: parse the noun from `<verb> <noun> --help` (and bare `<verb> --help`) and pass it to `CommandHelp`. Ensure the `-`→`--help` ghost (Phase 7 T7.3) also fires at `<verb> <noun> -`. complexity: [low]
- [ ] T38.4 Specs: `delete --help` lists game+video forms; `delete game --help` = game page; bare verb-level for single-entity verbs == their one form. complexity: [low]

## Verification (end-to-end)

- `bundle exec rspec` green; `bin/rubocop` clean; `npm test` (vitest) green; `node --check` on the touched JS.
- Manual (via `/run` or dev server): in the shell type —
  - `list games` → clean 2-col table.
  - `list games with developer, publisher, genres, release date, year, platforms` → single wrapping table (not a vertical stack); Release reads "June 09, 2026"; Platform reads "PlayStation, Switch, Steam" with no Xbox/Google/Mac/PC.
  - Type `list games ` → ghost " with"; `list games with ` → ghost "platform"; cycle remaining field tokens; confirm "channels" never appears as a `with` field. (Bare `list ` still ghosts "channels" — intentional, unchanged.)
