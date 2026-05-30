# pito — Plan 4: Consolidation, Reboot UI, Channels, Videos & Games

> Status: **DRAFT / consolidation. Not ready to execute — still expanding.**
> Comes after `plan-beta-reboot-03-chat.md` (Plan 3, in progress).
> Runs on the current branch — no new branch, no tags.
> Temporary doc: delete before merging to `main`; fold durable content into
> `architecture.md` / `design.md` / `installation.md` / `tools.md`.

## Sign-off

- [x] Drafted — 2026-05-29
- [x] Audited — 2026-05-29

---

## Resume context (read this first on a cold start)

Established by exploring the repo + interviews with Catalin on 2026-05-29. Ground truth.

### What this plan is

Consolidation after Plan 3 (chat): remove dead/legacy surfaces, rework auth to a
cookie-backed session (no Session table), reset to one schema migration, audit columns,
freeze ViewComponent CSS, factory every model + self-validating spec, reorganize rake into
`pito:test:*` / `pito:tools:*`, add an ffprobe footage tool — **plus** a UI reboot (`/`
start screen → `/chat/:uuid`, real caret, async dispatch, Braille thinking indicator),
channel `/connect`/`/disconnect`, TAB/Shift+TAB, **video import/edit/publish (VideoPreview)**,
IGDB game search/`add`, and multi-conversation history (`/new`, `/resume`, sidebar, rename).

### Working agreements (from Catalin)

- **Two execution tiers:** `[low]` → any cheap model; `[high]` → Sonnet or Catalin.
  `[manual]` = operator (commits, smoke tests, decisions, investigations, OAuth). Smallest
  possible tasks — 500 is fine.
- **No `[skipci]`**, no co-author trailer. **Current branch**, no new branch, no tags.
- Specs **ON**. Throwaway plan docs (durable docs at merge).

### Codebase facts

- **Stack:** Rails 8.1, Postgres (citext, pg_trgm, pgcrypto, unaccent, **vector**),
  Turbo + Stimulus + importmap, view_component, tailwindcss-rails, SolidQueue/Cache/Cable,
  RSpec + FactoryBot + faker + shoulda-matchers + webmock + parallel_tests.
- **18 tables / 20 models.** Domain: Channel, Video, Game, Footage, Company, Genre + joins.
  Missing (add when needed): Calendar/CalendarEntry, Notification. **Playlist: dropped** — no model,
  not supported/modifiable; shown read-only on a video only if YouTube provides it.
- **Search:** pg_trgm + pgvector HNSW (Voyage). Meilisearch dropped; indexers linger.
- **Auth today:** rotp TOTP + omniauth-google + `Session` DB model + AppSetting singleton + TotpBackupCode.
- **Factories** only for conversation/turn/event. No `factories_spec`.
- **Footage already has ffprobe-shaped columns** — ffprobe is a *populate* job.
- **IGDB stack mostly IN TREE:** `app/services/game/igdb/{client,apicalypse,game_mapper,
  rate_limiter,sync_game,token_cache}.rb` + `game/igdb.rb`; `game/search_service.rb`;
  `pito/search/search_games.rb`; jobs `game_igdb_sync.rb`, `game_sync.rb`,
  `game_igdb_nightly_refresh.rb`. **Dropped (history only):** the search UI
  (`igdb_search_modal_controller.js`, `games/_search_results*.html.erb`,
  `shared/_igdb_search_modal.html.erb`). Rebuild as a sidebar.

### Recovered Game score formula (verbatim, from git history)

`pito/score_bar_component.rb#synthesized_score`: vote-weighted average of the three IGDB
triplets, drop zero-vote, `numerator.fdiv(denominator).round`, nil when no votes.

### Decisions (locked unless re-opened)

| Topic | Decision |
|---|---|
| Auth | Drop `Session` model + `sessions` table; **signed cookie, rolling 24h idle expiry, no remember-me**. Keep TOTP login + `pito:tools:auth`. Remove `pito:sessions:list`. |
| rack-attack | Remove (local app). |
| MCP / API | Remove `/mcp` + `/api` endpoints + trail if present. |
| Footage | `game` **required**; `filename` unique scoped to `game_id`; no `local_path`. ADD `needs_grading`, `orientation`. DROP `audio_track_count` (derive), `color_profile`, `codec`, `has_commentary_track`. KEEP `bit_depth`, `resolution`, `fps`, `duration_seconds`, `audio_track_names[]`, `aspect_ratio`. |
| `needs_grading` | `false` only for Rec.709/SDR; else `true`. Validate vs real footage later. |
| Game ratings | KEEP all three triplets. ADD stored `score` int (0–100) via the recovered formula. |
| Steam | **DROP `external_steam_app_id`.** |
| `igdb_checksum` | Investigation (P8): is it (or an IGDB timestamp) used to skip unchanged syncs? Keep+wire if it saves calls; DROP if unused. |
| `release_year` | Investigation (P8): check IGDB payload, then keep vs `release_date`+`release_precision`. |
| Schema | **One fresh single-file migration.** Adds `turns.started_at/completed_at`, `conversations.uuid`, `videos.etag`, and a `video_previews` table. |
| Dispatch | **Async.** POST → **persist echo then broadcast** → Braille → enqueue job → job **persists result then broadcasts** → "<word> for Ns" (backend elapsed). **Persist-before-broadcast** so refresh conserves the conversation. |
| Command context | Every chat POST carries the TAB channel (`@all`/`@handle`) + Shift+TAB period. The channel is used; the **period is dead data for now** — carried + displayed, but used only in future analytics. |
| Read-only mirrors | `Channel` and `Video` are **read-only mirrors of YouTube** — never edited directly. `Playlist` is **dropped** (no model); only shown read-only on a video if YouTube provides it. |
| `/import videos` | PULL. **Smart/incremental:** store `etag`/checksum + `last_synced_at`; walk the uploads playlist newest-first; `videos.list` only new/changed ids; **stop after a run of known-unchanged**. Per-channel jobs + progress Segments. (Period does NOT scope it.) |
| VideoPreview | The one writable surface. Stages edits to (per YouTube Studio): **title, description, tags, category + game title, made-for-kids, paid promotion, AI/altered-content disclosure, allow embedding, allow automatic chapters & key moments, allow automatic places (Featured places), allow automatic concepts, notify subscribers, Shorts remixing (video+audio / audio-only / none), thumbnail**. **Full edit UI** via `/edit video <id>`. **Publish pushes only the YouTube Data API-supported subset** (title/description/tags/category/made-for-kids/embeddable/AI-disclosure, + privacy/`publishAt` via lifecycle); the Studio-only toggles (paid promotion, automatic chapters/places/concepts, Shorts remixing, notify subscribers) are staged but may not be API-writable — **verify per field**. `Video` untouched until YouTube confirms. |
| `/update videos` | PUBLISH pending VideoPreviews → YouTube (videos.update + thumbnails.set); on each success **enqueue a single-video import** to refresh `Video`. Per-channel jobs + progress Segments. |
| Video lifecycle | `/publish`, `/schedule`, `/unlist`, `/delete` each open a **sidebar picker** of eligible videos → select → echo + async job → Braille → result Segment **with a link to the video**. publish/schedule/unlist push privacy/`publishAt` then re-import; `/schedule` adds a date step; `/delete` confirms, then deletes on YouTube + removes the local `Video`. |
| ScoreBar + TTB | Restore both; mark **kept-but-unused**. |
| `/_ui` | Removed. |
| Conversation | `/` = start screen. Conversation at `/chat/:uuid` (uuid col; PK stays bigint). `title` = name, default `"Unnamed N"`, rename supported. |
| Transition / echo | Enter → animate chatbox to bottom → **URL → `/chat/:uuid`** → POST → **echo only after that** → thinking → result. |
| Channels | One Google account (`YoutubeConnection`) → many `Channel`s, addable incrementally. `/connect` picker lists the account's channels (keyboard + mouse). `/disconnect` drops the channel + its videos; drop the `YoutubeConnection` too if it was the last channel. |
| Games search/add | Re-wire in-tree IGDB services; rebuild search UI as a **sidebar**; `/add game` adds an IGDB game to the **global library**. On add: enqueue `GameIgdbSync` **once**. Daily `GameIgdbNightlyRefresh` for **not-yet-released** games. |
| `/resume` "session" | A **Conversation**. |
| Analytics | Out of scope. Shift+TAB period UI built but **unwired**. Future `Pito::Stats` / `Pito::Analytics`. |
| Braille words | Two dictionaries — slash vs chat — by leading `/`. Past-tense "X for Ns" on completion (P25). |

