# Pito enhancements — June 2026 · remaining work

> Completed phases are pruned from this file.
>
> **Committed** (5 GPG-signed commits on `main`): P0–P9, P16–P23, P25–P28, P31.
>
> **Done but NOT yet committed** (one large uncommitted tree, awaiting your GPG):
> P14, P15, P33, P36, P37, and **P38–P44** — the video-sync overhaul (search-based
> `VideoLibrary#sync`, one `VideoSyncJob`, `sync`/`import` verbs unified with `sync`
> canonical), the footage rework (`footage_hours` decimal + `footage update`/`footage
> snippet`, probe/rake flow dropped), the schedule + `--help` bug fixes, the
> scheduled sync cadence, and the show game/video kv-table refinements. Suite green
> at 4930 examples.
>
> What's LEFT is below.

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
- P24 — Clean up the connect message + 50-variant themed ASCII for connect/disconnect
- P32 — `show game` linked-videos: drop "Footage", use vids/vid, include the listing

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

- [ ] T11.1 Sweep the codebase (rb/js/css/erb/yml + specs) for obsolete code from prior attempts — remnants of removed surfaces (Settings::*, MCP, Redis, Sidekiq, Meilisearch, Doorkeeper, old layouts/hooks), the dead Phase-16 notification subsystem (`Pito::Notifications::Source::YoutubeReauthNeeded` + `PayloadBuilder` referencing dropped columns), the orphaned `confirmation_resolved_component` (deferred from P14 — only its own spec references it), the now-unreachable `confirm_import_videos` executor branch + `import_videos` copy if dead, unreferenced files, orphaned specs — and write a findings report to `tmp/audits/dead-code.md` (file:line, why dead, removal risk). complexity: [high]
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
>
> **BLOCKED on you:** the final 50-card ASCII pick / confirmation before T24.3.

- [x] T24.1 Remove the `already_connected_extras` render from the duplicate branch of `compose_callback_flash` (message = main line + ascii only). complexity: [low]
- [x] T24.2 Delete the now-unused `pito.copy.youtube.already_connected_extras` dictionary from the copy. complexity: [low]
- [x] T24.3 Rebuild `pito.copy.youtube.ascii_art` as a 50-variant dictionary from the 50 chosen `tmp/ascii-demo-2.html` cards — each a themed `<pre>` block, demo span classes remapped to pito `text-*` message classes (`accent-pink` → `text-purple`, `accent-blue` → `text-pito` (pito blue `#5170ff`)). All colors already emitted by the chat UI, so no safelist needed. complexity: [high]
- [x] T24.4 Render a random `pito.copy.youtube.ascii_art` on the `/disconnect` confirmed outcome (append after the i18n confirmed line; `/connect` success already renders it). complexity: [low]
- [x] T24.5 Spec: `ascii_art` has exactly 50 variants (1-or-50 guard) and both `/connect` success + `/disconnect` outcome include an ascii block. complexity: [low]
- [ ] T24.6 Smoke: `/connect` (new + already-connected) and `/disconnect` each show a random art that re-colors on `/themes`; no filler line. complexity: [manual]
- [ ] T24.7 Commit: `50-variant themed ascii on connect/disconnect; drop the filler line`. complexity: [manual]

## P32 — `show game` linked-videos: drop "Footage", use vids/vid, include the listing

> The `show game` linked-videos message reads "Footage: <title> × N videos." —
> (1) "Footage" collides with the user's recorded-footage concept; (2) copy should
> say "vids"/"vid" not "videos"/"video"; (3) the message should include the actual
> video LISTING (a lighter `list videos`), not just a count.
>
> **BLOCKED on you:** scope of the vids/vid terminology change — display copy only,
> or also command keywords like `list videos`? (Proposed: display copy only; keep
> command keywords.)

- [ ] T32.1 Replace "Footage" in `pito.copy.game.linked_videos_intro` (50 variants) with non-"Footage" wording. complexity: [low]
- [ ] T32.2 Switch user-facing "videos"/"video" → "vids"/"vid" in the relevant `Pito::Copy` (audit + confirm scope; keep command keywords). complexity: [high]
- [ ] T32.3 Ensure the show-game linked-videos message renders the actual listing (lighter `list videos` form), not just the count — verify P6's table emits, or add a slim listing. complexity: [high]
- [ ] T32.4 Specs + smoke. complexity: [low]
- [ ] T32.5 Commit: `show game linked-videos: drop Footage, vids/vid, include listing`. complexity: [manual]

## How to use this plan

Execute phase by phase on `main`. One Sonnet sub-agent per atomic task; escalate
`[high]` tasks to Opus. Verify each task before the next (`bundle exec rspec`
green + `bin/rubocop` clean + `node --check` for JS). P11 pauses for user approval
before any deletion. UI phases need a manual smoke on both `localhost` and
`app.pitomd.com`.
