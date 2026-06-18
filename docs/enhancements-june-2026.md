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
- [ ] T0.13 Delete `spec/javascript/expand_controller.test.js` and expand assertions in slash/disconnect/help specs. complexity: [low]
- [x] T0.14 Run affected `bundle exec rspec` + `bin/rubocop` + `node --check`; confirm green. complexity: [manual]
- [ ] T0.15 Commit: `Remove the expandable ctrl+| feature; render detail always-visible`. complexity: [manual]

## P1 — Serve attachment images from any host (proxy + relative URLs)

- [ ] T1.1 Add `config/initializers/active_storage_proxy.rb` setting `config.active_storage.resolve_model_to_route = :rails_storage_proxy`. complexity: [high]
- [ ] T1.2 Add a `Pito::ImagePath` service returning a host-less proxy path for a blob/variant via the AS proxy route helpers. complexity: [high]
- [ ] T1.3 Render the cover via `Pito::ImagePath` in `game/detail_component.html.erb`. complexity: [low]
- [ ] T1.4 Render the thumbnail via `Pito::ImagePath` in `video/detail_component.html.erb`. complexity: [low]
- [ ] T1.5 Render the avatar via `Pito::ImagePath` in `channel/item_component.html.erb`. complexity: [low]
- [ ] T1.6 Render the similar-game covers via `Pito::ImagePath` in `game/enhanced_component.html.erb`. complexity: [low]
- [ ] T1.7 Audit remaining attachment `image_tag`/`*_url` sites (start-screen channels, sidebar/resume previews) and switch them to `Pito::ImagePath`. complexity: [low]
- [ ] T1.8 Add a `Pito::ImagePath` spec asserting a relative `/rails/active_storage/...` path (no host). complexity: [low]
- [ ] T1.9 Verify a rendered message has relative image `src` (no `http://localhost`); reload app.pitomd.com and confirm images load. complexity: [manual]
- [ ] T1.10 Commit: `Serve attachment images via relative proxy paths (host-agnostic)`. complexity: [manual]

## P2 — Sidebar dismiss + `m` (focus chat / dismiss sidebar), unauthenticated

- [x] T2.1 Add a public `dismiss()` action to `resume_controller.js` that calls the existing private `#clear()`. complexity: [low]
- [x] T2.2 Dispatch a `pito:resume:dismiss` window event on connect from `Pito::StartScreen::Component` (covers start screen + 404). complexity: [low]
- [x] T2.3 Listen for `pito:resume:dismiss` in `resume_controller.js` and call `dismiss()`. complexity: [low]
- [x] T2.4 Rework the `"m"` handler in `command_palette_controller.js`: if the sidebar is active → `dismiss()` it; else focus the chatbox — and remove the `isAuthenticated()` gate (keep the in-input guard). complexity: [high]
- [x] T2.5 Update any command-palette controller spec for the new `m` behaviour. complexity: [low]
- [ ] T2.6 Run `node --check`; smoke: `m` focuses chat (logged out too), `m` dismisses an open sidebar, and start/404 dismiss the sidebar without reopening on reload. complexity: [manual]
- [ ] T2.7 Commit: `m focuses chat or dismisses the sidebar; dismiss sidebar on start/404`. complexity: [manual]

## P3 — Right-align the `#` id heading in list videos/games

- [x] T3.1 Give the `#` heading the right-align class in `video/list.rb` (`{ "text" => "#", "class" => "text-right" }`, matching `game/list.rb`). complexity: [low]
- [x] T3.2 Ensure the heading cell stretches so `text-right` takes effect in the `max-content` track (CSS in `application.css`); confirm both lists right-align `#`. complexity: [low]
- [x] T3.3 Update the games/videos list specs to assert the `#` heading carries the right-align class. complexity: [low]
- [ ] T3.4 Commit: `Right-align the # id heading in list videos and games`. complexity: [manual]

## P4 — Re-evaluate column widths on add/remove so the grid never breaks

- [ ] T4.1 Constrain `.pito-data-grid` to the available width in `application.css` (`max-width: 100%`, cells `min-width: 0`) so it never overflows the segment. complexity: [high]
- [ ] T4.2 Add `data-cols`-tiered per-cell `max-width` overrides (tighten title/genre/developer/publisher/game/channel caps as `data-cols` grows). complexity: [high]
- [ ] T4.3 Smoke `list videos` → `add comments` (and all columns) on a wide viewport: bounded with truncation, no break. complexity: [manual]
- [ ] T4.4 Smoke `list games` → `add genre, developer, publisher` (and all columns): bounded with truncation. complexity: [manual]
- [ ] T4.5 Commit: `Keep the list data-grid within bounds when columns change`. complexity: [manual]

## P5 — Similar-game score bars under `show game`

- [ ] T5.1 Render `Pito::ScoreBarComponent.new(score: result.score, show_label: false)` under each similar-game card in `game/enhanced_component.html.erb`. complexity: [low]
- [ ] T5.2 Widen the `.pito-game-enhanced-message__similar-games-strip` row gap in `application.css` so the score bubble clears the next row. complexity: [low]
- [ ] T5.3 Update the game enhanced component spec to assert a score bar per similar-game card. complexity: [low]
- [ ] T5.4 Commit: `Score bar under each similar-game card in show game`. complexity: [manual]

## P6 — `show game`: repliable linked-videos list table

