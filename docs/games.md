# Games domain — repurpose the IGDB backend (+ Stat / Stack / Suggestions)

> Status: in progress. Branch `themes` (folded into PR #62; **do not merge until
> the user validates**). No co-author trailers; no `[skipci]`.

## Sign-off

- [x] Drafted — 2026-06-06
- [ ] Audited — _pending_

## North star

Turn games into a real domain: chat verbs (`list games`, `show game <title>`,
`delete game <title>`) + a `/games import` IGDB-search sidebar + repliable
follow-ups + recommendations — repurposing the working IGDB backend, storing
**all** IGDB genres, and wiring the built-but-unused score/TTB/cover components.
Alongside it: a polymorphic **`Stat`** model (subscribers/views), a **`Pito::Stack`**
API-usage/local tracking engine, the rebaptized **`Pito::Suggestions`** engine
(with game-title ghosting), and removal of the phantom video/analytics dead code.
No production data exists → destructive migrations are free.

## Locked decisions

| Topic              | Decision                                                                                                                                                                                                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Branch / PR        | Continue on `themes` / PR #62; **never merge** until validated                                                                                                                                                                                                               |
| Rename `/themes`   | `/theme` → `/themes` (verb, fast-path, grammar, help/palette, i18n, specs, docs)                                                                                                                                                                                             |
| Follow-up engine   | Keep the name **`Pito::FollowUp`** (no rename)                                                                                                                                                                                                                               |
| Suggestions engine | `Pito::Autocomplete::*` → **`Pito::Suggestions::*`**, `pito--autosuggest` → `pito--suggestions`, route `/autocomplete` → `/suggestions`, **all `pito-autosuggest-*` CSS → `pito-suggestions-*`** (full). New: game-title argument ghosting.                                  |
| Command surface    | Chat verbs (repliable): `list games`/`ls games`, `show game <title>`, `delete game <title>`/`rm game <title>`. Slash: `/games import [title]` (IGDB search sidebar).                                                                                                         |
| Genres             | Drop `PrimaryGenrePicker` + `primary_genre_id`; store **all** IGDB genres (`game_genres`, keep `position`)                                                                                                                                                                   |
| Editions           | Drop `version_parent_id` + `version_title` + version-parent resolution; **main titles only** (`game_type=(0)`)                                                                                                                                                               |
| Game schema        | Add `games.last_sync_error`, `games.resyncing`; **wire** `games.platforms[]`; drop dead `games.notes`, `games.played_at`                                                                                                                                                     |
| Stats              | Polymorphic **`Stat`**(`entity_type`/`entity_id`, `kind`, `value`, `synced_at`); kinds **`subscribers`, `views`**; `Pito::Stats` facade; move off Channel/Video columns                                                                                                      |
| watched_hours      | **Dropped now** (Analytics-sourced) → future `Pito::Analytics`; remove `channels.watched_hours` + its Analytics fetch                                                                                                                                                        |
| Game stats         | `views` **materialized** via a refresh job (sum of `linked_videos` views)                                                                                                                                                                                                    |
| Stack              | **`Pito::Stack`** engine + tracking ONLY (no UI): `api_requests` table; instrument Voyage/IGDB/YouTube chokepoints; `Stack::{Voyage,YouTube,IGDB}` = request counts (24h + month); `Stack::Local` = Postgres MB + Game/Video counts. Replaces `Pito::ExternalApiTracker::*`. |
| Search             | Modular `Pito::Search` registry + base module + **IGDB game-search module** (port `Client#search_games`). Local search + a `search` chat verb deferred to **after Video**.                                                                                                   |
| Embeddings         | Game multi-field (title+genres+dev+pub+description+platforms+ttb+ratings, shared `Game::EmbedText`); Channel (title+desc+handle+keywords+tags) — add `channels.summary_embedding`+`keywords`+`tags`; **diff-gated** reindex (cover-art change must NOT reindex)              |
| Footage/TTB        | Keep `pito:tools:probe` + `Footage`; footage hours = `sum(footages.duration_seconds)/3600` → `TimeToBeatComponent` **4th** tick                                                                                                                                              |
| Recommendations    | Real `#similar`/`#channel` (multi-field + filters, `ScoreBarComponent`); import step-5 = dummy `Pito::Recommendations` → true                                                                                                                                                |
| Platform ownership | Tokens `ps/switch/steam`; synonyms ps4/ps5/PlayStation→ps, Switch1/2→switch, Steam/GOG/Epic/PC→steam                                                                                                                                                                         |
| Sync timing        | IGDB sync on add; future-release games re-sync **daily at 1:00**; stop once released                                                                                                                                                                                         |
| Dead code          | Remove phantom video/analytics layer (keep `Video` model + operational `ImportVideosJob` + `Voyage::Stats` + working channel sync)                                                                                                                                           |