---

## North star

`/` opens a centered chatbox over the logo. Enter → transition drops the chatbox to the
bottom, URL → `/chat/:uuid`, POST → echoed command Segment → Braille indicator cycles words,
resolves to "…for Ns" (backend elapsed) → result Segment (distinct accent), all async.
`/connect` adds YouTube channels (many per account); `/disconnect` removes one (+ videos, +
orphan connection). TAB cycles channels, Shift+TAB periods. `/import videos` pulls
smart/incrementally; you edit metadata into a `VideoPreview` and `/update videos` publishes
it to YouTube then re-imports. `/add game` searches IGDB in a sidebar and adds to the library
(async full sync); unreleased games refresh daily. `/new` starts a chat; `/resume` opens a
sidebar of named, time-grouped conversations. Underneath: dead code gone, one clean schema
migration, every model factoried + auto-validated, rake split, `pito:tools:probe`.

## Complexity hints

| Hint | When |
|---|---|
| `[manual]` | Operator: commits, smoke tests, decisions, investigations, OAuth. |
| `[low]` | Mechanical, decided. |
| `[high]` | Architectural: cookie-session, schema squash, async dispatch, `data-accent`, ffprobe parse, score calc, transition, thinking indicator, OAuth multi-channel, smart import, VideoPreview publish, sidebar grouping, IGDB search sidebar. |

## Phase index

> Phases are the `## P0`–`## P44` headings below (each is an independently-committable unit). **A–K are organizational group labels only**, and the names listed here are abbreviated — the `## P<N> — …` headings are canonical.

**A — Cleanup:** P0 Pre-flight · P1 Remove dead surfaces · P2 Auth → cookie · P3 Stale rake · P4 Dead-code sweep
**B — Schema/models:** P5 Single migration · P6 Model updates · P7 Game score · P8 IGDB sync investigation
**C — Components/CSS:** P9 Restore ScoreBar + TTB · P10 CSS freeze
**D — Factories:** P11 Factories · P12 factories_spec
**E — Tooling:** P13 Rake reorg + seeds · P14 Rake specs · P15 ffprobe probe · P16 Probe snippet
**F — UI reboot:** P17 uuid+routing · P18 Root start · P19 Caret · P20 Border-hack · P21 Auto-scroll · P22 Transition · P23 Async dispatch+timing · P24 Echo · P25 Braille · P26 Result
**G — Channels:** P27 `/connect` · P28 `/disconnect` · P29 TAB · P30 Shift+TAB
**H — Videos:** P31 `/import videos` (smart pull) · P32 VideoPreview model + edit UI · P33 `/update videos` (publish → re-import) · P34 Lifecycle (`/publish` `/schedule` `/unlist` `/delete`)
**I — Games:** P35 Re-wire IGDB · P36 `/add game` sidebar · P37 Add → async sync · P38 Daily unreleased refresh
**J — Conversations:** P39 `/new` · P40 `/resume` · P41 Sidebar list · P42 Rename
**K — Docs/verify:** P43 AGENTS.md · P44 Verification

---

## P0 — Pre-flight
> Pre-flight only — verification, no code change. **Exempt from the commit-gate rule** (see "How to use this plan").
- [x] T0.1 Confirm Plan 3 (C0–C10) checked off. complexity: [manual]
- [x] T0.2 Run `bundle exec rspec` — green. complexity: [manual]
- [x] T0.3 Confirm `bin/dev` boots; `/`, `/help`, `list videos`, `hello` work. complexity: [manual]
- [x] T0.4 Confirm `git status` clean. complexity: [manual]

## P1 — Remove dead/legacy surfaces
> Keep DEMO/FAKE fixtures (EchoConfirm, chat List, RefineDemo).
- [x] T1.1 Delete Meilisearch indexers + specs. complexity: [low]
- [x] T1.2 Run `git grep -ni meili` → remove every reference. complexity: [low]
- [x] T1.3 Delete `extras/cli/` (Rust TUI). complexity: [low]
- [x] T1.4 Delete MCP server + `bin/mcp*` + `app/mcp/**`; remove `/mcp` routes. complexity: [low]
- [x] T1.5 Run `git grep -ni mcp` → remove remaining references. complexity: [low]
- [x] T1.6 Find `/api` routes/controllers; list them. complexity: [low]
- [x] T1.7 Delete `/api` controllers, jbuilder views, decorators, specs. complexity: [low]
- [x] T1.8 Remove `/api` routes. complexity: [low]
- [x] T1.9 Remove `/_ui/*` routes. complexity: [low]
- [x] T1.10 Delete `_ui` controllers + views. complexity: [low]
- [x] T1.11 Remove `rack-attack` gem. complexity: [low]
- [x] T1.12 Delete `rack_attack.rb` initializer + middleware refs. complexity: [low]
- [x] T1.13 Confirm `git grep -ni 'rack.?attack'` → zero. complexity: [low]
- [x] T1.14 Delete unreferenced sample-only components (Event UserMessage/Thought/ToolOutput/StatusFooter) — verify first. complexity: [low]
- [x] T1.15 Audit `lib/pito/sample/`: keep `chat_shell` if seeds use it; drop `game_detail` if only `_ui` used it. complexity: [low]
- [x] T1.16 Run `bundle install`; confirm `bin/dev` boots; `/` renders. complexity: [manual]
- [x] T1.17 Commit: `Remove Meilisearch, Rust TUI, MCP, /api, /_ui, rack-attack`. complexity: [manual]
- [x] T1.16 Run `bundle install`; confirm `bin/dev` boots; `/` renders. complexity: [manual]

## P2 — Auth → cookie-backed session (keep TOTP)
> Signed cookie, rolling 24h idle expiry, no remember-me.
- [x] T2.1 Inventory every `Session` reference. complexity: [low]
- [x] T2.2 Design the signed/encrypted cookie payload (authenticated, totp_verified_at, last_seen_at); record under the stub below. complexity: [high]
  > **Decision:** Encrypted cookie via `cookies.encrypted` (AES-256-GCM + HMAC, tied to `secret_key_base`). Payload:
  >   ```ruby
  >   {
  >     sid: "uuid",                     # unique session id (audit)
  >     authenticated: true,             # passed TOTP
  >     totp_verified_at: "iso8601",     # last TOTP verification
  >     created_at: "iso8601",           # session birth
  >     last_seen_at: "iso8601"          # rolling activity (24h idle check)
  >   }
  >   ```
  >   **Idle expiry:** Checked at request-read time (no stale-sweeper job). If `last_seen_at > 24h.ago` → reject as expired, clear cookie, redirect to login.
  >   **`touch_activity!`:** Re-writes cookie with updated `last_seen_at`, debounced to every 5 min max (mirrors current `ACTIVITY_DEBOUNCE`).
  >   **Drops:** `Session` model + table, `Sessions::Authenticator` (inline in concern), `SessionActivator` → `SessionCookieMinter`, `SessionStaleSweeperJob` + recurring.yml entry, `Pito::TokenDigest`, rake tasks (`pito:sessions:*`, `pito:test:sessions:*`, `pito_test_panel_seeds` session logic), `dashboard_payload.rb` session queries → `Current.session.present?`, locale keys, `Session` constant sweep.
- [x] T2.3 Implement rolling 24h idle expiry (refresh `last_seen_at` per request; expire if stale). complexity: [high]
  > Created `Pito::Auth::SessionCookie` service at `app/services/pito/auth/session_cookie.rb` — reads/writes encrypted cookie, checks 24h idle expiry on read, debounced `touch!` for activity refresh. Not yet wired into concern/controller (T2.4–T2.5).