- [ ] T6.1 Add `Pito::MessageBuilder::Game::LinkedVideos` calling `Video::List.call(game.linked_videos, conversation:, columns: %i[channel duration views comments likes])`. complexity: [high]
- [ ] T6.2 Add a dim header/intro copy line for the linked-videos section via `Pito::Copy`. complexity: [low]
- [ ] T6.3 Emit the linked-videos payload as an `:enhanced` event right after the detail in the `show game` branch of `handlers/show.rb`. complexity: [low]
- [ ] T6.4 Omit the message when `game.linked_videos` is empty. complexity: [low]
- [ ] T6.5 Add a spec: the linked-videos message is present and repliable (target `video_list`). complexity: [low]
- [ ] T6.6 Smoke `show game <id>`: repliable linked-videos table; `#<handle> show <video-id>` opens the video; `add/remove` columns work. complexity: [manual]
- [ ] T6.7 Commit: `show game: repliable linked-videos list table`. complexity: [manual]

## P7 — `show game`: Stats & Analytics placeholder message

- [ ] T7.1 Add `Pito::MessageBuilder::Game::StatsPlaceholder` mirroring `Video::Enhanced`. complexity: [low]
- [ ] T7.2 Add the `pito.copy.game.stats_placeholder` copy line. complexity: [low]
- [ ] T7.3 Emit it as an `:enhanced` event between the linked-videos and recommendations messages in `handlers/show.rb`. complexity: [low]
- [ ] T7.4 Smoke the `show game` order: detail → linked-videos → stats&analytics → recommendations. complexity: [manual]
- [ ] T7.5 Commit: `show game: Stats & Analytics placeholder message`. complexity: [manual]

## P8 — `show video`: slim repliable linked-game card

- [ ] T8.1 Add `Pito::Video::LinkedGameCardComponent` (slim): cover left + kv-table right (title, genres, perspective, theme, publisher, developer, release date, total footage), no TTB bar. complexity: [high]
- [ ] T8.2 Render total footage as a TTB-pillar value via `Pito::Formatter::TtbHours.call(game.footages.sum(:duration_seconds))`. complexity: [low]
- [ ] T8.3 Add the card CSS (cover left, kv-table right) reusing `Pito::Table::KeyValueRowComponent` + the `grid grid-cols-[max-content_1fr]` pattern. complexity: [low]
- [ ] T8.4 Add `Pito::MessageBuilder::Video::LinkedGame` rendering the card for `video.linked_games.first`, stamping `game_id` + `make_followupable!(target: "game_detail")`. complexity: [high]
- [ ] T8.5 Emit the card as an `:enhanced` event before the `Video::Enhanced` placeholder in the `show video` branch of `handlers/show.rb`. complexity: [low]
- [ ] T8.6 Omit the card when the video has no linked game. complexity: [low]
- [ ] T8.7 Add specs: the card renders the fields, and the flow emits it repliable via `game_detail`. complexity: [low]
- [ ] T8.8 Smoke `show video <id>`: slim linked-game card before the stats placeholder; `#<handle> show`/`reindex` act on the game. complexity: [manual]
- [ ] T8.9 Commit: `show video: slim repliable linked-game card`. complexity: [manual]

## P9 — Daily release-countdown notifications

- [ ] T9.1 Remove the buggy date-less `releasing_30d` collection + reporting from `app/jobs/game_igdb_nightly_refresh.rb` (keep the changed/failures summary). complexity: [high]
- [ ] T9.2 Add a `Pito::Notifications::Source::ReleaseCountdown` source that, for a game + days-remaining, builds a notification via a 50-variant `Pito::Copy` dictionary (embeds `%{n}` days + title). complexity: [high]
- [ ] T9.3 Add the 50-variant countdown copy dictionary under `config/locales/pito/copy/` (witty `n`-days-until-release lines). complexity: [low]
- [ ] T9.4 Add a daily `ReleaseCountdownJob` that selects games with a present `release_date` in `Date.current..(Date.current + 30.days)` and emits one countdown notification per game. complexity: [high]
- [ ] T9.5 Guard against a duplicate same-day reminder per game (skip if one already exists for that game today). complexity: [low]
- [ ] T9.6 Schedule `ReleaseCountdownJob` daily in `config/recurring.yml` (both environments). complexity: [low]
- [ ] T9.7 Add a job spec: a game dated within 30 days gets a countdown notification; a date-less (TBA) game gets none; no duplicate same day. complexity: [low]
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

- [ ] T14.1 Render the confirmation prompt's `HH:MM ·` timestamp inline with the message in `confirmation_component` (mirror the standard `TimestampPrefixComponent` inline pattern). complexity: [low]
- [ ] T14.2 Pass/render a timestamp on the sync/import confirmation RESULT message so it shows `HH:MM ·` like other messages. complexity: [low]
- [ ] T14.3 Smoke: a confirmation prompt and its imported result both show an inline timestamp. complexity: [manual]
- [ ] T14.4 Commit: `Inline timestamp on confirmation prompt + timestamp on sync result`. complexity: [manual]

## P15 — `import videos`: detect & import new videos (reported bug)

> Reported: `import videos` does not detect/import genuinely new uploads (3 new
> videos across channels were missed), and the result reads "Imported all
> channels: ? new video(s)" — the count interpolates as a literal `?`.

- [x] T15.1 Investigate why the YouTube sync ("import newer videos") misses new uploads — trace the sync handler/job + its "newer-than"/pagination filter; capture the root cause. complexity: [high]
- [ ] T15.2 Fix detection so genuinely new videos across all channels are imported. complexity: [high]
- [ ] T15.3 Fix the "Imported all channels: ? new video(s)" copy so the count interpolates correctly (no literal `?`). complexity: [low]
- [ ] T15.4 Add/update a spec covering new-video detection + the reported count. complexity: [low]
- [ ] T15.5 Smoke: with new uploads present, `import videos` imports them and reports the correct count. complexity: [manual]
- [ ] T15.6 Commit: `Fix import videos new-video detection and count`. complexity: [manual]

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