## Complexity hints

`[manual]` operator (smoke/commits) · `[low]` mechanical/established-pattern · `[high]` architectural/cross-cutting.

## Phase index

- P0 — Rename `/theme` → `/themes`
- P1 — Rename autocomplete engine → `Pito::Suggestions` (full, incl. CSS)
- P2 — Games schema reconcile + genre→genres + games dead-code
- P3 — Remove phantom video/analytics dead code (keep Video model)
- P4 — Polymorphic `Stat` model + `Pito::Stats` (subscribers/views)
- P5 — `Pito::Stack` engine + API-usage/local tracking (no UI)
- P6 — Modular search + IGDB game-search module
- P7 — IGDB sync repair + verification (+ sync-on-add)
- P8 — Multi-field game embedding + channel embedding + diff-gated reindex
- P9 — Game detail message component (ScoreBar + TTB-with-footage + cover)
- P10 — Chat verbs `list/show/delete games` + grammar + title ghost + list follow-up + picker
- P11 — `/games import` sidebar (search → 5-step progress → 2 messages)
- P12 — Follow-ups on the game messages
- P13 — `Pito::Recommendations` (similar / channel)
- P14 — Daily future-games sync (1:00)
- P15 — Extract to `docs/games.md`, AGENTS conventions, finalize

---

## P0 — Rename `/theme` → `/themes`

- [x] T0.1 Set `Pito::Slash::Handlers::Theme.verb = :themes`; update verb literals + `description_key`. complexity: [low]
- [x] T0.2 Update the slash vocabulary/registry + `Pito::Suggestions` catalog so `/themes` resolves; `/theme` no longer resolves. complexity: [low]
- [x] T0.3 `ChatController`: rename `bare_theme_command?` → `bare_themes_command?`, regex `\A/themes\z`. complexity: [low]
- [x] T0.4 Update `/help` sections + ctrl+k palette + descriptions i18n → `/themes`. complexity: [low]
- [x] T0.5 Update theme specs → `/themes`; keep `list/ls/preview/apply/reset` + `#<handle>` follow-ups passing. complexity: [low]
- [x] T0.6 Update `docs/themes.md` + `docs/validations.md` references → `/themes`. complexity: [low]
- [x] T0.7 `bundle exec rspec` + `bin/rubocop` green. complexity: [manual]
- [x] T0.8 Commit: `Rename /theme command to /themes`. complexity: [manual]

## P1 — Rename autocomplete engine → `Pito::Suggestions` (full)

- [x] T1.1 Rename `app/services/pito/autocomplete/{engine,catalog}.rb` → `suggestions/*`; `Pito::Autocomplete` → `Pito::Suggestions`. complexity: [low]
- [x] T1.2 Update Ruby refs: `AutocompleteController`, `chatbox_component.rb`, `Pito::Palette::Autocomplete::Component` → `Pito::Palette::Suggestions::Component` (+ dir). complexity: [low]
- [x] T1.3 Route `/autocomplete` → `/suggestions`; rename controller; update the catalog `endpoint:` string. complexity: [low]
- [x] T1.4 JS: `autosuggest_controller.js` → `suggestions_controller.js` (`pito--suggestions`); update all data-attrs in `chatbox_component.html.erb` + comments; POST `/suggestions`. complexity: [high]
- [ ] T1.5 CSS: `.pito-autosuggest-*` → `.pito-suggestions-*` (CSS + ERB + `history_controller.js` selector + specs); rebuild Tailwind. complexity: [low]
- [ ] T1.6 i18n: rename `pito.shell.autocomplete_*` keys. complexity: [low]
- [ ] T1.7 Rename specs (services/request/JS/palette) + all refs. complexity: [low]
- [ ] T1.8 `bundle exec rspec` + `npm test` + `bin/rubocop` + `node --check` + `zeitwerk:check` green. complexity: [manual]
- [ ] T1.9 Commit: `Rename autocomplete engine to Pito::Suggestions (full)`. complexity: [manual]

## P2 — Games schema reconcile + genre→genres + games dead-code