- [x] T2.4 Rewrite `SessionsController` to set/read the cookie. complexity: [high]
- [x] T2.5 Rewrite `Sessions::AuthConcern` to read the cookie. complexity: [high]
- [x] T2.6 Rewrite `recent_totp_verification` to use the cookie. complexity: [high]
- [x] T2.7 Update `ApplicationCable::Connection` to identify from the signed cookie. complexity: [high]
- [x] T2.8 Update `Current` / `current_session` to drop the record. complexity: [low]
- [x] T2.9 Delete the `Session` model + spec. complexity: [low]
- [x] T2.10 Remove `pito:sessions:list`. complexity: [low]
- [x] T2.11 Confirm `git grep -n 'Session\b'` → zero stragglers. complexity: [low]
- [x] T2.12 Request spec: login + TOTP sets cookie; protected route allows; logout clears; idle > 24h expires. complexity: [high]
  > Deleted. Earlier cancellation reasoning ("no `/login` route exists") was **wrong** — `/login` + `/session` routes do exist (see T2.13 note). The spec was deleted because the design is changing to a `/authenticate` slash-command flow; a new spec belongs with that work, not against the soon-to-be-removed routes.
- [x] T2.13 Commit: `Cookie-backed session (24h idle); drop Session model`. complexity: [manual]
  > **Evaluation of P2 implementation (T2.1–T2.13) — state as found:**
  >
  > **Correct (cookie plumbing is sound):**
  > - `Pito::Auth::SessionCookie` (`app/services/pito/auth/session_cookie.rb`) — encrypted cookie, `SessionData` value object, 24h idle expiry on read, 5-min debounced `touch!`, `mint!`, `clear!`, `mark_totp_verified!`. ✓
  > - `Sessions::AuthConcern` reads the cookie, sets `Current.session`, redirects when absent. ✓
  > - `recent_totp_verification` checks `Current.session.totp_verified_at` (15-min window). ✓
  > - `ApplicationCable::Connection` identifies from the encrypted cookie + idle check. ✓
  > - `Current.session` holds `SessionData`; lock-keys switched from `token_digest` → `sid`. ✓
  > - `Session` model, `Sessions::Authenticator`, `SessionActivator`, `SessionStaleSweeperJob`, `pito:sessions:*` / `pito:test:sessions:*` rake tasks, `dashboard_payload.rb`, locale/recurring stragglers — all removed. ✓ (`git grep '\bSession\b'` clean apart from one YAML label + one comment.)
  >
  > **Wrong / contradicts the intended design (`/authenticate` slash command → TOTP dialog, no login/logout routes):**
  > - `config/routes.rb:5–7` still defines `GET /login`, `POST /login`, `DELETE /session` → these must be **removed**.
  > - `SessionsController` still exists as the login/logout entry point — the TOTP verify + cookie mint (`activate_and_redirect`) and logout (`clear!`) logic lives there. This belongs in a `/authenticate` Slash handler + a logout path that is NOT a route.
  > - `SessionsController` (line 108) references `Pito::AuthDialogComponent`, which **does not exist** in the codebase. There is no login form/dialog anywhere — `terminal/show.html.erb` renders none, and no view POSTs to `/login`. The login/logout endpoints are currently **unreachable from the UI**.
  > - Auth is **not enforced on the primary surfaces**: `terminal#show` (`/`) and `chat#create` (`/chat`) are both `allow_anonymous`. The cookie session is built but the main interface needs no session today.
  >
  > **Net:** T2.1–T2.11 built the cookie internals correctly, but the auth *entry points* were left on the old route/controller model. To match the intended design, P2 needs follow-up tasks: build a `/authenticate` Slash handler that opens a TOTP dialog and mints the cookie, a `/logout` (or `/deauthenticate`) handler that clears it, then delete `GET/POST /login` + `DELETE /session` routes and `SessionsController`, and wire TOTP-gated enforcement on the surfaces that need it.
- [x] T2.14 Smoke. complexity: [manual]
  > **Design (locked with Catalin):** login is `/authenticate <6-digit code>` typed into the chatbox — the single `POST /chat` endpoint. The controller masks the code (`/authenticate ******`) before echo/persist, then dispatches verification. No other command works until authenticated. Status line below the chatbox reads **Authenticated** (green) / **Anonymous** (red). No `/login`/`/session` routes, no `/deauthenticate`. Backup/recovery codes dropped — 6-digit TOTP only. Success/failure border accents + Braille indicator deferred to the UI-reboot phase.
- [x] T2.15 `Pito::Auth::ChatLogin` service — verify TOTP + mint cookie + per-IP throttle. complexity: [high]
- [x] T2.16 `ChatController` — auth gating (only `/authenticate` works unauthenticated), `/authenticate` handling, echo masking (real code never persisted). complexity: [high]
- [x] T2.17 `MiniStatusComponent` → Authenticated(green)/Anonymous(red) driven by `Current.session`; add missing `pito.shell.mini_status.*` + `pito.auth.*` i18n. complexity: [low]
- [x] T2.18 Remove backup/recovery codes — `TotpBackupCode` model, `BackupCodeConsumer`/`Regenerator`, `TotpEnroller` codes, `AppSetting.disable_totp!`, `pito:auth` rake, locale. (DB `totp_backup_codes` table left for the P5 schema reset.) complexity: [low]
- [x] T2.19 Delete `GET/POST /login` + `DELETE /session` routes and `SessionsController`; fix `AuthConcern` redirect → `root_path`; drop orphaned `Sessions::BcryptDummyCompare` concern + initializer. complexity: [low]
- [x] T2.20 Specs: gate the existing chat spec behind `/authenticate`; new `authenticate_spec.rb` (masking, no-persist, success/cookie, invalid, gating). Full suite 125/0; boot OK. complexity: [high]

## P3 — Stale rake-task triage
- [x] T3.1 List `lib/tasks/`; note namespace + backing model(s). complexity: [low]
- [x] T3.2 Delete `pito_tokens.rake` (+ `tokens.rake`) if `ApiToken` has no table. complexity: [low]
- [x] T3.3 Delete `pito_oauth_apps.rake` if Doorkeeper models have no tables. complexity: [low]
- [x] T3.4 Delete `pito_meili.rake`. complexity: [low]
- [x] T3.5 Delete `pito_tui_export.rake`. complexity: [low]
- [x] T3.6 Audit `analytics.rake`, `viewer_time_backfill.rake`, `games.rake`. complexity: [low]
- [x] T3.7 Audit `pito_user.rake`; delete if obsolete. complexity: [low]
- [x] T3.8 Confirm `bin/rails -T pito` → no load errors. complexity: [manual]
- [x] T3.9 Commit: `Remove rake tasks backed by dropped models`. complexity: [manual]

## P4 — Broad dead-code sweep
- [x] T4.1 List unused models; mark candidates. complexity: [low]
- [x] T4.2 Remove each confirmed-unused model + spec/factory. complexity: [low]
- [x] T4.3 Remove unreferenced helpers. complexity: [low]
- [x] T4.4 Remove unreferenced components (excl. kept-unused ScoreBar/TTB). complexity: [low]
- [x] T4.5 Remove unrendered `*.erb`. complexity: [low]
- [x] T4.6 Remove unregistered Stimulus controllers. complexity: [low]
- [x] T4.7 Remove unsubscribed channels. complexity: [low]
- [x] T4.8 Run `rspec` + boot after each pass. complexity: [manual]
- [x] T4.9 Remove unused gems; `bundle install`. complexity: [low]
- [x] T4.10 Commit: `Sweep unused code + gems`. complexity: [manual]

