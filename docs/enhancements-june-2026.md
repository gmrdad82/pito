# Pito enhancements — June 2026

## Context

Sixteen user-reported enhancements and fixes gathered after manual testing on the
live `app.pitomd.com` tunnel. They span: removing the unwanted expandable
(`ctrl+|`) message feature; infra fixes for off-localhost use (images on any
host, `m` reachable unauthenticated, sidebar dismissal); richer `show video` /
`show game` messages (slim linked-game card, linked-videos table, stats
placeholders, similar-game score bars); list-table polish (right-aligned id
heading, columns that re-trim instead of breaking); a daily release-countdown
notification (replacing a buggy summary that fired for a date-less game); and a
documentation/dead-code cleanup (strip plan tags from comments, audit dead code,
collapse the three injected MD docs into one lean CLAUDE.md).

## North star

`show video` / `show game` produce richer, host-agnostic, fully-expanded
messages; the chat works correctly off localhost (relative images, `m` for
everyone, sidebar dismissed on start/404); list tables stay within bounds with
right-aligned `#` headings; `show game` gains a repliable linked-videos table, a
stats placeholder, and similar-game score bars; `show video` gains a repliable
slim linked-game card; upcoming games send a witty daily countdown reminder once
dated within 30 days; and the repo's always-injected guidance is a single lean
CLAUDE.md (AGENTS.md + EXTRA.md gone), with source comments free of internal plan
tags and dead code audited out.

## Locked decisions