- [ ] T2.1 Migration: drop `games.primary_genre_id` (+ index + FK), `games.notes`, `games.played_at`. complexity: [low]
- [ ] T2.2 Migration: add `games.last_sync_error:text`, `games.resyncing:boolean null:false default:false`. complexity: [low]
- [ ] T2.3 Remove `app/services/game/primary_genre_picker.rb` + refs. complexity: [low]
- [ ] T2.4 `Game`: remove `belongs_to :primary_genre`; keep `has_many :genres, through: :game_genres`. complexity: [low]
- [ ] T2.5 `SyncGame`: remove `re_assign_primary_genre` + `resolve_version_parent_id`/`attrs[:version_parent_id]`. complexity: [high]
- [ ] T2.6 `GameMapper`: remove `version_title` + `hours_of_footage_manual`; keep `game_genres.position`. complexity: [low]
- [ ] T2.7 Delete orphaned `app/queries/games/filter.rb`. complexity: [low]
- [ ] T2.8 `Game`: define only the used scopes (`upcoming`/`unreleased`); remove dead scope callers. complexity: [low]
- [ ] T2.9 Fix `ScoreBarComponent` `resyncing?`. complexity: [low]
- [ ] T2.10 `db:migrate`; update specs; `bundle exec rspec` + `bin/rubocop` + `zeitwerk:check` green. complexity: [manual]
- [ ] T2.11 Commit: `Games schema reconcile + store all genres + remove games dead code`. complexity: [manual]

## P3 — Remove phantom video/analytics dead code (keep Video model)

- [ ] T3.1 Re-confirm each phantom target has no table/model (grep vs schema). complexity: [low]
- [ ] T3.2 Remove analytics-sync chain + specs (`ChannelAnalyticsSync`, `VideoAnalyticsSync`, `VideoRetentionSync`(+Orchestrator), `VideoViewerTimeSyncJob`, `ViewerTimeDailyRefreshJob`, `YoutubeAnalyticsSync`). complexity: [high]
- [ ] T3.3 Remove `Pito::Analytics::ViewerTimeRollup` + `VideoViewerTimeBucket`/`time_zone` refs; clean/remove `CrossVideoLocals`/`DataFreshness`. complexity: [high]
- [ ] T3.4 Remove `AnalyticsController` + `channels/analytics_controller.rb` + routes/views. complexity: [low]
- [ ] T3.5 Remove phantom import stack (`ImportJob`/`RejectedVideoImport` refs, `Channel::ImportVideosJob`, `Channel::VideoImporter`, `imports/channels_controller.rb` + route); keep `ImportVideosJob`. complexity: [high]
- [ ] T3.6 Remove `Video::ThumbnailPreview`. complexity: [low]
- [ ] T3.7 Strip phantom-column writes (`videos.last_sync_error`/`made_for_kids_effective`; `video_stats` refs). complexity: [high]
- [ ] T3.8 Remove the phantom `YoutubeApiCall`-based tracker/quota reads (superseded by P5) or guard; clean `config/recurring.yml`. complexity: [high]
- [ ] T3.9 `zeitwerk:check` + boot clean; remove dead specs; `bundle exec rspec` + `bin/rubocop` green. complexity: [manual]
- [ ] T3.10 Commit: `Remove phantom video/analytics dead code (keep Video model)`. complexity: [manual]

## P4 — Polymorphic `Stat` model + `Pito::Stats`

- [ ] T4.1 Migration: `stats`(`entity_type`,`entity_id`,`kind`,`value:bigint`,`synced_at`); unique `(entity_type,entity_id,kind)`. complexity: [low]
- [ ] T4.2 `Stat` model: polymorphic `entity`; `KINDS=%w[subscribers views]`; validations. complexity: [low]
- [ ] T4.3 `Channel`/`Video`/`Game`: `has_many :stats, as: :entity` + readers. complexity: [low]
- [ ] T4.4 `Pito::Stats` facade: `get`/`set`(upsert+synced_at)/`for`. complexity: [high]
- [ ] T4.5 Migration: drop `channels.{subscriber_count,view_count,watched_hours}`, `videos.view_count`. complexity: [low]
- [ ] T4.6 `StatsFetcher`: drop watched_hours Analytics call; subs+views only. Channel sync jobs write via `Pito::Stats.set`. complexity: [high]
- [ ] T4.7 `ImportVideosJob`: write video `views` via `Pito::Stats.set`. complexity: [low]
- [ ] T4.8 Update readers of dropped columns → `Pito::Stats`. complexity: [high]
- [ ] T4.9 `Game::StatsRefresh` + `GameStatsRefreshJob`: game `views` = sum(`linked_videos` views); enqueue on import/sync/link-change. complexity: [high]
- [ ] T4.10 Specs: model, facade, writes, game aggregate; `bundle exec rspec` + `bin/rubocop` green. complexity: [low]
- [ ] T4.11 Commit: `Polymorphic Stat model + Pito::Stats (subscribers/views); drop watched_hours`. complexity: [manual]