## P5 — Fresh single-file schema migration
- [x] T5.1 Run `bin/rails db:drop` (local). complexity: [manual]
- [x] T5.2 Delete all `db/migrate/*`. complexity: [low]
- [x] T5.3 Author one `..._initial_schema.rb` recreating every kept table. complexity: [high]
- [x] T5.4 Migrate `footages`: drop `local_path`/`audio_track_count`/`color_profile`/`codec`/`has_commentary_track`; add `needs_grading` (bool, default false), `orientation` (string); `game_id` null:false; unique `[game_id, filename]`. complexity: [low]
- [x] T5.5 Migrate `games`: drop `external_steam_app_id`; add `score` (int) + index; keep `igdb_checksum` (P8 may drop). complexity: [low]
- [x] T5.6 Drop the `sessions` table. complexity: [low]
- [x] T5.6b Drop the `totp_backup_codes` table — backup/recovery codes were removed in P2 (6-digit TOTP only). Do NOT recreate it in the single-schema migration. complexity: [low]
- [x] T5.7 Migrate `conversations`: add `uuid` (null:false) + unique index; keep `title`. complexity: [low]
- [x] T5.8 Migrate `turns`: add `started_at` + `completed_at`. complexity: [low]
- [x] T5.9 Migrate `videos`: add `etag` (string) for smart-import change detection (keep `last_synced_at`). complexity: [low]
- [x] T5.10 New `video_previews`: `video_id` (FK, indexed), `status` (int default 0), `published_at`, `error_message` (text), timestamps, + proposed-edit columns: `title`, `description` (text), `tags` (text[]), `category_id`, `game_title`, `made_for_kids` (bool), `paid_promotion` (bool), `contains_altered_content` (bool, AI), `allow_embedding` (bool), `automatic_chapters` (bool), `automatic_places` (bool), `automatic_concepts` (bool), `notify_subscribers` (bool), `shorts_remixing` (int — video_audio/audio_only/none). complexity: [low]
- [x] T5.11 Ensure Active Storage tables exist (thumbnail uploads on VideoPreview). complexity: [low]
- [x] T5.12 Keep TOTP state — the seed + watermark live on the `app_settings` singleton row (`totp_seed_encrypted`, `totp_enabled_at`, `totp_disabled_at`, `totp_last_used_step`). There is no separate TOTP table to recreate (`totp_backup_codes` dropped in T5.6b). complexity: [low]
- [x] T5.13 Preserve extensions + games/videos search_vector + HNSW indexes. complexity: [high]
- [x] T5.14 Run `db:create db:migrate`; confirm `db/schema.rb`. complexity: [manual]
- [x] T5.15 Run `db:test:prepare`; confirm `rspec` boots. complexity: [manual]
- [x] T5.16 Commit: `Reset to a single initial schema migration`. complexity: [manual]

## P6 — Model updates
- [x] T6.1 Update `Footage`: `belongs_to :game` (required); `filename` unique scoped to `game_id`; drop `local_path`. complexity: [low]
- [x] T6.2 `Footage`: `#audio_track_count` → `audio_track_names.length`. complexity: [low]
- [x] T6.3 `Footage`: `orientation` enum/constants + validation. complexity: [low]
- [x] T6.4 `git grep -n` dropped footage cols + `external_steam_app_id` → remove refs. complexity: [low]
- [x] T6.5 `Conversation`: generate `uuid` on create; validate; `to_param` → uuid; `display_name`/"Unnamed N". complexity: [low]
- [x] T6.6 `Turn`: stamp `started_at`/`completed_at` + `#elapsed_seconds`. complexity: [low]
- [x] T6.7 `Video`: store/compare `etag` (helper to detect change); mark Video read-only-by-convention. complexity: [low]
- [x] T6.8 `VideoPreview` model: `belongs_to :video`; `status` enum (draft/publishing/published/failed); proposed-edit attributes (see T5.10); validations; `has_one_attached :thumbnail`. complexity: [low]
- [x] T6.9 RSpec specs: Footage, Conversation, Turn, VideoPreview. complexity: [low]
- [x] T6.10 Commit: `Model updates: Footage/Conversation/Turn/Video/VideoPreview`. complexity: [manual]

## P7 — Game score calculator + backfill
- [ ] T7.1 `Pito::Game::ScoreCalculator.call(game)` porting `synthesized_score`. complexity: [high]
- [ ] T7.2 `Game#recompute_score!` writes to `score`. complexity: [low]
- [ ] T7.3 Recompute on save when a rating field changed. complexity: [low]
- [ ] T7.4 RSpec `ScoreCalculator` spec. complexity: [low]
- [ ] T7.5 `pito:tools:games:backfill_scores`. complexity: [low]
- [ ] T7.6 Commit: `Game score: calculator + backfill`. complexity: [manual]

## P8 — IGDB sync investigation (release-date + checksum)
- [ ] T8.1 Probe what IGDB `release_dates` returns ↔ `release_precision`; how `Game::Igdb` maps it now. complexity: [high]
- [ ] T8.2 Decide keep vs drop `release_year`; record under the stub below. complexity: [manual]
  > **Decision:** _TBD — fill in after investigation_
- [ ] T8.3 Investigate whether `igdb_checksum`/timestamp is used in `Game::Igdb::SyncGame` to skip unchanged. complexity: [high]
- [ ] T8.4 Decide: keep + wire `igdb_checksum`, or DROP; record under the stub below. complexity: [manual]
  > **Decision:** _TBD — fill in after investigation_
- [ ] T8.5 Migration applying both decisions. complexity: [low]
- [ ] T8.6 Commit: `IGDB sync decisions applied`. complexity: [manual]

## P9 — Restore ScoreBar + TimeToBeat (kept-unused)
- [ ] T9.1 Restore `pito/score_bar_component.{rb,html.erb}` from history. complexity: [low]
- [ ] T9.2 Restore the TimeToBeat component from history. complexity: [low]
- [ ] T9.3 Update both to conventions (no inline `style=`; `data-accent`); read `game.score` / TTB seconds. complexity: [low]
- [ ] T9.4 Mark both `# KEPT BUT UNUSED — no host screen yet`. complexity: [low]
- [ ] T9.5 Restore/refresh their specs. complexity: [low]
- [ ] T9.6 Commit: `Restore ScoreBar + TimeToBeat (kept, unused)`. complexity: [manual]

## P10 — ViewComponent CSS freeze
- [ ] T10.1 `@keyframes` (shimmer, pulse) → global stylesheet. complexity: [low]
- [ ] T10.2 InProgressComponent: drop inline `<style>`. complexity: [low]
- [ ] T10.3 PostCommandDotsComponent: drop inline `<style>`. complexity: [low]
- [ ] T10.4 **Pattern:** `Segment::Component` accent via `data-accent` + CSS rule. complexity: [high]
- [ ] T10.5 Define `data-accent` → color rules for the accent set. complexity: [low]
- [ ] T10.6 EchoComponent → `data-accent` (orange); px → utilities. complexity: [low]
- [ ] T10.7 ErrorComponent → `data-accent` (red). complexity: [low]
- [ ] T10.8 ConfirmationPromptComponent → `data-accent` (yellow). complexity: [low]
- [ ] T10.9 ChatboxComponent: caret-color via class; px → utilities. complexity: [low]
- [ ] T10.10 MiniStatusComponent: accents via class. complexity: [low]
- [ ] T10.11 Cursor::Component (if kept): via class/attr. complexity: [low]
- [ ] T10.12 Palette::*: inline → utilities. complexity: [low]
- [ ] T10.13 Sidebar::Component + SectionComponent: → utilities. complexity: [low]
- [ ] T10.14 StartScreen::Component: colors via class. complexity: [low]
- [ ] T10.15 Confirm `git grep -nE 'style="' app/components` → ideally zero. complexity: [low]
- [ ] T10.16 `bin/dev`: `/` + start screen unchanged. complexity: [manual]
- [ ] T10.17 Commit: `Freeze component CSS`. complexity: [manual]

## P11 — Factories for every model + traits
- [ ] T11.1 Audit `spec/factories/` vs models; list missing. complexity: [low]
- [ ] T11.2 Factory `channel` (+ `:with_videos`, `:on_connection`). complexity: [low]
- [ ] T11.3 Factory `video` (+ `:scheduled`/`:public`/`:private`). complexity: [low]
- [ ] T11.4 Factory `video_preview` (+ `:published`/`:failed`; thumbnail attach). complexity: [low]
- [ ] T11.5 Factory `game` (+ `:with_ratings`/`:tba`/`:unreleased`/`:with_score`). complexity: [low]
- [ ] T11.6 Factory `footage` (game required; + `:needs_grading`/`:portrait`/`:with_audio_tracks`). complexity: [low]
- [ ] T11.7 Factory `company`. complexity: [low]
- [ ] T11.8 Factory `genre`. complexity: [low]
- [ ] T11.9 Factories for join models. complexity: [low]
- [ ] T11.10 Factory `app_setting` (singleton + key/value + TOTP traits). complexity: [low]
- [ ] T11.11 Factory `totp_backup_code` (+ `:used`). complexity: [low]
- [ ] T11.12 Factory `youtube_connection` (+ `:needs_reauth`). complexity: [low]
- [ ] T11.13 Factory `conversation` (+ `:named`); refresh `turn`/`event`. complexity: [low]
- [ ] T11.14 Commit: `Factories for every model with traits`. complexity: [manual]