| Topic | Decision |
| --- | --- |
| Expand removal | Delete `pito--expand`, `ExpandableBodyComponent`, and the expand-all setting/route; render previously-collapsed detail (error backtraces, /help sections, confirmation stats) **always-visible**. |
| Images on any host | ActiveStorage **proxy delivery** + **relative (host-less)** image paths via a `Pito::ImagePath` helper. |
| `m` behaviour | When the sidebar is active, `m` **dismisses** it; otherwise `m` **focuses the chatbox** — for everyone (drop the `isAuthenticated()` gate); the in-input guard stays. |
| Sidebar dismiss | Public `dismiss()` on `resume_controller` (reuses `#clear()`); fired by the `m` handler and by the start screen / 404 on connect. |
| Linked videos (show game) | Full repliable list table reusing `Video::List` filtered to `game.linked_videos` (video_list follow-up). |
| Linked-game card (show video) | New slim card (cover left, kv-table right), repliable via the existing **`game_detail`** target. |
| Stats & Analytics | Placeholder enhanced message, mirroring `Video::Enhanced`, added to `show game`. |
| `show game` order | detail → linked-videos → stats&analytics → recommendations (recs gain similar-game score bars). |
| `show video` order | detail → linked-game card → stats&analytics placeholder. |
| List id heading | Right-align the `#` heading in both lists. |
| Grid on column change | Bound `.pito-data-grid` to available width + tier per-cell caps by `data-cols` so columns trim instead of breaking. |
| Release countdown (notif) | A new **daily** job: for each game with a **present** release_date within the next 30 days, create **one notification per game per day** — a countdown reminder via a **50-variant `Pito::Copy`** dictionary. Removes the buggy date-less `releasing_30d` summary path. |
| Stellar Blade notif | No delete task — `CleanupNotificationsJob` purges it 7 days after the user marks it read. |
| Comment sweep | Strip plan/phase/task tags from **comments only** (never code identifiers); keep the prose. |
| Dead-code audit | **Report first**: produce a findings list for user sign-off; removals only after approval. |
| Docs consolidation | Collapse into **one lean CLAUDE.md**; **delete AGENTS.md + EXTRA.md**. Keep main conventions + skills + **condensed** stack sections; drop the heavy plan ceremony (sign-off/audit-mode), duplications, and vendor/ticket/MCP cruft (FPR-####, JIRA, Slack). |

## Complexity hints

| Hint | Meaning |
| --- | --- |
| `[manual]` | Operator by hand: smoke tests, grep audits, user approval, commits. |
| `[low]` | Mechanical CSS / markup / single-file edits, or plumbing that follows an existing pattern. |
| `[high]` | Layout restructure, ActiveStorage plumbing, component-tree surgery, cross-cutting removals, doc rewrites. |

## Phase index

- P0 — Remove the expandable (`ctrl+|`) feature; keep detail always-shown
- P1 — Serve attachment images from any host (proxy + relative URLs)
- P2 — Sidebar dismiss + `m` (focus chat / dismiss sidebar), unauthenticated
- P3 — Right-align the `#` id heading in list videos/games
- P4 — Re-evaluate column widths on add/remove so the grid never breaks
- P5 — Similar-game score bars under `show game`
- P6 — `show game`: repliable linked-videos list table
- P7 — `show game`: Stats & Analytics placeholder message
- P8 — `show video`: slim repliable linked-game card
- P9 — Daily release-countdown notifications
- P10 — Strip plan/phase/task references from source comments
- P11 — Dead-code audit (report-first)
- P12 — Consolidate docs into one lean CLAUDE.md (delete AGENTS.md + EXTRA.md)
- P13 — Refresh docs/architecture.md + audit README for dead doc links
- P14 — Confirmation & sync message timestamps (reported bugs)
- P15 — `import videos`: detect & import new videos (reported bug)
- P16 — Sidebar focus model: blur chatbox on open; m/Esc dismiss (reported bug)
- P17 — Consume prior #hashtags when a new (non-reply) message is sent
- P18 — `shift+r` opens a picker of the last command's #hashtags
- P19 — `import videos`: one job + one message per channel (+ reauth surfacing)
- P20 — Channel-item stats: compact numbers + S/V/v labels + legend
- P21 — `list channels`: append an Enhanced message for channels needing reauth
- P22 — Nightly job: notify per channel that needs reauth
- P23 — Auto-import videos only for newly connected channels (not on re-auth)
- P24 — Clean up the "already connected" connect message + redo its ASCII art
- P25 — Add the Synthwave dark theme
- P26 — `platform` verb: set a game's platform (normalized to a logo)
- P27 — Replace the test-seeds tasks with a `pito:tools:backup` task (sql + voyage + assets)
- P28 — BUG: `link`/`unlink` multi-target reply to list cards is broken
- P29 — `show game`: up to 6 similar games (match the channel row)
- P30 — Halve the page left/right margins
- P31 — BUG: prior list "replays" when a new command consumes it (DONE)
- P32 — `show game` linked-videos: drop "Footage", use vids/vid, include the listing
- P33 — platform --help + show game/video detail kv-table refinements
- P34 — User timezone: `/config timezone=City` + render timestamps in local time
- P35 — Schedule natural-language time parser (in/tomorrow/at/for + 30-min guard)

## P0 — Remove the expandable (`ctrl+|`) feature; keep detail always-shown

- [x] T0.1 Rewrite `app/components/pito/event/system_component.html.erb` to render body, `sections`, and detail always-visible — drop the `pito--expand` wrapper, both hints, and the detail/hintAfter targets. complexity: [high]
- [x] T0.2 Simplify `app/components/pito/event/system_component.rb` — remove `expandable?` and expand-only branching; keep sections/detail as plain data. complexity: [high]
- [x] T0.3 Inline the error detail always-visible in `app/components/pito/event/error_component.html.erb` (drop the wrapper + `ctrl+|` hint). complexity: [low]
- [x] T0.4 Simplify `app/components/pito/event/error_component.rb` to stop driving an expand wrapper. complexity: [low]
- [x] T0.5 Render confirmation stats always-visible in `app/components/pito/event/confirmation_component.html.erb`. complexity: [low]
- [x] T0.6 Simplify `app/components/pito/event/confirmation_component.rb` — remove `expandable?`/`expand_detail` gating (keep the stats data). complexity: [low]
- [x] T0.7 Remove expand-param forwarding from `app/components/pito/event/enhanced_component.html.erb`. complexity: [low]
- [x] T0.8 Delete `expandable_body_component.rb` + `.html.erb`, replacing remaining callers with a plain body render. complexity: [high]
- [x] T0.9 Delete `app/javascript/controllers/pito/expand_controller.js` and unregister it from the Stimulus index. complexity: [low]
- [x] T0.10 Remove the expand-all settings action, its route, and any stored expand-all default (grep `expand_all`). complexity: [high]
- [x] T0.11 Remove dead expand copy (`expand_hint`/`collapse_hint`/`more_hint`/`fewer_hint`) from the locales. complexity: [low]
- [x] T0.12 Update the `expandable_body`/`error`/`confirmation`/`system` component specs to the always-visible markup. complexity: [low]
- [x] T0.13 Delete `spec/javascript/expand_controller.test.js` and expand assertions in slash/disconnect/help specs. complexity: [low]
- [x] T0.14 Run affected `bundle exec rspec` + `bin/rubocop` + `node --check`; confirm green. complexity: [manual]
- [x] T0.15 Commit: `Remove the expandable ctrl+| feature; render detail always-visible`. complexity: [manual]

## P1 — Serve attachment images from any host (proxy + relative URLs)

- [x] T1.1 Add `config/initializers/active_storage_proxy.rb` setting `config.active_storage.resolve_model_to_route = :rails_storage_proxy`. complexity: [high]
- [x] T1.2 Add a `Pito::ImagePath` service returning a host-less proxy path for a blob/variant via the AS proxy route helpers. complexity: [high]
- [x] T1.3 Render the cover via `Pito::ImagePath` in `game/detail_component.html.erb`. complexity: [low]
- [x] T1.4 Render the thumbnail via `Pito::ImagePath` in `video/detail_component.html.erb`. complexity: [low]
- [x] T1.5 Render the avatar via `Pito::ImagePath` in `channel/item_component.html.erb`. complexity: [low]
- [x] T1.6 Render the similar-game covers via `Pito::ImagePath` in `game/enhanced_component.html.erb`. complexity: [low]
- [x] T1.7 Audit remaining attachment `image_tag`/`*_url` sites (start-screen channels, sidebar/resume previews) and switch them to `Pito::ImagePath`. complexity: [low]
- [x] T1.8 Add a `Pito::ImagePath` spec asserting a relative `/rails/active_storage/...` path (no host). complexity: [low]
- [x] T1.9 Verify a rendered message has relative image `src` (no `http://localhost`); reload app.pitomd.com and confirm images load. complexity: [manual]
- [ ] T1.10 Commit: `Serve attachment images via relative proxy paths (host-agnostic)`. complexity: [manual]

## P2 — Sidebar dismiss + `m` (focus chat / dismiss sidebar), unauthenticated

- [x] T2.1 Add a public `dismiss()` action to `resume_controller.js` that calls the existing private `#clear()`. complexity: [low]
- [x] T2.2 Dispatch a `pito:resume:dismiss` window event on connect from `Pito::StartScreen::Component` (covers start screen + 404). complexity: [low]
- [x] T2.3 Listen for `pito:resume:dismiss` in `resume_controller.js` and call `dismiss()`. complexity: [low]
- [x] T2.4 Rework the `"m"` handler in `command_palette_controller.js`: if the sidebar is active → `dismiss()` it; else focus the chatbox — and remove the `isAuthenticated()` gate (keep the in-input guard). complexity: [high]
- [x] T2.5 Update any command-palette controller spec for the new `m` behaviour. complexity: [low]
- [ ] T2.6 Run `node --check`; smoke: `m` focuses chat (logged out too), `m` dismisses an open sidebar, and start/404 dismiss the sidebar without reopening on reload. complexity: [manual]
- [x] T2.7 Commit: `m focuses chat or dismisses the sidebar; dismiss sidebar on start/404`. complexity: [manual]

## P3 — Right-align the `#` id heading in list videos/games

- [x] T3.1 Give the `#` heading the right-align class in `video/list.rb` (`{ "text" => "#", "class" => "text-right" }`, matching `game/list.rb`). complexity: [low]
- [x] T3.2 Ensure the heading cell stretches so `text-right` takes effect in the `max-content` track (CSS in `application.css`); confirm both lists right-align `#`. complexity: [low]
- [x] T3.3 Update the games/videos list specs to assert the `#` heading carries the right-align class. complexity: [low]
- [x] T3.4 Commit: `Right-align the # id heading in list videos and games`. complexity: [manual]

## P4 — Re-evaluate column widths on add/remove so the grid never breaks

- [x] T4.1 Constrain `.pito-data-grid` to the available width in `application.css` (`max-width: 100%`, cells `min-width: 0`) so it never overflows the segment. complexity: [high]
- [x] T4.2 Add `data-cols`-tiered per-cell `max-width` overrides (root cause was the MISSING data-cols 9–12 grid rules → extended them; bounding + min-width:0 truncation handles narrow viewports, so tiered caps weren't needed). complexity: [high]
- [x] ~~T4.2 original~~ superseded by the line above (tighten title/genre/developer/publisher/game/channel caps as `data-cols` grows). complexity: [high]
- [ ] T4.3 Smoke `list videos` → `add comments` (and all columns) on a wide viewport: bounded with truncation, no break. complexity: [manual]
- [ ] T4.4 Smoke `list games` → `add genre, developer, publisher` (and all columns): bounded with truncation. complexity: [manual]
- [ ] T4.5 Commit: `Keep the list data-grid within bounds when columns change`. complexity: [manual]

## P5 — Similar-game score bars under `show game`

- [x] T5.1 Render `Pito::ScoreBarComponent.new(score: result.score, show_label: false)` under each similar-game card in `game/enhanced_component.html.erb`. complexity: [low]
- [x] T5.2 Widen the `.pito-game-enhanced-message__similar-games-strip` row gap in `application.css` so the score bubble clears the next row. complexity: [low]
- [x] T5.3 Update the game enhanced component spec to assert a score bar per similar-game card. complexity: [low]
- [ ] T5.4 Commit: `Score bar under each similar-game card in show game`. complexity: [manual]

## P6 — `show game`: repliable linked-videos list table

- [x] T6.1 Add `Pito::MessageBuilder::Game::LinkedVideos` calling `Video::List.call(game.linked_videos, conversation:, columns: %i[channel duration views comments likes])`. complexity: [high]
- [x] T6.2 Add a dim header/intro copy line for the linked-videos section via `Pito::Copy`. complexity: [low]
- [x] T6.3 Emit the linked-videos payload as an `:enhanced` event right after the detail in the `show game` branch of `handlers/show.rb`. complexity: [low]
- [x] T6.4 Omit the message when `game.linked_videos` is empty. complexity: [low]
- [x] T6.5 Add a spec: the linked-videos message is present and repliable (target `video_list`). complexity: [low]
- [ ] T6.6 Smoke `show game <id>`: repliable linked-videos table; `#<handle> show <video-id>` opens the video; `add/remove` columns work. complexity: [manual]
- [ ] T6.7 Commit: `show game: repliable linked-videos list table`. complexity: [manual]

## P7 — `show game`: Stats & Analytics placeholder message

- [x] T7.1 Add `Pito::MessageBuilder::Game::StatsPlaceholder` mirroring `Video::Enhanced`. complexity: [low]
- [x] T7.2 Add the `pito.copy.game.stats_placeholder` copy line. complexity: [low]
- [x] T7.3 Emit it as an `:enhanced` event between the linked-videos and recommendations messages in `handlers/show.rb`. complexity: [low]
- [ ] T7.4 Smoke the `show game` order: detail → linked-videos → stats&analytics → recommendations. complexity: [manual]
- [ ] T7.5 Commit: `show game: Stats & Analytics placeholder message`. complexity: [manual]

## P8 — `show video`: slim repliable linked-game card

- [x] T8.1 Add `Pito::Video::LinkedGameCardComponent` (slim): cover left + kv-table right (title, genres, perspective, theme, publisher, developer, release date, total footage), no TTB bar. complexity: [high]
- [x] T8.2 Render total footage as a TTB-pillar value via `Pito::Formatter::TtbHours.call(game.footages.sum(:duration_seconds))`. complexity: [low]
- [x] T8.3 Add the card CSS (cover left, kv-table right) reusing `Pito::Table::KeyValueRowComponent` + the `grid grid-cols-[max-content_1fr]` pattern. complexity: [low]
- [x] T8.4 Add `Pito::MessageBuilder::Video::LinkedGame` rendering the card for `video.linked_games.first`, stamping `game_id` + `make_followupable!(target: "game_detail")`. complexity: [high]
- [x] T8.5 Emit the card as an `:enhanced` event before the `Video::Enhanced` placeholder in the `show video` branch of `handlers/show.rb`. complexity: [low]
- [x] T8.6 Omit the card when the video has no linked game. complexity: [low]
- [x] T8.7 Add specs: the card renders the fields, and the flow emits it repliable via `game_detail`. complexity: [low]
- [ ] T8.8 Smoke `show video <id>`: slim linked-game card before the stats placeholder; `#<handle> show`/`reindex` act on the game. complexity: [manual]
- [ ] T8.9 Commit: `show video: slim repliable linked-game card`. complexity: [manual]

## P9 — Daily release-countdown notifications

- [x] T9.1 Remove the buggy date-less `releasing_30d` collection + reporting from `app/jobs/game_igdb_nightly_refresh.rb` (keep the changed/failures summary). complexity: [high]
- [x] T9.2 Add a `Pito::Notifications::Source::ReleaseCountdown` source that, for a game + days-remaining, builds a notification via a 50-variant `Pito::Copy` dictionary (embeds `%{n}` days + title). complexity: [high]
- [x] T9.3 Add the 50-variant countdown copy dictionary under `config/locales/pito/copy/` (witty `n`-days-until-release lines). complexity: [low]
- [x] T9.4 Add a daily `ReleaseCountdownJob` that selects games with a present `release_date` in `Date.current..(Date.current + 30.days)` and emits one countdown notification per game. complexity: [high]
- [x] T9.5 Guard against a duplicate same-day reminder per game (skip if one already exists for that game today). complexity: [low]
- [x] T9.6 Schedule `ReleaseCountdownJob` daily in `config/recurring.yml` (both environments). complexity: [low]
- [x] T9.7 Add a job spec: a game dated within 30 days gets a countdown notification; a date-less (TBA) game gets none; no duplicate same day. complexity: [low]
- [ ] T9.8 Run the affected specs + `bin/rubocop`; confirm green. complexity: [manual]
- [ ] T9.9 Commit: `Daily release-countdown notifications for upcoming games`. complexity: [manual]

## P10 — Strip plan/phase/task references from source comments

> Touch **comments only** — never code identifiers (e.g. the `p1:`/`p2:` payload
> keys). Delete header-only plan references whole; trim inline `(T17.4)` / `Plan
> P17` / `(rule 5)` tags and keep the prose.

- [ ] T10.1 Strip plan/phase/task tags from comments in `app/javascript/`. complexity: [low]
- [ ] T10.2 Strip from `app/components/` (heaviest: `time_to_beat_component.rb`). complexity: [low]
- [ ] T10.3 Strip from `app/services/channel/youtube/` and `app/services/game/igdb/`. complexity: [low]
- [ ] T10.4 Strip from `app/services/pito/` (chat, follow_up, message_builder, recommendations, suggestions). complexity: [low]
- [ ] T10.5 Strip from `app/services/` remainder (notifications, etc.). complexity: [low]
- [ ] T10.6 Strip from `app/jobs/`. complexity: [low]
- [ ] T10.7 Strip from `app/controllers/` (heaviest: `chat_controller.rb`). complexity: [low]
- [ ] T10.8 Strip from `app/models/` and `app/assets/` (CSS comments). complexity: [low]
- [ ] T10.9 Strip from `config/` comments. complexity: [low]
- [ ] T10.10 Strip plan/phase/task tags from `spec/` descriptions/comments (keep them meaningful). complexity: [low]
- [ ] T10.11 Grep audit for residual `Plan P`/`Phase`/`\bP\d+\b`/`\bT\d+\.\d+\b`/`rule \d` in comments; confirm only legitimate code remains. complexity: [manual]
- [ ] T10.12 Run `bundle exec rspec` + `bin/rubocop`; confirm green after edits. complexity: [manual]
- [ ] T10.13 Commit: `Strip plan/phase/task references from source comments`. complexity: [manual]

## P11 — Dead-code audit (report-first)

- [ ] T11.1 Sweep the codebase (rb/js/css/erb/yml + specs) for obsolete code from prior attempts — remnants of removed surfaces (Settings::*, MCP, Redis, Sidekiq, Meilisearch, Doorkeeper, old layouts/hooks), unreferenced files, orphaned specs — and write a findings report to `tmp/audits/dead-code.md` (file:line, why dead, removal risk). complexity: [high]
- [ ] T11.2 Review the report with the user; mark each finding keep / remove. complexity: [manual]
- [ ] T11.3 Remove the user-approved dead code (one cohesive deletion per area). complexity: [high]
- [ ] T11.4 Run `bundle exec rspec` + `bin/rubocop` + `node --check`; confirm green after removals. complexity: [manual]
- [ ] T11.5 Commit: `Remove audited dead code from prior attempts`. complexity: [manual]

## P12 — Consolidate docs into one lean CLAUDE.md (delete AGENTS.md + EXTRA.md)

- [ ] T12.1 Draft a lean "how we work + plan discipline" section: Opus plans / Sonnet implements, a plan is an atomic-task md file, commit per phase (no `[skipci]`, no co-author trailer, current branch), specs/coverage required — drop the sign-off/audit-mode ceremony and step-by-step procedures. complexity: [high]
- [ ] T12.2 Draft the pito architecture section condensed from AGENTS.md's pito-specific parts + EXTRA.md (dispatch, slash/chat/hashtag isolation, event payloads, copy engine, games/footage, namespace policy). complexity: [high]
- [ ] T12.3 Draft the visual + ViewComponent/Stimulus/Turbo rules (border-radius 0, no hover, no inline CSS, 16px font + logo exception, Broadcaster) from EXTRA.md + AGENTS.md. complexity: [high]
- [ ] T12.4 Draft condensed stack sections (Rails service objects, RSpec, Postgres, ActionCable, Tailwind, Voyage, Kamal/Docker, security) — principle blocks only, no vendor/ticket/MCP cruft (FPR-####, JIRA, Slack). complexity: [high]
- [ ] T12.5 Assemble the sections into the new `CLAUDE.md`, replacing the old content. complexity: [high]
- [ ] T12.6 Delete `AGENTS.md`. complexity: [low]
- [ ] T12.7 Delete `docs/EXTRA.md`. complexity: [low]
- [ ] T12.8 Grep for `AGENTS.md` / `EXTRA.md` references across the repo (CLAUDE.md, README, docs, comments) and update/remove them. complexity: [low]
- [ ] T12.9 Verify the new CLAUDE.md covers the main conventions + skills and reads authoritative + lean. complexity: [manual]
- [ ] T12.10 Commit: `Consolidate guidance into one lean CLAUDE.md; remove AGENTS.md and EXTRA.md`. complexity: [manual]

## P13 — Refresh docs/architecture.md + audit README for dead doc links

- [ ] T13.1 Audit `docs/architecture.md` against the current code (routes, component tree, event kinds, dispatch pipeline, namespace policy, release-date model) and note the stale parts. complexity: [low]
- [ ] T13.2 Update the **Component tree** section to the current event components (e.g. `EchoComponent`, `SystemComponent`, `EnhancedComponent`, `ErrorComponent`, `ConfirmationComponent`, `ThinkingComponent`) and palette controller. complexity: [low]
- [ ] T13.3 Update the **Event kinds** table to the current kinds (add `system`, `enhanced`; reconcile `assistant_text`/`confirmation_prompt` naming). complexity: [low]
- [ ] T13.4 Reconcile the **Routes** + **Dispatch pipeline** sections with the current controllers/flow (e.g. `/chat` login-navigate, follow-up replies). complexity: [low]
- [ ] T13.5 Verify the **Game release-date** section still matches `Game` (components, `recompute_release_date`, scopes, `ReleaseDateMapper`); update any drift. complexity: [low]
- [ ] T13.6 Fix the broken `docs/design.md` link in `README.md` (re-point or remove). complexity: [low]
- [ ] T13.7 Remove/redirect `README.md` references to `AGENTS.md` and `docs/EXTRA.md` now that P12 deleted them. complexity: [low]
- [ ] T13.8 Grep the repo for links to deleted MD files (`docs/design.md`, `AGENTS.md`, `EXTRA.md`) and fix dangling references. complexity: [low]
- [ ] T13.9 Commit: `Refresh docs/architecture.md and fix README dead doc links`. complexity: [manual]

## P14 — Confirmation & sync message timestamps (reported bugs)

> Bug #1: the confirmation prompt renders its `HH:MM ·` timestamp on its own line
> above the message instead of inline. Bug #2: the sync/import confirmation
> RESULT message ("Imported all channels: N new video(s)") has no timestamp.

- [x] T14.1 Render the confirmation prompt's `HH:MM ·` timestamp inline with the message in `confirmation_component` (mirror the standard `TimestampPrefixComponent` inline pattern). complexity: [low]
- [x] T14.2 Pass/render a timestamp on the sync/import confirmation RESULT message so it shows `HH:MM ·` like other messages. complexity: [low]
- [ ] T14.3 Add the inline first-line `HH:MM ·` timestamp to the remaining standalone message components that lack it — `error_component` and `confirmation_resolved_component` (sub-components spinner/meta/suggestion and the transient thinking status are excluded). complexity: [low]
- [ ] T14.4 Smoke: a confirmation prompt, its imported result, an error, and a resolved confirmation all show an inline first-line timestamp. complexity: [manual]
- [ ] T14.5 Commit: `Consistent first-line timestamp on confirmation, sync, and error messages`. complexity: [manual]

## P16 — Sidebar focus model: blur chatbox on open; m/Esc dismiss (reported bug)

> The first attempt (dismiss-on-keystroke) was wrong — it ate arrow-nav and broke
> sidebar inputs. Revised model: when a sidebar gains content it BLURS the chatbox,
> so keys drive the sidebar (or its own input, e.g. the IGDB game-search) and
> typing never dismisses. `m` dismisses any open sidebar AND focuses the chatbox;
> `Esc` dismisses without changing focus.

- [x] T16.1 Blur the chatbox when the sidebar gains content (`resume_controller#onContentChange` → `#blurChatbox`). complexity: [low]
- [x] T16.2 Remove the dismiss-on-keystroke guards from `resume_controller` (`#onKey`, `#onEscapeCapture`) and `notifications_nav_controller#onKey`. complexity: [low]
- [x] T16.3 `m` (command_palette) dismisses any open sidebar AND focuses the chatbox; `Esc` (resume) dismisses without focusing. complexity: [low]
- [x] T16.4 Update the JS specs (blur-on-open; m dismiss+focus; drop obsolete guard tests) — 326 vitest green. complexity: [low]
- [ ] T16.5 Smoke: open notifications, arrow/space navigate, type in chatbox/IGDB search without dismissing; `m` → chatbox; `Esc` → close. complexity: [manual]
- [ ] T16.6 Commit: `Sidebar blurs the chatbox on open; m/Esc dismiss`. complexity: [manual]

## P15 — `import videos`: detect & import new videos (reported bug)

> Reported: `import videos` does not detect/import genuinely new uploads (3 new
> videos across channels were missed), and the result reads "Imported all
> channels: ? new video(s)" — the count interpolates as a literal `?`.

- [x] T15.1 Investigate why the YouTube sync ("import newer videos") misses new uploads — trace the sync handler/job + its "newer-than"/pagination filter; capture the root cause. complexity: [high]
- [ ] T15.2 Fix detection so genuinely new videos across all channels are imported. complexity: [high]
- [x] T15.3 Fix the "Imported all channels: ? new video(s)" copy so the count interpolates correctly (no literal `?`) — switched the confirm message to an "Importing…" (queued) variant; the job's later message carries the real count. complexity: [low]
- [ ] T15.4 Add/update a spec covering new-video detection + the reported count. complexity: [low]
- [ ] T15.5 Smoke: with new uploads present, `import videos` imports them and reports the correct count. complexity: [manual]
- [ ] T15.6 Commit: `Fix import videos new-video detection and count`. complexity: [manual]

## P17 — Consume prior #hashtags when a new (non-reply) message is sent

> When the user sends a NEW (non-reply) chat message, every pre-existing live
> #hashtag becomes consumed (no longer repliable). The new command's own result
> messages keep their hashtags, even if they stream in later. Mechanism mirrors
> the follow-up dispatch: set `reply_consumed: true` + `broadcaster.replace_event`.

- [x] T17.1 In `ChatController#enqueue_turn` (after creating the new non-reply turn), mark every prior live repliable event (`turn_id < new_turn.id`, `reply_handle` present, not consumed) as `reply_consumed: true`. complexity: [high]
- [x] T17.2 `broadcaster.replace_event(event)` for each consumed event so its `#handle`/`shift+r` affordance drops live. complexity: [low]
- [x] T17.3 Ensure the new turn's own result events (emitted afterward) keep their handles — only PRIOR turns are consumed. complexity: [high]
- [x] T17.4 Spec: a new message consumes prior handles (router returns `:not_found`); the new command's handles stay live. complexity: [low]
- [ ] T17.5 Commit: `Consume prior hashtags when a new chat message is sent`. complexity: [manual]

## P18 — `shift+r` opens a picker of the last command's #hashtags

> Instead of prefilling the single last `#handle`, `shift+r` (caret at 0) opens a
> palette of all live hashtags from the user's LAST command's messages (a command
> can emit several repliable messages), so the user picks which to reply to.

- [x] T18.1 Collect the last turn's live hashtags (client: `#pito-scrollback .pito-turn:last-child [data-pito-handle]`). complexity: [high]
- [x] T18.2 On `shift+r` in `chat_form_controller.js`, when >1 hashtag exists, open a picker (reuse `command_palette` open/commit with `data-insert="#<handle> "`) instead of the single prefill. complexity: [high]
- [x] T18.3 Picking prefills `#<handle> ` in the chatbox (no auto-submit — the user types the action). complexity: [low]
- [x] T18.4 Keep the current single-handle prefill when only one hashtag exists. complexity: [low]
- [ ] T18.5 `node --check` + smoke: `shift+r` after `list videos` lists the result hashtags; picking one prefills it. complexity: [manual]
- [ ] T18.6 Commit: `shift+r opens a picker of the last command's hashtags`. complexity: [manual]

## P19 — `import videos`: one job + one message per channel (+ reauth surfacing)

> Root cause of "0 imported": ALL channels currently have `needs_reauth: true`, so
> `@all` resolves to 0 eligible channels. The import should fan out ONE job per
> channel, each emitting ONE result message — so reauth-needed channels surface
> ("@chan: needs reauth") instead of a single silent "0".

- [x] T19.1 Add a per-channel import job that imports one channel and emits one result message. complexity: [high]
- [x] T19.2 Change `confirm_import_videos` to enqueue one per-channel job per resolved channel — INCLUDING reauth-needed channels (so they get a message). (Adapted: kept one job that emits one message per channel — same outcome, simpler turn lifecycle.) complexity: [high]
- [x] T19.3 Per-channel message: "@chan: N new video(s)" on success; "@chan: needs reauth — reconnect" when `needs_reauth`. complexity: [low]
- [x] T19.4 Spec: N channels → N messages; a reauth-needed channel reports it. complexity: [low]
- [ ] T19.5 Commit: `import videos: one job + one message per channel`. complexity: [manual]

## P20 — Channel-item stats: compact numbers + S/V/v labels + legend

> `2260 subs · 3 videos · 454 views` should read `2.3K S · 3 V · 454 v` (compact
> numbers via the existing `Pito::Formatter::CompactCount`, abbreviated labels),
> with a single italic legend line (1-variant `Pito::Copy`): `S: Subscribers,
> V: Videos, v: Views`, shown once under the `list channels` grid.

- [ ] T20.1 Compact the subscriber/view numbers via `Pito::Formatter::CompactCount` in `channel/item_component`. complexity: [low]
- [ ] T20.2 Abbreviate the stat labels to `S` / `V` / `v` via 1-variant `Pito::Copy` keys (`%{count} S`, etc.), dropping the singular/plural split. complexity: [low]
- [ ] T20.3 Add a 1-variant italic legend copy (`S: Subscribers, V: Videos, v: Views`) and render it once under the grid in `channel/list_component`. complexity: [low]
- [ ] T20.4 Update channel-item + list specs for the new stats format + legend. complexity: [low]
- [ ] T20.5 Commit: `Channel stats: compact numbers, S/V/v labels, legend`. complexity: [manual]

## P21 — `list channels`: append an Enhanced message for channels needing reauth

> After the channel-list (Standard) message, `list channels` appends an Enhanced
> message listing the channels whose YouTube connection `needs_reauth` (with a
> reconnect hint). When none need reauth, NO Enhanced message is emitted.

- [x] T21.1 Add `Pito::MessageBuilder::Channel::ReauthNeeded` that renders an Enhanced message listing the reauth-needed channels (one `@handle — reconnect` line each) via `Pito::Copy`. complexity: [low]
- [x] T21.2 In `handlers/list.rb#list_channels`, select channels whose `youtube_connection&.needs_reauth?` and, when any, emit a second `{ kind: :enhanced, payload: ... }` after the list; emit nothing extra when none. complexity: [low]
- [x] T21.3 Add the reauth copy (header + per-channel line) under `pito.copy.channels.*`. complexity: [low]
- [x] T21.4 Spec: `list channels` with reauth-needed channels emits the enhanced message; with none, only the system message. complexity: [low]
- [ ] T21.5 Commit: `list channels: enhanced reauth-needed message`. complexity: [manual]

## P22 — Nightly job: notify per channel that needs reauth

> A daily job scans YouTube connections with `needs_reauth: true` and creates one
> notification per connection, reusing the existing idempotent
> `Pito::Notifications::Source::YoutubeReauthNeeded.report!` (dedup by connection,
> so re-runs don't spam).

- [x] T22.1 Add `YoutubeReauthCheckJob` that notifies per `needs_reauth` connection (uses the real `Notification.create!(message:)` schema with an unread-match for idempotency — the Phase-16 `YoutubeReauthNeeded` source references dropped columns and is dead code / P11 candidate). complexity: [low]
- [x] T22.2 Schedule it daily in `config/recurring.yml` (production + development). complexity: [low]
- [x] T22.3 Spec: a needs_reauth connection → one notification; re-running the job does not duplicate (idempotent). complexity: [low]
- [ ] T22.4 Commit: `Nightly job: notify on channels needing reauth`. complexity: [manual]

## P23 — Auto-import videos only for newly connected channels (not on re-auth)

> The `/connect` multi-stage flow runs `ChannelInfoJob`, which always enqueues
> `ImportVideosJob` (stage 2). On a re-auth of EXISTING channels (all duplicates),
> it should NOT auto-import — only when NEW channels were added.

- [x] T23.1 Add an `import_videos:` flag (default true) to `ChannelInfoJob#perform`; enqueue `ImportVideosJob` only when true, else complete the turn after the stats stage. complexity: [low]
- [x] T23.2 Add an `import_videos:` param to `persist_connect_result` and pass it to `ChannelInfoJob`. complexity: [low]
- [x] T23.3 In the OAuth callback `create`, pass `import_videos: discovery[:added].any?`. complexity: [low]
- [ ] T23.4 Spec: re-auth with all-duplicate channels → no `ImportVideosJob`; a new channel → `ImportVideosJob` enqueued. complexity: [low]
- [ ] T23.5 Commit: `Auto-import videos only for newly connected channels`. complexity: [manual]

## P24 — Clean up the connect message + 50-variant themed ASCII for connect/disconnect

> The duplicate/"already connected" connect message (`compose_callback_flash`)
> appends a witty filler line (`already_connected_extras`) AND an ASCII line
> (`ascii_art`). Drop the filler. Rebuild `ascii_art` as a **50-variant** theme-
> aware dictionary from the 50 cards chosen in `tmp/ascii-demo-2.html` — cards
> 01, 03, 05, 06, 11, 15, 16, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31, 32,
> 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 53,
> 54, 56, 58, 59, 60, 61, 64, 65, 67, 69 — each a themed `<pre>` block with the
> demo span classes remapped to pito message `text-*` classes (no `text-pink`/
> `text-blue` utility → map to existing accents). `/connect` (success) AND
> `/disconnect` (outcome) each render a RANDOM one. 50 variants satisfies the
> 1-or-50 copy guard.

- [ ] T24.1 Remove the `already_connected_extras` render from the duplicate branch of `compose_callback_flash` (message = main line + ascii only). complexity: [low]
- [ ] T24.2 Delete the now-unused `pito.copy.youtube.already_connected_extras` dictionary from the copy. complexity: [low]
- [ ] T24.3 Rebuild `pito.copy.youtube.ascii_art` as a 50-variant dictionary from the 50 chosen `tmp/ascii-demo-2.html` cards — each a themed `<pre>` block, demo span classes remapped to pito `text-*` message classes (`accent-pink`/`accent-blue` → existing accents). complexity: [high]
- [ ] T24.4 Render a random `pito.copy.youtube.ascii_art` on the `/disconnect` confirmed outcome (append after the i18n confirmed line; `/connect` success already renders it). complexity: [low]
- [ ] T24.5 Spec: `ascii_art` has exactly 50 variants (1-or-50 guard) and both `/connect` success + `/disconnect` outcome include an ascii block. complexity: [low]
- [ ] T24.6 Smoke: `/connect` (new + already-connected) and `/disconnect` each show a random art that re-colors on `/themes`; no filler line. complexity: [manual]
- [ ] T24.7 Commit: `50-variant themed ascii on connect/disconnect; drop the filler line`. complexity: [manual]

## P25 — Add the Synthwave dark theme

> Add the demo's neon "Synthwave" palette (deep-indigo bg, magenta/cyan accents)
> as a registered pito dark theme. Themes self-register via a file under
> `app/services/pito/themes/definitions/`; the CSS is generated from the registry
> by `rake pito:themes:export`. Palette (from `tmp/ascii-demo.html`): bg #1a0b2e,
> surface #241046, elevated #2d1259, fg #f5e0ff / dim #c4a7e7 / faded #7a5c9e,
> cyan #00f0ff, purple #b967ff, blue #5d8bff, green #39ff88, yellow #ffe066,
> orange #ff8c42, red #ff2e63 (pink #ff5cc8 has no pito token → dropped).

- [x] T25.1 Add `app/services/pito/themes/definitions/synthwave.rb` registering the `synthwave` dark theme with the palette above. complexity: [low]
- [x] T25.2 Regenerate `app/assets/tailwind/themes.css` via `bin/rails pito:themes:export`. complexity: [low]
- [x] T25.3 Bump `registry_completeness_spec` counts (18→19 total, 11→12 dark) and add `synthwave` to the dark-slugs assertion. complexity: [low]
- [x] T25.4 Run `contrast_spec`; add any new `synthwave:*` low-contrast pairs to `ACCEPTED_LOW_CONTRAST` with a one-line reason. complexity: [low] (none needed — synthwave clears the 3.0:1 floor everywhere)
- [x] T25.5 Run the themes specs + `bin/rubocop`; confirm green. complexity: [manual]
- [ ] T25.6 Commit: `Add the Synthwave dark theme`. complexity: [manual]

## P26 — `platform` verb: set a game's platform (normalized to a logo)

> Some IGDB games (e.g. Tekken 7) import with NO platform. Add a `platform` verb
> that sets a game's platform from free-text input, converging spelling variants
> to one canonical platform/logo. The DISPLAY layer already converges (the
> `Pito::Game::PlatformTokens` regex `playstation|ps\s?\d` matches PS5/ps5/
> PlayStation 5/PlayStation5/ps4 → the PlayStation logo); this phase adds the
> WRITE path + a normalizer so what we store is clean and logo-matchable.
>
> Contexts (via the existing `VerbDelegator`, same as `show`/`reindex`):
> - reply to `show game`: `#<handle> platform ps5` (game from context)
> - reply to `list games`: `#<handle> platform <game-id> ps5`
> - free chat: `platform <game-id> ps5`
>
> **Open decisions to confirm (proposed defaults below):**
> 1. **Add vs replace** — proposed: ADD the normalized platform to `game.platforms`
>    (append, de-duped), keeping any existing platforms. (Fits the "missing
>    platform" use case; the column is already an array.)
> 2. **Unknown platforms** — proposed: an input that maps to none of the three
>    logo families (PlayStation / Switch / Steam-PC) is still stored as text (no
>    logo, matching today's silent-drop display), rather than rejected. Xbox has
>    no logo asset yet → no icon until one is added (out of scope).

- [x] T26.1 Add a platform-input normalizer (free-text → canonical stored string) covering the PlayStation / Switch / Steam-PC families, reusing `Pito::Game::PlatformTokens` synonyms (e.g. `ps5`/`PlayStation 5`/`ps4` → `"PlayStation 5"`). complexity: [high]
- [x] T26.2 Add a `platform` chat verb handler: resolve the game (by `<id>` arg, or from the reply context), normalize the name, append it to `game.platforms` (de-duped), persist. complexity: [high]
- [x] T26.3 Register `platform` as an allowed reply verb on the `game_detail` and `game_list` follow-up targets so `#<handle> platform …` routes through the `VerbDelegator`. complexity: [high]
- [x] T26.4 Free-chat + list-reply parse a leading `<game-id>`; the show-game reply omits it (game from context). complexity: [low]
- [x] T26.5 Emit an HTML-friendly system message confirming the set platform, including its logo via `Pito::Game::PlatformTokens.icons_html`. complexity: [low]
- [x] T26.6 Add 1-or-50-compliant copy for the confirmation + unknown-platform + missing-id errors. complexity: [low]
- [x] T26.7 Specs: the normalizer converges `PS5`/`ps5`/`PlayStation 5`/`PlayStation5`/`ps4` → the PlayStation logo; the verb sets the platform in all three contexts; unknown name + missing id are handled. complexity: [low]
- [ ] T26.8 Commit: `Add the platform verb to set a game's platform`. complexity: [manual]

## P27 — Replace the test-seeds tasks with a `pito:tools:backup` task (sql + voyage + assets)

> The two `pito:test:seeds:*` tasks (`prepare` snapshot + `populate` restore) are
> replaced by a single real backup under a new `pito:tools` namespace. Restore is
> DROPPED — done manually. `pito:tools:backup` dumps the Postgres database, the
> Voyage embeddings, and all ActiveStorage assets into a
> `backup/<yyyy-mm-dd hh-mm-ss>/` folder, gzipped, using SYSTEM TOOLS (`pg_dump` /
> `tar` / `gzip`) shelled out from a Rake task that prints progress. The `backup/`
> folder is git-ignored. The task is specced (timestamped dir + gz artifacts
> produced; shell-outs stubbed so it runs in CI).
>
> **Confirmed:** task name is `pito:tools:backup`. Voyage embeddings are pgvector
> columns in Postgres, so the `pg_dump` already captures them — NO separate Voyage
> artifact is needed.

- [x] T27.1 Add `/backup/` to `.gitignore`. complexity: [low]
- [x] T27.2 Add a `pito:tools:backup` Rake task (new `pito:tools` namespace) that creates the `backup/<yyyy-mm-dd hh-mm-ss>/` destination folder (timestamp resolved at run time). complexity: [high]
- [x] T27.3 Dump Postgres via `pg_dump` piped through `gzip` → `<dir>/database.sql.gz` (read DB connection from Rails config; shell out to system tools). This dump also carries the Voyage pgvector embeddings. complexity: [high]
- [x] T27.4 Archive the ActiveStorage disk-service root via `tar -czf <dir>/active_storage.tar.gz` (resolve the storage path from config). complexity: [low]
- [x] T27.5 Print step-by-step progress in the task (each artifact, its size, and the final backup path). complexity: [low]
- [x] T27.6 Remove the `pito:test:seeds:prepare` + `pito:test:seeds:populate` tasks (restore is manual now). complexity: [low]
- [x] T27.7 Spec the backup: stub the `pg_dump`/`tar` shell-outs and assert a `backup/<timestamp>/` dir with `database.sql.gz` + `active_storage.tar.gz` is created and progress is printed; remove the obsolete `spec/lib/tasks/pito_test_seeds_rake_spec.rb`. complexity: [low]
- [ ] T27.8 Commit: `Replace test-seeds tasks with a pito:tools:backup task (sql + voyage + assets)`. complexity: [manual]

## P28 — `link`/`unlink` reply to list/detail cards shows the wrong usage message

> ROOT CAUSE (verified by reproduction): multi-target `link`/`unlink` from a list
> card is NOT broken — `#<handle> link <src-id> to <tgt-id1>,<tgt-id2>,…` works and
> creates the links (`link 20 to 21` on a video_list → link created). The reported
> failure used `with` instead of the connector `to`. The real bug: when the
> connector split fails, `follow_up_multi` falls back to `Handlers::Link#usage_hint`,
> which emits the FREE-CHAT syntax ("link game to video | link video to game")
> instead of the context-appropriate reply syntax — making it look broken.

- [x] T28.1 Reproduce + root-cause — DONE: multi-link with `to` works (link created); the misleading free-chat usage message on malformed input is the bug. complexity: [high]
- [x] T28.2 Make `follow_up_multi`'s malformed-input error show CONTEXT-appropriate usage: list → `link <src-id> to <tgt-id>[,id…]`; detail → `link to <id>[,id…]` (link) / `from` (unlink). complexity: [high]
- [x] T28.3 Accept `with` as a connector alias for `to` on link (free-chat + reply) — confirmed by user. Updated comments + help/usage copy (`Pito::Copy`). complexity: [low]
- [x] T28.4 Spec: a malformed list/detail link reply returns the context usage (not the free-chat one); a well-formed `link <id> to/with <ids>` links + idempotent. complexity: [low]
- [ ] T28.5 Smoke: `list videos` → `#<h> link <vid> to <gid1>,<gid2>` links; a malformed reply shows the list syntax. complexity: [manual]
- [ ] T28.6 Commit: `Context-aware usage for link/unlink replies`. complexity: [manual]

## P29 — `show game`: up to 6 similar games (match the channel row)

> The `show game` "overlap worth exploring" similar-games strip shows 5, while
> the "channels this game would feel at home in" row shows up to 6. Bump similar
> games to 6 (when available) so the two rows balance.

- [ ] T29.1 Change the similar-games limit from 5 → 6 (grep `similar_games(.*limit: 5` — in the game-enhanced builder/component recommendation call). complexity: [low]
- [ ] T29.2 Update the game-enhanced spec if it asserts a count/limit of 5. complexity: [low]
- [ ] T29.3 Commit: `Show up to 6 similar games (match the channel row)`. complexity: [manual]

## P30 — Halve the page left/right margins

> The chat page content sits inside left/right margins; cut those horizontal
> margins to the page edges by 50% so messages use more width.

- [ ] T30.1 Find the chat page/content container's horizontal margin/padding (the scrollback/layout wrapper in `application.css` or the layout) and halve the left + right value. complexity: [low]
- [ ] T30.2 Confirm the chatbox/composer still aligns with the widened content. complexity: [manual]
- [ ] T30.3 Commit: `Halve the page left/right margins`. complexity: [manual]

## P31 — BUG: prior list "replays" when a new command consumes it (DONE)

> Sending a new command (e.g. another `list videos`) re-rendered the PRIOR
> repliable list (P17 consume → `replace_event`), replaying its typewriter reveal
> before the new result streamed in. Fix: a consumed event (`reply_consumed`) now
> re-renders STATICALLY — no `pito--typewriter` controller — so consume re-renders
> never replay.

- [x] T31.1 Gate the `pito--typewriter` controller on `!reply_consumed` in `system_component.html.erb` (both wrappers) + `enhanced_component.html.erb`. complexity: [high]
- [x] T31.2 Spec: a consumed system event renders without the typewriter controller. complexity: [low]
- [ ] T31.3 Commit: `Render consumed events statically so they don't replay on re-render`. complexity: [manual]

## P32 — `show game` linked-videos: drop "Footage", use vids/vid, include the listing

> The `show game` linked-videos message reads "Footage: <title> × N videos." —
> (1) "Footage" collides with the user's recorded-footage concept; (2) copy should
> say "vids"/"vid" not "videos"/"video"; (3) the message should include the actual
> video LISTING (a lighter `list videos`), not just a count.
>
> **Open:** scope of the vids/vid terminology change — display copy only, or also
> command keywords like `list videos`? (Proposed: display copy only; keep command
> keywords.)

- [ ] T32.1 Replace "Footage" in `pito.copy.game.linked_videos_intro` (50 variants) with non-"Footage" wording. complexity: [low]
- [ ] T32.2 Switch user-facing "videos"/"video" → "vids"/"vid" in the relevant `Pito::Copy` (audit + confirm scope; keep command keywords). complexity: [high]
- [ ] T32.3 Ensure the show-game linked-videos message renders the actual listing (lighter `list videos` form), not just the count — verify P6's table emits, or add a slim listing. complexity: [high]
- [ ] T32.4 Specs + smoke. complexity: [low]
- [ ] T32.5 Commit: `show game linked-videos: drop Footage, vids/vid, include listing`. complexity: [manual]

## P33 — platform --help + show game/video detail kv-table refinements

> (a) `platform --help` is empty — add a man-style `Pito::Copy` help like other verbs.
> (b) `show game` kv-table: add `ID: #<id>` (internal id) before the Platform row.
> (c) `show video`: move the Category/Length/Status/Tags kv-table AFTER the
>     Description, with a hairline separator; keep the v/L/C stats on the left + add
>     a legend (v: Views, L: Likes, C: Comments) via `Pito::Copy`.
> (d) `show video` kv-table: add `ID: #<id>` (internal) + `YouTube ID: <yt>` rows.

- [ ] T33.1 Add `platform --help` man-style help copy (mirror other verbs' `--help`). complexity: [low]
- [ ] T33.2 `show game` detail kv-table: add an `ID: #<id>` row before the Platform row. complexity: [low]
- [ ] T33.3 `show video`: move the Category/Length/Status/Tags kv-table after the Description + add a hairline separator. complexity: [high]
- [ ] T33.4 `show video`: keep the v/L/C stats on the left + add a legend (v: Views, L: Likes, C: Comments) via `Pito::Copy`. complexity: [low]
- [ ] T33.5 `show video` kv-table: add `ID: #<id>` + `YouTube ID: <yt>` rows. complexity: [low]
- [ ] T33.6 Specs + smoke. complexity: [low]
- [ ] T33.7 Commit: `show game/video detail kv-table refinements + platform --help`. complexity: [manual]

## P34 — User timezone: `/config timezone=City` + render timestamps in local time

> The app stores UTC (application.rb + AR `default_timezone`). Add a user timezone
> so timestamps RENDER in local time AND schedule inputs are interpreted in local
> time (then converted to UTC at the YouTube boundary — already handled). Configure
> via `/config timezone=Madrid` — a MAJOR CITY mapped to an IANA zone via
> `ActiveSupport::TimeZone["Madrid"] → "Europe/Madrid"`. Default before set: UTC.

- [ ] T34.1 Add a `timezone` setting to `AppSetting` (key/value accessor + writer; default "UTC"). complexity: [low]
- [ ] T34.2 Add `/config timezone=<City>` to the config handler: resolve the city via `ActiveSupport::TimeZone[city]`, validate, persist; witty error on an unknown city. complexity: [high]
- [ ] T34.3 Set the request `Time.zone` from `AppSetting.timezone` (around_action on the base controller) so rendering + schedule parsing use local time; AR keeps storing UTC. complexity: [high]
- [ ] T34.4 Confirm the timestamp surfaces (`TimestampPrefixComponent`, `Pito::Formatter::CompactTimeAgo`, etc.) render in `Time.zone`. complexity: [low]
- [ ] T34.5 Add a `/config timezone` help/usage entry (man-style, like other config keys). complexity: [low]
- [ ] T34.6 Specs: city→zone resolution; a timestamp renders in the configured zone; unknown city errors. complexity: [low]
- [ ] T34.7 Commit: `User timezone via /config timezone=City; render timestamps locally`. complexity: [manual]

## P35 — Schedule natural-language time parser (in/tomorrow/at/for + 30-min guard)

> Extend `schedule <id> <when>` beyond `DD-MM-YYYY [HH:MM]` to natural language,
> interpreted in the user's local zone (P34) → UTC at the YouTube boundary. EVERY
> form validates ≥ 30 minutes from now. Forms: `in 30m` · `in 30 minutes` ·
> `in 1h [from now]` · `in 1 hour [from now]` · `in 3 days` · `tomorrow at noon` ·
> `tomorrow` (→ 9 AM) · `in 3 days` (→ 9 AM) · `at 2pm` / `at 23` (→ today) ·
> `for DD.MM.YYYY HH:MM` (accept `.` and `-`).
>
> **Decision:** a time-only form (`at 2pm` / `at 23`) is strictly the CURRENT day —
> if it has already passed, it's rejected by the past/30-min guard (no auto-roll to
> tomorrow).

- [ ] T35.1 Add a `Pito::Schedule::TimeParser` (or extend `Schedule#extract_when`) for relative durations: `in <n> <m|min|minute(s)|h|hour(s)|day(s)> [from now]`. complexity: [high]
- [ ] T35.2 Parse named day/time: `tomorrow`, `tomorrow at noon`, `at <HH>[am|pm]`, `at <HH>` — defaults (tomorrow / in-N-days → 9 AM; bare `at` → today). complexity: [high]
- [ ] T35.3 Parse absolute `for DD.MM.YYYY HH:MM` accepting `.` and `-` separators. complexity: [low]
- [ ] T35.4 Interpret every form in `Time.zone` (local) and enforce ≥ 30 min from now uniformly (reuse the past/30-min guards). complexity: [high]
- [ ] T35.5 Update the schedule help/usage copy (`Pito::Copy`) with the new forms. complexity: [low]
- [ ] T35.6 Specs: each of the 10 example forms → the correct local→UTC time; the 30-min guard on each. complexity: [low]
- [ ] T35.7 Commit: `schedule: natural-language time parsing (local→UTC, 30-min guard)`. complexity: [manual]

## Verification

- Per phase: `bundle exec rspec` green + `bin/rubocop` clean (and `node --check` for JS phases).
- UI phases need a manual smoke on **both** `localhost` and `app.pitomd.com`:
  `show video <id>`, `show game <id>`, `list videos`/`list games` with
  `add/remove` columns, the start screen + a 404 with the sidebar open, and `m`
  while logged out.
- P1: rendered `src` is relative and loads on app.pitomd.com.
- P9: run `ReleaseCountdownJob` against a game dated within 30 days → one
  countdown notification; a TBA game → none.
- P12: confirm nothing in the repo still depends on AGENTS.md / EXTRA.md.

## How to use this plan

Execute phase by phase on the current branch. One Sonnet sub-agent per atomic
task; escalate `[high]` tasks (P0 component surgery, P1 ActiveStorage paths, P2
`m` handler, P4 grid bounding, P6/P8 builders+components, P9 notification job,
P11 removals, P12 doc rewrite) to Opus. Verify each task before the next, and
stage this plan file with every phase commit. P11 pauses for user approval before
any deletion. Run the cleanup phases (P10–P12) last and do not introduce new plan
tags in comments you write along the way.
