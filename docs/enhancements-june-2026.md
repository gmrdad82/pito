# Pito enhancements — June 2026 · remaining work

> Completed phases have been pruned from this file. Done + committed (5 GPG-signed
> commits on `main`): P0–P9, P16–P23, P25–P28, P31 — expandable removal, host-less
> images, list-table polish, `show game`/`show video` enrichments, per-channel
> imports + reauth surfacing, release-countdown notifications, consume-prior-
> hashtags, `shift+r` picker, `platform` verb, `link to/with`, Synthwave theme,
> `pito:tools:backup`, and the replay fix. What's LEFT is below.

## Complexity hints

| Hint | Meaning |
| --- | --- |
| `[manual]` | Operator by hand: smoke tests, grep audits, user approval, commits. |
| `[low]` | Mechanical CSS / markup / single-file edits, or plumbing that follows an existing pattern. |
| `[high]` | Layout restructure, ActiveStorage plumbing, component-tree surgery, cross-cutting removals, doc rewrites. |

## Phase index (remaining)

- P10 — Strip plan/phase/task references from source comments
- P11 — Dead-code audit (report-first)
- P12 — Consolidate docs into one lean CLAUDE.md (delete AGENTS.md + EXTRA.md)
- P13 — Refresh docs/architecture.md + audit README for dead doc links
- P14 — Confirmation & sync message timestamps (remaining: error/resolved)
- P15 — `import videos`: detect & import new videos (root-cause fix)
- P24 — Clean up the connect message + 50-variant themed ASCII for connect/disconnect
- P29 — `show game`: up to 6 similar games (match the channel row)
- P30 — Halve the page left/right margins
- P32 — `show game` linked-videos: drop "Footage", use vids/vid, include the listing
- P33 — platform --help + show game/video detail kv-table refinements
- P34 — User timezone: `/config timezone=City` + render timestamps in local time
- P35 — Schedule natural-language time parser (in/tomorrow/at/for + 30-min guard)

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

- [ ] T11.1 Sweep the codebase (rb/js/css/erb/yml + specs) for obsolete code from prior attempts — remnants of removed surfaces (Settings::*, MCP, Redis, Sidekiq, Meilisearch, Doorkeeper, old layouts/hooks), the dead Phase-16 notification subsystem (`Pito::Notifications::Source::YoutubeReauthNeeded` + `PayloadBuilder` referencing dropped columns), unreferenced files, orphaned specs — and write a findings report to `tmp/audits/dead-code.md` (file:line, why dead, removal risk). complexity: [high]
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

## P14 — Confirmation & sync message timestamps (remaining)

> Bug #1 (confirmation inline timestamp) + Bug #2 (sync/import result timestamp)
> are DONE. Remaining: extend the inline first-line `HH:MM ·` timestamp to the
> other standalone message components that still lack it.

- [ ] T14.3 Add the inline first-line `HH:MM ·` timestamp to the remaining standalone message components that lack it — `error_component` and `confirmation_resolved_component` (sub-components spinner/meta/suggestion and the transient thinking status are excluded). complexity: [low]
- [ ] T14.4 Smoke: a confirmation prompt, its imported result, an error, and a resolved confirmation all show an inline first-line timestamp. complexity: [manual]
- [ ] T14.5 Commit: `Consistent first-line timestamp on confirmation, sync, and error messages`. complexity: [manual]

## P15 — `import videos`: detect & import new videos (root-cause fix)

> The count bug (`? new video(s)`) is fixed and per-channel fan-out (P19) shipped.
> Remaining: the ROOT detection fix — genuinely new uploads across channels are
> still missed by the "newer-only" sync. (Investigation done in T15.1.)

- [ ] T15.2 Fix detection so genuinely new videos across all channels are imported. complexity: [high]
- [ ] T15.4 Add/update a spec covering new-video detection + the reported count. complexity: [low]
- [ ] T15.5 Smoke: with new uploads present, `import videos` imports them and reports the correct count. complexity: [manual]
- [ ] T15.6 Commit: `Fix import videos new-video detection and count`. complexity: [manual]

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