## P12 — Auto-validating factories_spec
- [ ] T12.1 `spec/models/factories_spec.rb`: each factory builds valid. complexity: [low]
- [ ] T12.2 Extend: each trait builds valid. complexity: [low]
- [ ] T12.3 Run; fix failures. complexity: [low]
- [ ] T12.4 Commit: `Self-validating factories spec`. complexity: [manual]

## P13 — Rake reorg + seeds prepare/populate
- [ ] T13.1 Empty `db/seeds.rb`. complexity: [low]
- [ ] T13.2 Map surviving tasks → `pito:test:*` / `pito:tools:*`; record tree. complexity: [low]
- [ ] T13.3 `pito:test:seeds:prepare` — snapshot current DB rows → seed files. complexity: [high]
- [ ] T13.4 `pito:test:seeds:populate` — drop existing + load prepared seeds. complexity: [high]
- [ ] T13.5 `test_broadcast` → `pito:test:broadcast`. complexity: [low]
- [ ] T13.6 `test_panel_seeds` (+ clear) → `pito:test:panels:*`. complexity: [low]
- [ ] T13.7 auth/TOTP → `pito:tools:auth:*`. complexity: [low]
- [ ] T13.8 state → `pito:tools:state:*`. complexity: [low]
- [ ] T13.9 config → `pito:tools:config:*`. complexity: [low]
- [ ] T13.10 cleanup/assets/cover_arts → `pito:tools:{cleanup,assets,cover_arts}:*`. complexity: [low]
- [ ] T13.11 `games:backfill_scores` → `pito:tools:games:*`. complexity: [low]
- [ ] T13.12 `pito:tools:db:dump` + `:restore`. complexity: [low]
- [ ] T13.13 Update initializers/docs invoking renamed tasks. complexity: [low]
- [ ] T13.14 Confirm `bin/rails -T pito` → only `pito:test:*` + `pito:tools:*`. complexity: [manual]
- [ ] T13.15 Commit: `Rake reorg + seeds prepare/populate`. complexity: [manual]

## P14 — Rake task specs
- [ ] T14.1 Rake-spec helper. complexity: [low]
- [ ] T14.2 Spec `pito:test:seeds:prepare`/`populate` (round-trip). complexity: [low]
- [ ] T14.3 Spec `pito:tools:auth:*`. complexity: [low]
- [ ] T14.4 Spec `pito:tools:state:*`. complexity: [low]
- [ ] T14.5 Spec `pito:tools:db:dump`/`restore` (stubbed). complexity: [low]
- [ ] T14.6 Spec `pito:tools:games:backfill_scores`. complexity: [low]
- [ ] T14.7 `rspec` rake specs green. complexity: [manual]
- [ ] T14.8 Commit: `Specs for pito:test / pito:tools`. complexity: [manual]

## P15 — ffprobe footage probe
- [ ] T15.1 `Pito::Footage::Probe.call(path:)` → ffprobe JSON + parse. complexity: [high]
- [ ] T15.2 Map → resolution, fps (eval `r_frame_rate`), bit_depth, duration_seconds, aspect_ratio, orientation. complexity: [high]
- [ ] T15.3 Compute `needs_grading` (false only for BT.709 + BT.709/SMPTE170M). complexity: [high]
- [ ] T15.4 Build `audio_track_names` (tags.title/language; fallback `track N`). complexity: [low]
- [ ] T15.5 Guard missing ffprobe / file. complexity: [low]
- [ ] T15.6 RSpec `Probe` spec (HDR-4K + SDR-1080p fixtures). complexity: [low]
- [ ] T15.7 `pito:tools:probe` task: parse `game=N` + path; `File.expand_path`. complexity: [low]
- [ ] T15.8 Upsert `Footage` by `[game_id, filename]`. complexity: [low]
- [ ] T15.9 Progress: `==> probing <file>` + summary; `i/total` for globs. complexity: [low]
- [ ] T15.10 RSpec task spec. complexity: [low]
- [ ] T15.11 Manual: real clip → row + summary. complexity: [manual]
- [ ] T15.12 Commit: `ffprobe probe + pito:tools:probe`. complexity: [manual]

## P16 — Probe-command copyable snippet component
- [ ] T16.1 Add `Pito::Footage::ProbeCommandComponent` (copyable command block). complexity: [low]
- [ ] T16.2 `clipboard` Stimulus controller (click + keyboard). complexity: [low]
- [ ] T16.3 Pin/register. complexity: [low]
- [ ] T16.4 Component spec. complexity: [low]
- [ ] T16.5 i18n under `config/locales/pito/footage/en.yml`. complexity: [low]
- [ ] T16.6 Commit: `Probe-command snippet component`. complexity: [manual]

## P17 — Conversation uuid + routing
- [ ] T17.1 `GET /` → start screen. complexity: [low]
- [ ] T17.2 `GET /chat/:uuid` → `ConversationsController#show` (by uuid). complexity: [low]
- [ ] T17.3 `#show` loads ordered `@events`. complexity: [low]
- [ ] T17.4 `POST /chat`: on first message create a Conversation (uuid); return uuid. complexity: [high]
- [ ] T17.5 Cable stream → `pito:conversation:<uuid>`. complexity: [low]
- [ ] T17.6 `current_conversation` resolves by uuid param. complexity: [high]
- [ ] T17.7 Request specs: `/chat/:uuid` renders; unknown uuid → 404. complexity: [low]
- [ ] T17.8 Commit: `Conversation uuid + /chat/:uuid routing`. complexity: [manual]

## P18 — Root start screen
- [ ] T18.1 `/` renders centered chatbox + logo. complexity: [low]
- [ ] T18.2 No scrollback on `/`. complexity: [low]
- [ ] T18.3 Chatbox form on `/` posts to `POST /chat`. complexity: [low]
- [ ] T18.4 Smoke. complexity: [manual]
- [ ] T18.5 Commit: `Root / = centered start screen`. complexity: [manual]

## P19 — Caret rework
- [ ] T19.1 Evaluate `Cursor::Component` vs a real caret; record verdict. complexity: [high]
- [ ] T19.2 If unsuitable: real caret on the chatbox `<textarea>`/input. complexity: [high]
- [ ] T19.3 Hint only when empty; caret at the hint's first char when empty. complexity: [high]
- [ ] T19.4 Caret follows after last typed char. complexity: [low]
- [ ] T19.5 Caret color via token/class. complexity: [low]
- [ ] T19.6 Remove fake-cursor component if dropped. complexity: [low]
- [ ] T19.7 Smoke. complexity: [manual]
- [ ] T19.8 Commit: `Real caret over hint / following input`. complexity: [manual]

## P20 — Chatbox border-top hack → proper scroll
- [ ] T20.1 Document the 20px border-top hack + why. complexity: [low]
- [ ] T20.2 Replace with scroll-padding / scroll-margin / spacer. complexity: [high]
- [ ] T20.3 Remove the hack. complexity: [low]
- [ ] T20.4 Smoke: long scroll never collides. complexity: [manual]
- [ ] T20.5 Commit: `Proper chatbox/scrollback spacing`. complexity: [manual]

## P21 — Auto-scroll on send
- [ ] T21.1 On submit + on each appended event, scroll to newest. complexity: [low]
- [ ] T21.2 Respect "scrolled up". complexity: [high]
- [ ] T21.3 Smoke. complexity: [manual]
- [ ] T21.4 Commit: `Auto-scroll scrollback on send`. complexity: [manual]

## P22 — First-message transition
> Enter → animate → bottom → reveal scrollback → Dots → **URL → /chat/:uuid** → then POST.
- [ ] T22.1 Stimulus `pito--home-transition`: on Enter (empty conversation) `preventDefault`. complexity: [low]
- [ ] T22.2 Animate the centered chatbox down to the bottom bar. complexity: [high]
- [ ] T22.3 Reveal the empty scrollback as the chatbox lands. complexity: [low]
- [ ] T22.4 Make the bottom-left Dots indicator visible at transition end. complexity: [low]
- [ ] T22.5 Create the conversation + `history.pushState` to `/chat/:uuid` (keep streamed DOM). complexity: [high]
- [ ] T22.6 Only AFTER the URL change, POST the message. complexity: [high]
- [ ] T22.7 Subsequent messages skip the transition. complexity: [low]
- [ ] T22.8 Smoke. complexity: [manual]
- [ ] T22.9 Commit: `Home→chat first-message transition`. complexity: [manual]