## P5 — `Pito::Stack` engine + tracking (no UI)

- [ ] T5.1 Migration: `api_requests`(`provider`,`endpoint`,`units:integer null`,`created_at`); index `(provider, created_at)`. complexity: [low]
- [ ] T5.2 `ApiRequest` model + scopes `last_24h`/`this_month` + prune helper. complexity: [low]
- [ ] T5.3 `Pito::Stack` + `Stack::{Voyage,YouTube,IGDB}`: `requests_24h`, `requests_month`. complexity: [high]
- [ ] T5.4 `Pito::Stack::Local`: `db_size_mb` + record counts `{videos:,games:}`. complexity: [low]
- [ ] T5.5 Instrument chokepoints (Voyage `post_embeddings*`; IGDB `Client#post`; YouTube `Auditor#write_audit_row` + direct writers) → `ApiRequest`. complexity: [high]
- [ ] T5.6 Replace `Pito::ExternalApiTracker::*` with `Pito::Stack` reads (or remove + repoint). complexity: [low]
- [ ] T5.7 Specs: scopes, module counts, Local size/counts, instrumentation (stubbed HTTP). complexity: [low]
- [ ] T5.8 `bundle exec rspec` + `bin/rubocop` + `zeitwerk:check` green. complexity: [manual]
- [ ] T5.9 Commit: `Pito::Stack: API-usage + local Postgres tracking`. complexity: [manual]

## P6 — Modular search + IGDB game-search module

- [ ] T6.1 `Pito::Search::Module` base (`#call(query:, **opts)` → `{hits:,total:,error:}`). complexity: [low]
- [ ] T6.2 `Pito::Search::Registry` (register/for/reset!) replacing `Omnisearch::AREAS`. complexity: [high]
- [ ] T6.3 `Pito::Search::Modules::IgdbGames` wrapping `Client#search_games` + error envelope. complexity: [high]
- [ ] T6.4 Fold/retire `Game::SearchService`; leave local `SearchGames` for the deferred path. complexity: [low]
- [ ] T6.5 Specs (WebMock): main-only, coverless, denoise, error envelope, registry. complexity: [low]
- [ ] T6.6 Commit: `Modular search registry + IGDB game-search module`. complexity: [manual]

## P7 — IGDB sync repair + verification (+ sync-on-add)

- [ ] T7.1 Make `SyncGame#call` run end-to-end on the reconciled schema. complexity: [high]
- [ ] T7.2 `GameMapper.map_game`: populate `platforms[]`. complexity: [low]
- [ ] T7.3 Already-in-Library resolver (find by `igdb_id` → resync; else create + sync). complexity: [high]
- [ ] T7.4 `GameIgdbSync`: fix `resyncing`; ensure cover-art + Voyage chain. complexity: [low]
- [ ] T7.5 WebMock specs: Client, SyncGame, GameIgdbSync. complexity: [low]
- [ ] T7.6 `bundle exec rspec` + `bin/rubocop` green. complexity: [manual]
- [ ] T7.7 Commit: `Repair IGDB sync end-to-end + specs`. complexity: [manual]

## P8 — Multi-field game embedding + channel embedding + diff-gated reindex

- [ ] T8.1 `Game::EmbedText` (title+genres+dev+pub+description+platforms+ttb+ratings) in VoyageIndexer + BulkVoyageIndexJob. complexity: [high]
- [ ] T8.2 Migration `games.embedded_digest`; VoyageIndexer no-ops when digest unchanged. complexity: [high]
- [ ] T8.3 `SyncGame`: reindex only when digest changed. complexity: [low]
- [ ] T8.4 Migration: `channels.summary_embedding`(HNSW) + `keywords` + `tags`; `has_neighbors`. complexity: [low]
- [ ] T8.5 `Channel::VoyageIndexer`: title+desc+handle+keywords+tags + digest gate; backfill. complexity: [low]
- [ ] T8.6 Confirm `SimilarGames` + `ChannelRecommendation` work. complexity: [low]
- [ ] T8.7 Specs; `bundle exec rspec` + `bin/rubocop` green. complexity: [low]
- [ ] T8.8 Commit: `Multi-field game + channel embeddings + diff-gated reindex`. complexity: [manual]