## P29 — `show game`: up to 6 similar games (match the channel row)

> The `show game` "overlap worth exploring" similar-games strip shows 5, while
> the "channels this game would feel at home in" row shows up to 6. Bump similar
> games to 6 (when available) so the two rows balance.

- [x] T29.1 Change the similar-games limit from 5 → 6 (grep `similar_games(.*limit: 5` — in the game-enhanced builder/component recommendation call). complexity: [low]
- [x] T29.2 Update the game-enhanced spec if it asserts a count/limit of 5. complexity: [low]
- [ ] T29.3 Commit: `Show up to 6 similar games (match the channel row)`. complexity: [manual]

## P30 — Halve the page left/right margins

> The chat page content sits inside left/right margins; cut those horizontal
> margins to the page edges by 50% so messages use more width.

- [x] T30.1 Find the chat page/content container's horizontal margin/padding (the scrollback/layout wrapper in `application.css` or the layout) and halve the left + right value (`#pito-scrollback` padding 50px → 25px). complexity: [low]
- [ ] T30.2 Confirm the chatbox/composer still aligns with the widened content. complexity: [manual]
- [ ] T30.3 Commit: `Halve the page left/right margins`. complexity: [manual]

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

- [x] T34.1 Add a `timezone` setting to `AppSetting` (key/value accessor + writer; default "UTC"). complexity: [low]
- [x] T34.2 Add `/config timezone=<City>` to the config handler: resolve the city via `ActiveSupport::TimeZone[city]`, validate, persist; witty error on an unknown city. complexity: [high]
- [x] T34.3 Set the request `Time.zone` from `AppSetting.timezone` (`set_user_time_zone` before_action) so rendering + schedule parsing use local time; AR keeps storing UTC. complexity: [high]
- [x] T34.4 Timestamp surfaces render in `Time.zone` (`TimestampPrefixComponent` → `in_time_zone`; `CompactTimeAgo` is delta-math, zone-independent). complexity: [low]
- [x] T34.5 Add a `/config timezone` help/usage entry (man-style, like other config keys). complexity: [low]
- [x] T34.6 Specs: city→zone resolution; a timestamp renders in the configured zone; unknown city errors. complexity: [low]
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

- [x] T35.1 Add a `Pito::Schedule::TimeParser` (or extend `Schedule#extract_when`) for relative durations: `in <n> <m|min|minute(s)|h|hour(s)|day(s)> [from now]`. complexity: [high]
- [x] T35.2 Parse named day/time: `tomorrow`, `tomorrow at noon`, `at <HH>[am|pm]`, `at <HH>` — defaults (tomorrow / in-N-days → 9 AM; bare `at` → today). complexity: [high]
- [x] T35.3 Parse absolute `for DD.MM.YYYY HH:MM` accepting `.` and `-` separators. complexity: [low]
- [x] T35.4 Interpret every form in `Time.zone` (local) and enforce ≥ 30 min from now uniformly (reuse the past/30-min guards). complexity: [high]
- [x] T35.5 Update the schedule help/usage copy (`Pito::Copy`) with the new forms. complexity: [low]
- [x] T35.6 Specs: each of the 10 example forms → the correct local→UTC time; the 30-min guard on each. complexity: [low]
- [ ] T35.7 Commit: `schedule: natural-language time parsing (local→UTC, 30-min guard)`. complexity: [manual]

## How to use this plan

Execute phase by phase on `main`. One Sonnet sub-agent per atomic task; escalate
`[high]` tasks to Opus. Verify each task before the next (`bundle exec rspec`
green + `bin/rubocop` clean + `node --check` for JS). P11 pauses for user approval
before any deletion. UI phases need a manual smoke on both `localhost` and
`app.pitomd.com`.