## P23 — Async dispatch + turn timing
> Echo immediate; result via a job; backend elapsed. **Persist-before-broadcast** so refresh conserves the conversation.
- [ ] T23.1 On POST: create Conversation (if new) + Turn; stamp `started_at`; **persist the echo Event first**. complexity: [high]
- [ ] T23.2 Then broadcast the echo to cable. complexity: [low]
- [ ] T23.3 Read TAB channel + Shift+TAB period from params; pass as context. complexity: [low]
- [ ] T23.4 Enqueue `ChatDispatchJob(turn, channel:, period:)`. complexity: [high]
- [ ] T23.5 Controller responds 204 right after enqueue. complexity: [low]
- [ ] T23.6 Job materializes result events: **persist first**, stamp `completed_at`, then broadcast. complexity: [high]
- [ ] T23.7 Result broadcast includes `elapsed_seconds`. complexity: [low]
- [ ] T23.8 Refresh smoke: mid-thinking → echo conserved; after → echo + result conserved. complexity: [manual]
- [ ] T23.9 Request/job specs. complexity: [high]
- [ ] T23.10 Commit: `Async dispatch, persist-before-broadcast, turn timing + context`. complexity: [manual]

## P24 — Echo confirmation Segment
> Appears only after the transition + URL change (P22).
- [ ] T24.1 Echo renders as a Segment with the proper accent (slash vs chat). complexity: [low]
- [ ] T24.2 Content = the exact submitted command/message. complexity: [low]
- [ ] T24.3 Verify it appears only post-transition. complexity: [manual]
- [ ] T24.4 Commit: `Echo confirmation Segment`. complexity: [manual]

## P25 — Braille thinking indicator + dictionaries
> Under the echo; cycles words; resolves to "<Word> for <backend elapsed>s".
- [ ] T25.1 Stimulus `pito--thinking`: Braille spinner + status word, from echo until result. complexity: [high]
- [ ] T25.2 **Slash** dictionary: Executing, Dispatching, Running, Resolving, Fetching, Querying, Computing, Crunching, Assembling, Routing, Parsing, Processing. complexity: [low]
- [ ] T25.3 **Chat** dictionary: Thinkering, Pondering, Digesting, Musing, Reasoning, Contemplating, Deliberating, Ruminating, Considering, Reflecting, Brewing, Wondering. complexity: [low]
- [ ] T25.4 Past-tense completion forms per dictionary. complexity: [low]
- [ ] T25.5 Both dictionaries in i18n/config (not hardcoded in JS). complexity: [low]
- [ ] T25.6 Pick the dictionary by leading `/`. complexity: [low]
- [ ] T25.7 Cycle words while waiting; stop on result. complexity: [high]
- [ ] T25.8 Replace with "<PastWord> for <elapsed_seconds>s". complexity: [low]
- [ ] T25.9 Manual: slash vs chat pick the right list; elapsed renders. complexity: [manual]
- [ ] T25.10 Commit: `Braille thinking indicator + dictionaries`. complexity: [manual]

## P26 — Result Segment
- [ ] T26.1 Result broadcasts a Segment with a distinct accent. complexity: [low]
- [ ] T26.2 Appears after the thinking indicator resolves. complexity: [low]
- [ ] T26.3 Refresh `/chat/:uuid` → echo + result persist in order. complexity: [manual]
- [ ] T26.4 Commit: `Distinct-accent result Segment`. complexity: [manual]

## P27 — `/connect` (OAuth, multi-channel)
- [ ] T27.1 `/connect` starts Google OAuth (reuse omniauth init). complexity: [high]
- [ ] T27.2 Callback finds-or-creates `YoutubeConnection` by `google_subject_id`. complexity: [low]
- [ ] T27.3 Fetch the account's manageable channels (YouTube API). complexity: [high]
- [ ] T27.4 Sidebar picker (keyboard + mouse); mark already-added. complexity: [high]
- [ ] T27.5 On select, create `Channel` under the connection (skip dupes). complexity: [low]
- [ ] T27.6 Allow multi-select + re-running `/connect` later. complexity: [low]
- [ ] T27.7 Result Segment confirms added channel(s). complexity: [low]
- [ ] T27.8 Specs (callback stubbed; created; deduped). complexity: [high]
- [ ] T27.9 Smoke. complexity: [manual]
- [ ] T27.10 Commit: `/connect OAuth + multi-channel picker`. complexity: [manual]

## P28 — `/disconnect @handle|id`
- [ ] T28.1 Resolve target channel by `@handle` or id. complexity: [low]
- [ ] T28.2 `confirmation_prompt` Segment describing the cascade. complexity: [low]
- [ ] T28.3 Wire `/confirm` / `/cancel`. complexity: [high]
- [ ] T28.4 On confirm: delete the channel + its videos. complexity: [low]
- [ ] T28.5 If last channel on its connection, delete the `YoutubeConnection`. complexity: [low]
- [ ] T28.6 Result Segment confirms removal. complexity: [low]
- [ ] T28.7 Specs. complexity: [low]
- [ ] T28.8 Smoke. complexity: [manual]
- [ ] T28.9 Commit: `/disconnect with confirmation + cascade`. complexity: [manual]

## P29 — TAB channel cycling
- [ ] T29.1 Provide the channel list (`@all` + each `@handle`) to the chatbox. complexity: [low]
- [ ] T29.2 Stimulus: TAB cycles `@all → @handle1 → … → @all`. complexity: [high]
- [ ] T29.3 Render the active channel token in the chatbox slot. complexity: [low]
- [ ] T29.4 Include the selected channel in submitted params. complexity: [low]
- [ ] T29.5 Smoke. complexity: [manual]
- [ ] T29.6 Commit: `TAB channel cycling`. complexity: [manual]

## P30 — Shift+TAB period cycling (UI only)
- [ ] T30.1 Stimulus: Shift+TAB cycles `7d → 28d → 1m → 3m → 1y → lifetime → 7d`. complexity: [low]
- [ ] T30.2 Render the active period token. complexity: [low]
- [ ] T30.3 Include the period in params (unwired downstream). complexity: [low]
- [ ] T30.4 Smoke. complexity: [manual]
- [ ] T30.5 Commit: `Shift+TAB period cycling (UI only)`. complexity: [manual]

## P31 — `/import videos` (smart incremental pull)
> Pull YouTube → `Video` (read-only mirror). Quota-aware. Channel from TAB; period is dead data (carried only).
- [ ] T31.1 `/import videos` handler reads the selected channels (TAB). (Period is carried but unused.) complexity: [low]
- [ ] T31.2 `@all` → one `ImportVideosJob` per channel; single channel → one. complexity: [low]
- [ ] T31.3 Per job: persist + broadcast a per-channel progress Segment. complexity: [low]
- [ ] T31.4 Progress Segment payload updated via Turbo Stream replace (targets its DOM id). complexity: [high]
- [ ] T31.5 `ImportVideosJob` walks the channel's uploads playlist newest-first (`playlistItems.list`), paginating. complexity: [high]
- [ ] T31.6 Batch `videos.list` only for new/changed ids; compare stored `etag`/checksum; skip unchanged. complexity: [high]
- [ ] T31.7 Stop paging after a run of K consecutive known-unchanged videos (incremental tail cutoff). complexity: [high]
- [ ] T31.8 Upsert `Video` (dedupe by `youtube_video_id`); store `etag` + `last_synced_at`. complexity: [low]
- [ ] T31.9 Update the progress Segment; summary (N new / M updated / skipped) on finish. complexity: [low]
- [ ] T31.10 Specs (stubbed API; incremental stop; checksum skip; dedupe; progress). complexity: [high]
- [ ] T31.11 Smoke: `@all` → multiple Segments; single → one. complexity: [manual]
- [ ] T31.12 Commit: `/import videos: smart incremental pull`. complexity: [manual]