## P9 — Game detail message component (ScoreBar + TTB-with-footage + cover)

- [ ] T9.1 `Pito::Game::DetailComponent`: cover (600×800), title, dev, pub, release_label, platforms available, owned platforms, description, all genres. complexity: [high]
- [ ] T9.2 Wire `TimeToBeatComponent` main/extras/completionist + **footage** 4th tick = `sum(footages.duration_seconds)/3600`. complexity: [low]
- [ ] T9.3 Wire `ScoreBarComponent` with `game.score`. complexity: [low]
- [ ] T9.4 Prose via `Pito::Copy`; stamp `make_followupable!(target:"game_detail")`. complexity: [low]
- [ ] T9.5 Component specs. complexity: [low]
- [ ] T9.6 Commit: `Game detail message component (score + ttb-with-footage + cover)`. complexity: [manual]

## P10 — Chat verbs `list/show/delete games` + grammar + title ghost + list follow-up + picker

- [ ] T10.1 Grammar: noun vocab (`game`/`games`/`videos`) + `:game_title` slot (source `:game_titles`) on `show`; `list`(ls)/`show`/`delete`(rm) specs/aliases; adjust FILLERS. complexity: [high]
- [ ] T10.2 `Chat::Handlers::List` (rewrite): real query → list System message; stamp `make_followupable!(target:"game_list")`. complexity: [low]
- [ ] T10.3 `Chat::Handlers::Show`: parse title; `Game.find_by ILIKE` → detail message; not-found witty error. complexity: [high]
- [ ] T10.4 `Chat::Handlers::Delete`: parse title → confirmation event (`reply_target:"game_delete"`). complexity: [low]
- [ ] T10.5 `Pito::Suggestions`: wire `:game_title` ghost (server resolves dynamic; add to JS `_chatEnumSlots()`) → `show game li` ghosts `es of P`. complexity: [high]
- [ ] T10.6 `FollowUp::Handlers::GameList` (`:append`): `#<h> show <title>` → detail message. complexity: [low]
- [ ] T10.7 `FollowUp::Handlers::GameDelete` (confirmation): destroy + outcome. complexity: [low]
- [ ] T10.8 `Sidebar::Games::Component` + `pito--games-nav`; no-arg picker → populate chatbox + submit. complexity: [high]
- [ ] T10.9 Extend `chat_form_controller` with a public set-value+submit action. complexity: [low]
- [ ] T10.10 `ChatController`: fast-path to open the games picker on no-title `show game`/`rm game`. complexity: [low]
- [ ] T10.11 i18n via `Pito::Copy`; handler/request/component/JS specs. complexity: [low]
- [ ] T10.12 `bundle exec rspec` + `npm test` + `bin/rubocop` + `node --check` green. complexity: [manual]
- [ ] T10.13 Commit: `Chat verbs list/show/delete games + title ghost + picker + follow-ups`. complexity: [manual]

## P11 — `/games import` sidebar (search → 5-step progress → 2 messages)

- [ ] T11.1 `Slash::Handlers::Games` (verb `:games`, subcommand `import`) + grammar/help/palette/i18n; opens sidebar (prefill). complexity: [high]
- [ ] T11.2 `Sidebar::GamesImport::Component` + `pito--games-search`: debounced search → IGDB module endpoint; keyboard nav. complexity: [high]
- [ ] T11.3 Results: main-only, cover thumb, "in Library" marker (→ resync). complexity: [low]
- [ ] T11.4 Select → `GameImportJob` streaming 5 steps: main info, cover art, score, Voyage, recommendations (dummy). complexity: [high]
- [ ] T11.5 After step 3: stream the standard detail chat message. complexity: [low]
- [ ] T11.6 After step 5: stream an enhanced (lorem) message; stamp `make_followupable!(target:"game_enhanced")`. complexity: [low]
- [ ] T11.7 Search endpoint route/controller (or chat fast-path). complexity: [low]
- [ ] T11.8 Specs: handler, endpoint (WebMock), import chain (steps + messages + resync). complexity: [low]
- [ ] T11.9 `bundle exec rspec` + `npm test` + `bin/rubocop` + `node --check` green. complexity: [manual]
- [ ] T11.10 Commit: `/games import sidebar: IGDB search → 5-step progress → detail + enhancement`. complexity: [manual]