## P32 — VideoPreview model + edit UI
> Stage edits without touching `Video`. Full edit experience this plan.
- [ ] T32.1 Confirm the `VideoPreview` model + `has_one_attached :thumbnail` (from P6). complexity: [low]
- [ ] T32.2 Edit surface: `/edit video <id>` opens the edit form for that video (or `/edit video` with no id opens the video picker, reusing P34's). complexity: [high]
- [ ] T32.3 Form fields (YouTube Studio parity): title, description, tags, category + game title, made-for-kids (Yes/No), paid promotion, AI/altered-content (Yes/No), allow embedding, allow automatic chapters, allow automatic places, allow automatic concepts, notify subscribers, Shorts remixing, thumbnail upload (Active Storage). complexity: [high]
- [ ] T32.4 Save creates/updates a `VideoPreview` (status `draft`); never mutates `Video`. complexity: [low]
- [ ] T32.5 Show a diff/preview of the draft vs current `Video` values. complexity: [high]
- [ ] T32.6 Thumbnail preview render (the uploaded image). complexity: [low]
- [ ] T32.7 Stimulus for the form (keyboard + mouse). complexity: [high]
- [ ] T32.8 i18n all copy. complexity: [low]
- [ ] T32.9 Model/component/request specs. complexity: [low]
- [ ] T32.10 Smoke: compose a preview; persists as draft; `Video` unchanged. complexity: [manual]
- [ ] T32.11 Commit: `VideoPreview model + edit UI`. complexity: [manual]

## P33 — `/update videos` (publish previews → re-import)
> Push pending VideoPreviews to YouTube; on success re-import that video. Per-channel fan-out + progress Segments.
- [ ] T33.1 `/update videos` handler reads channels + period; collects pending (`draft`) previews in scope. complexity: [low]
- [ ] T33.2 Per channel → one `PublishPreviewsJob` + one progress Segment (reuse P31's fan-out helper). complexity: [low]
- [ ] T33.3 Job maps the preview → the **API-supported fields** and publishes (`videos.update` snippet/status + `thumbnails.set`); flags staged Studio-only fields as not-published; status `publishing` → `published`/`failed`. complexity: [high]
- [ ] T33.4 On each success → enqueue a single-video `ImportVideosJob` (`videos.list` by id) to refresh `Video`. complexity: [low]
- [ ] T33.5 On failure → mark `failed` + surface the error in the Segment. complexity: [low]
- [ ] T33.6 Progress Segment updates; summary (published / failed) on finish. complexity: [low]
- [ ] T33.7 Specs (stubbed API; publish → reimport enqueued; failure path). complexity: [high]
- [ ] T33.8 Smoke: edit a title/thumbnail → `/update videos` → YouTube updated → `Video` re-synced. complexity: [manual]
- [ ] T33.9 Commit: `/update videos: publish previews → re-import`. complexity: [manual]

## P34 — Video lifecycle (`/publish` `/schedule` `/unlist` `/delete`)
> Each command opens a **sidebar picker** of eligible videos → select → echo + async job → Braille → result Segment **with a link to the video**. Direct YouTube state changes (not via VideoPreview); re-import after; `/delete` removes the local mirror.
- [ ] T34.1 Shared video-picker sidebar: backend returns the eligible set for the command; render with keyboard + mouse selection (reuse the `Pito::Sidebar` picker pattern). complexity: [high]
- [ ] T34.2 `/publish` → picker of publishable videos (private/draft, unlisted, scheduled). complexity: [low]
- [ ] T34.3 On select → set privacy `public` on YouTube (`videos.update`). complexity: [high]
- [ ] T34.4 `/schedule` → same picker + an **additional date step** (pick publish date/time) → set privacy `private` + `status.publishAt`. complexity: [high]
- [ ] T34.5 `/unlist` → picker of public/unlisted videos → set privacy `unlisted`. complexity: [low]
- [ ] T34.6 After publish/schedule/unlist success → enqueue a single-video import to refresh `Video`. complexity: [low]
- [ ] T34.7 `/delete` → picker (any video) → `confirmation_prompt` Segment → on confirm `videos.delete`. complexity: [high]
- [ ] T34.8 On delete success → remove the local `Video` (+ dependent rows). complexity: [low]
- [ ] T34.9 Common flow: echo + dispatch async job → Braille thinking → result Segment **with a link to the video** when done. complexity: [low]
- [ ] T34.10 Specs (eligible-set per command; stubbed API state changes; schedule date; delete confirm). complexity: [high]
- [ ] T34.11 Smoke each command via the picker. complexity: [manual]
- [ ] T34.12 Commit: `Video lifecycle via picker (publish/schedule/unlist/delete)`. complexity: [manual]

## P35 — Re-wire IGDB services
> Backend mostly in tree (`game/igdb/*`, `game/search_service`, `pito/search/search_games`, jobs).
- [ ] T35.1 Verify IGDB credentials path (`Game::Igdb::TokenCache` / AppSetting / credentials). complexity: [low]
- [ ] T35.2 Smoke `Game::Igdb` client search (or stubbed spec). complexity: [high]
- [ ] T35.3 Confirm `Game::Igdb::SyncGame` populates a Game + recompute `score`. complexity: [high]
- [ ] T35.4 Confirm `Game::SearchService` / `Pito::Search::SearchGames` work. complexity: [low]
- [ ] T35.5 Add/fix specs (WebMock stubbed IGDB). complexity: [low]
- [ ] T35.6 Commit: `Re-wire + verify IGDB search/sync services`. complexity: [manual]

## P36 — `/add game` + sidebar search UI
> Rebuild the dropped search UI as a sidebar. Adds to the global game library.
- [ ] T36.1 `/add game` opens the sidebar in "game search" mode. complexity: [low]
- [ ] T36.2 Sidebar search box; min-char gate; debounce. complexity: [low]
- [ ] T36.3 Search endpoint returns IGDB matches (+ flag already-in-DB). complexity: [high]
- [ ] T36.4 Render results; in-DB rows get a marker. complexity: [low]
- [ ] T36.5 Keyboard nav (↑/↓ + Enter) + mouse click select a result. complexity: [high]
- [ ] T36.6 Selecting a result shows its game details in the sidebar. complexity: [high]
- [ ] T36.7 Reuse `Pito::Sidebar::*`; i18n all copy. complexity: [low]
- [ ] T36.8 Component/request specs. complexity: [low]
- [ ] T36.9 Smoke. complexity: [manual]
- [ ] T36.10 Commit: `/add game sidebar search UI`. complexity: [manual]

## P37 — Add → async sync-once
- [ ] T37.1 "Add" creates a Game stub from the IGDB result (igdb_id, title) in the global library. complexity: [low]
- [ ] T37.2 Enqueue `GameIgdbSync(game)` **once** (full details + score + Voyage index). complexity: [low]
- [ ] T37.3 Dedupe: adding an already-in-DB game is a no-op (marker informs the UI). complexity: [low]
- [ ] T37.4 Confirmation Segment / sidebar update on completion. complexity: [low]
- [ ] T37.5 Job spec. complexity: [low]
- [ ] T37.6 Smoke. complexity: [manual]
- [ ] T37.7 Commit: `Add game → async one-shot IGDB sync`. complexity: [manual]

## P38 — Daily unreleased-games refresh
- [ ] T38.1 Confirm `game_igdb_nightly_refresh.rb`; scope to **not-yet-released** games (P8 fields). complexity: [high]
- [ ] T38.2 Register as a recurring daily job (SolidQueue `config/recurring.yml`). complexity: [low]
- [ ] T38.3 On refresh: re-sync release info + recompute `score`; stop once released. complexity: [low]
- [ ] T38.4 Job spec. complexity: [low]
- [ ] T38.5 Smoke. complexity: [manual]
- [ ] T38.6 Commit: `Daily refresh for unreleased games`. complexity: [manual]

## P39 — `/new`
- [ ] T39.1 `/new` creates a fresh Conversation (uuid, "Unnamed N"). complexity: [low]
- [ ] T39.2 Navigate to its `/chat/:uuid` (empty). complexity: [low]
- [ ] T39.3 Spec. complexity: [low]
- [ ] T39.4 Smoke. complexity: [manual]
- [ ] T39.5 Commit: `/new conversation`. complexity: [manual]

## P40 — `/resume` (sidebar picker)
- [ ] T40.1 `/resume` opens the sidebar listing conversations. complexity: [low]
- [ ] T40.2 Keyboard (↑/↓ + Enter) + mouse selection. complexity: [high]
- [ ] T40.3 Current conversation marked; picking it is a no-op. complexity: [low]
- [ ] T40.4 Picking another navigates to its `/chat/:uuid`. complexity: [low]
- [ ] T40.5 Spec/manual. complexity: [manual]
- [ ] T40.6 Commit: `/resume conversation picker`. complexity: [manual]

## P41 — Sidebar conversation list (grouping + timestamps)
- [ ] T41.1 Query: conversations by last activity. complexity: [low]
- [ ] T41.2 "Recent" = within 24h of the most recent conversation's last activity; hairline; then the rest. complexity: [high]
- [ ] T41.3 Render each row: `display_name` + timestamp. complexity: [low]
- [ ] T41.4 Relative wording < 1 week (reuse `Pito::Formatter`); absolute `May 18, 2026` beyond. complexity: [low]
- [ ] T41.5 Component spec. complexity: [low]
- [ ] T41.6 Commit: `Sidebar conversation list with recency grouping`. complexity: [manual]

## P42 — Conversation rename + "Unnamed N"
- [ ] T42.1 New conversations default `title` to `"Unnamed #{next_index}"`. complexity: [low]
- [ ] T42.2 Inline rename affordance (keyboard + mouse). complexity: [high]
- [ ] T42.3 `PATCH /chat/:uuid` updates `title`. complexity: [low]
- [ ] T42.4 Re-render the sidebar row (Turbo). complexity: [low]
- [ ] T42.5 Spec; smoke. complexity: [manual]
- [ ] T42.6 Commit: `Conversation rename + Unnamed N`. complexity: [manual]

## P43 — AGENTS.md conventions
- [ ] T43.1 Add `## Auth` section — cookie session (24h idle, no hard max), no Session model, TOTP retained. complexity: [low]
- [ ] T43.2 Add `## Factories` section — every model; `factories_spec` auto-validates. complexity: [low]
- [ ] T43.3 Add `## Rake` section — `pito:test:*` / `pito:tools:*`; seeds prepare/populate; specced. complexity: [low]
- [ ] T43.4 Add `## Component CSS` section — `data-accent`; no inline `style=`. complexity: [low]
- [ ] T43.5 Add `## Footage / ffprobe` section — Probe, `pito:tools:probe`, needs_grading/orientation. complexity: [low]
- [ ] T43.6 Add `## Dispatch` section — async, persist-before-broadcast, turn timing, backend elapsed, command context (channel used, period dead). complexity: [low]
- [ ] T43.7 Add `## Conversations` section — uuid routing, naming, sidebar grouping, `/new`/`/resume`. complexity: [low]
- [ ] T43.8 Add `## Chatbox` section — TAB channels, Shift+TAB periods (dead), thinking indicator + dictionaries. complexity: [low]
- [ ] T43.9 Add `## Videos` section — read-only mirror; smart `/import`; `VideoPreview` + `/edit video`; `/update` publish→re-import; lifecycle `/publish`/`/schedule`/`/unlist`/`/delete`. complexity: [low]
- [ ] T43.10 Add `## Games` section — IGDB search sidebar, `/add game`, async sync, nightly unreleased refresh. complexity: [low]
- [ ] T43.11 Add `## Analytics namespaces` section — `Pito::Stats` vs `Pito::Analytics` (directional). complexity: [low]
- [ ] T43.12 Commit: `AGENTS.md conventions`. complexity: [manual]

## P44 — Verification & cleanup
- [ ] T44.1 `rspec` green everywhere. complexity: [manual]
- [ ] T44.2 `bin/rails -T pito` → only `pito:test:*` + `pito:tools:*`. complexity: [manual]
- [ ] T44.3 `git grep -nE 'style="' app/components` → zero/documented. complexity: [manual]
- [ ] T44.4 `git grep -ni 'meili\|extras/cli\|/_ui\|rack.?attack\|local_path\|external_steam_app_id\|\bSession\b'` → zero. complexity: [manual]
- [ ] T44.5 `/` → type → transition → URL `/chat/:uuid` → echo → thinking → result; refresh conserves it. complexity: [manual]
- [ ] T44.6 `/connect` adds a channel; `/disconnect` removes it (+ orphan connection); TAB/Shift+TAB cycle. complexity: [manual]
- [ ] T44.7 `/import videos @all` → one progress Segment per channel; incremental + checksum skip works. complexity: [manual]
- [ ] T44.8 Edit a video → `VideoPreview` draft (Video unchanged) → `/update videos` → YouTube updated → re-imported. complexity: [manual]
- [ ] T44.9 `/publish`/`/schedule`/`/unlist` change YouTube state + re-import; `/delete` confirms + removes. complexity: [manual]
- [ ] T44.10 `/add game` searches IGDB, adds a game (async sync); unreleased game refreshes daily. complexity: [manual]
- [ ] T44.11 `/new`/`/resume`/rename work; sidebar grouping correct. complexity: [manual]
- [ ] T44.12 `pito:tools:probe` populates a Footage. complexity: [manual]
- [ ] T44.13 Commit: `Plan 4 verification`. complexity: [manual]

---

## Open questions / needs clarification

1. **`release_year` + `igdb_checksum` (P8):** both decided by the P8 investigation.
2. **`needs_grading` rule:** validate against real ffprobe output (you'll test + feed back).
3. **VideoPreview API support (P32/P33):** the full Studio field set is now confirmed (screenshots). Verify per field which are writable via the YouTube **Data API v3** `videos.update` (title/description/tags/categoryId, `status.embeddable`, `status.selfDeclaredMadeForKids`, AI/synthetic-media disclosure, `publishAt`/privacy) vs **Studio-only** (paid promotion, automatic chapters/places/concepts, Shorts remixing, notify subscribers) — Studio-only fields can be staged in a preview but not auto-published.

_Resolved this round:_ video commands = `/import` + `/update` + lifecycle `/publish`/`/schedule`/`/unlist`/`/delete`; `Video` + `Channel` read-only mirrors, `Playlist` dropped; smart import (etag/checksum + incremental); VideoPreview field set matches Studio (screenshots); VideoPreview edit via `/edit video <id>`; `/add game` → global library; **period is dead data**; **cookie 24h idle, no hard max**; Active Storage on; transition approved (must feel live/cool); **video targeting = sidebar picker** (`/publish`/`/schedule`/`/unlist`/`/delete` pick eligible videos; `/schedule` adds a date step; result links to the video).

## Still to cover (not yet discussed)

- **Chat box autocomplete / autosuggestions** (deferred — discuss later).
- Further UI enhancements beyond those listed.
- `Pito::Stats` design (daily snapshot tables/jobs for channel + video totals).
- `Pito::Analytics` (wire TAB channel + Shift+TAB period into real queries).
- Real chat/slash domain handlers (list videos, channel overview…).
- Games detail screen (host for ScoreBar + TTB + probe snippet + `/add game` detail pane).
- A **videos list screen** (host for `/edit video` + lifecycle actions + a friendlier video target picker).

## Open follow-ups (explicitly later)

- `Pito::Stats` / `Pito::Analytics` plans; wire TAB/period.
- Games detail screen; videos list screen.
- `Calendar`/`CalendarEntry`, `Notification` models — add when needed. (Playlist dropped — not supported.)
- Remote footage ingest (script + HTTP endpoint) if/when on Hetzner.
- At merge: delete `plan-beta-reboot-*.md`; fold durable content into `architecture.md` / `design.md` / `installation.md` / `tools.md`.

## How to use this plan

1. Draft — expect revisions as "Still to cover" lands.
2. Next unchecked task in phase order. `[low]` → cheap model; `[high]` → Sonnet/Catalin; `[manual]` → operator.
3. Implement, verify (diff + affected spec/flow), check the box.
4. Commit at each phase's commit task — plain message, no `[skipci]`.
5. Split anything bigger than 5 minutes.
6. **P0 (Pre-flight) is exempt from the commit-gate rule** — it is verification-only and produces no code, so it has no `Commit:` task. Every other phase ends with one.