## P12 — Follow-ups on the game messages

- [ ] T12.1 `FollowUp::Handlers::GameDetail`: `rm`/`delete` → confirmation; `resync` → confirmation. complexity: [low]
- [ ] T12.2 `owned <platform>`: extend `PLATFORMS` (GOG/Epic→steam) + display→token bridge; toggle `GamePlatformOwnership`; mutate the message. complexity: [high]
- [ ] T12.3 Confirmation executors: resync→`GameIgdbSync`; reindex→re-embed (digest-aware); rm→destroy. complexity: [low]
- [ ] T12.4 `FollowUp::Handlers::GameEnhanced`: `reindex`→confirmation; `similar [filters]` + `channel` → `:mutate` (chainable). complexity: [high]
- [ ] T12.5 Parse `similar` filters (genre/year/developer/publisher/complexity/ttb/score/platform). complexity: [high]
- [ ] T12.6 Render recommendation segments via `ScoreBarComponent` + `AffordanceComponent`. complexity: [low]
- [ ] T12.7 i18n via `Pito::Copy`; handler specs. complexity: [low]
- [ ] T12.8 `bundle exec rspec` + `bin/rubocop` green. complexity: [manual]
- [ ] T12.9 Commit: `Game message follow-ups (rm/resync/owned · reindex/similar/channel)`. complexity: [manual]

## P13 — `Pito::Recommendations` (similar / channel)

- [ ] T13.1 `Pito::Recommendations.similar_games(game, filters:)` via `SimilarGames` + `Recommendation::{TopK,HmsScorer,WeightedBlend}`. complexity: [high]
- [ ] T13.2 `Pito::Recommendations.channels_for(game)` via `ChannelRecommendation`. complexity: [low]
- [ ] T13.3 Keep import step-5 dummy distinct. complexity: [low]
- [ ] T13.4 Wire P12 `#similar`/`#channel`; output via `ScoreBarComponent`. complexity: [low]
- [ ] T13.5 Specs (seeded embeddings). complexity: [low]
- [ ] T13.6 Commit: `Pito::Recommendations (similar games + channel suggest)`. complexity: [manual]

## P14 — Daily future-games sync (1:00)

- [ ] T14.1 `GameIgdbNightlyRefresh`: scope to unreleased; re-sync + rescore; stop once released. complexity: [low]
- [ ] T14.2 Diff-gated reindex on nightly. complexity: [low]
- [ ] T14.3 `config/recurring.yml`: `0 1 * * *`. complexity: [low]
- [ ] T14.4 Trigger `GameStatsRefreshJob` after nightly. complexity: [low]
- [ ] T14.5 Job spec; `bundle exec rspec` + `bin/rubocop` green. complexity: [low]
- [ ] T14.6 Commit: `Daily 1:00 refresh for unreleased games`. complexity: [manual]

## P15 — Extract, document, finalize

- [ ] T15.1 (done at plan time) `docs/games.md` created. complexity: [low]
- [ ] T15.2 Finish pulling remaining game items out of `docs/follow-up.md` (Section E games-detail, Section C `## Games`/`## Footage`). complexity: [low]
- [ ] T15.3 `AGENTS.md`: `## Games`, `## Footage / ffprobe`, `## Engines` (`Copy`/`FollowUp`/`Suggestions`/`Stack`/`Stats`/`Search`). complexity: [low]
- [ ] T15.4 Update `docs/validations.md` + PR #62 description. complexity: [low]
- [ ] T15.5 Full suite + `npm test` + `bin/rubocop` + `zeitwerk:check` green; poll PR #62 CI green. complexity: [manual]
- [ ] T15.6 Commit: `Document games domain (docs/games.md + AGENTS) + finalize`. complexity: [manual]

## Per-phase Definition of Done

Doc-blocks on new classes; new + edge-case specs (Rails + JS); `bundle exec rspec`

- `npm test` + `bin/rubocop` + `node --check` + `bin/rails zeitwerk:check` green;
  each phase's `Commit:` flips its tasks `[ ]→[-]→[x]` per transition and stages
  this plan file; push; PR #62 CI (`rails`/`js`/`prettier`) green. **Never merge.**
