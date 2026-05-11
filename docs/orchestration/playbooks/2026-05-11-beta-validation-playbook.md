# Beta Validation Playbook — 2026-05-11

> The "everything" doc. Walk top-to-bottom before bumping the version. Each
> section maps to a surface or contract the user is expected to dogfood. Mobile
> readable — keep terse, use checkboxes, group walks by section.
>
> **Implementation status when this playbook was written:** ~98%
> autonomous-complete. Source snapshot:
> `docs/notes/2026-05-11-02-00-00-beta-progress-snapshot.md`. ~7000+ RSpec
> examples, ~710 cargo tests. CI green at HEAD.
>
> **Boot before walking:** `bin/dev` (Puma + Sidekiq + Tailwind watcher +
> Docker). MCP: `bin/mcp` or `bin/mcp-web`. CLI:
> `cargo run --bin pito -- <subcommand>` from `extras/cli/`.
>
> **Owner account:** `gmrdad82@gmail.com` (seeded — see `docs/setup.md`).
> Password lives in `rails credentials:edit` under `:owner`.

---

## 1. Identity + auth

**Contract:** email + password login. Owner seeded. Phase 25 01a/01b layered on
top: every authenticate POST writes a `LoginAttempt` row through
`Auth::AttemptLogger` with fingerprint + IP prefix + geo + UA. New-location
logins are challenged via `/login/challenge` → `/login/pending` with a 10-minute
expiry swept every minute by `pending_session_approval_sweeper`. Generic
`Login failed.` copy across every failure branch (LD-14, no leakage).

- [ ] Log in from your primary browser with the owner credentials. Land on `/`.
- [ ] Open `/settings/security`. See `2FA: off`, trusted locations: 1, pending:
      0, 1 success row in recent activity.
- [ ] Log out. Open a fresh incognito / different browser. Submit wrong
      password. See generic `login failed.` flash (not `invalid email`).
- [ ] Submit correct password from the same fresh browser. Expect redirect to
      `/login/challenge` (NOT to `/`). Two bracketed-link choices visible:
      `[enter 2FA code]` and `[ask for approval]`.
- [ ] Click `[ask for approval]`. Redirect to `/login/pending` with a `10:00`
      countdown + attempt-detail card (browser / OS / IP / fingerprint short).
- [ ] From the trusted browser, refresh `/settings/security`. Expect
      `pending: 1` and a `LoginAttempt` row with `result: pending_approval`.
- [ ] In a Rails console, run `Auth::PendingSessionExpirer.call`. Refresh
      `/login/pending` in the pending browser. Expect redirect to `/login` with
      generic `login failed.` and a new `LoginAttempt` row with
      `reason: pending_expired`.
- [ ] Visit `/sidekiq/cron`. Confirm `pending_session_approval_sweeper` is
      scheduled at `* * * * *`.
- [ ] Repeat the pending flow, then click `[cancel & log out]` from
      `/login/pending`. Confirm redirect to `/login` + the Session row flipped
      to `state: revoked`.
- [ ] Console teardown: `Session.pending.destroy_all`, `LoginAttempt.delete_all`
      (full purge UI ships in 01f, not yet implemented — see §17).

---

## 2. Google + YouTube integration

**Contract:** OAuth flow scopes (`youtube.readonly`, `yt-analytics.readonly`,
`youtube.force-ssl`). Phase 24 moved Google management out of
`/settings/youtube` onto `/channels`. `/settings/youtube` 301s to `/channels`.
Channels banner on `/channels` shows connected accounts +
`[+ add another Google account]` (forces `prompt=select_account`). OAuth
callback auto-discovers channels and duplicate-skips with a flash.

- [ ] Visit `/settings/youtube`. Expect 301 to `/channels`.
- [ ] On `/channels`, see the Google banner above the table listing your
      connected account(s) and `[+ add another Google account]`.
- [ ] Click `[+ add another Google account]`. Google forces a second account
      picker (`prompt=select_account`). Pick a second account.
- [ ] After callback, see both accounts in the banner. New channels (if any) are
      auto-discovered into the table; duplicates produce a skip flash.
- [ ] Click `[revoke]` next to a connected account. Action-screen confirms.
      Confirm. The `DeleteChannelDataJob` cleans up; banner now shows the
      remaining account.

---

## 3. Channels surface

**Contract:** `/channels` is an 8-column table (checkbox / avatar /
title+@handle / @handle URL (no truncation) / subscribers / videos / star / last
sync). Phase 7.5 Step 11 a–i ships the full per-channel revamp: show, edit
(14-day gate + reminder), diff (daily cron + bidirectional resolve), history,
preview (desktop / mobile / TV), watermark preview, banner upload.

- [ ] `/channels` — confirm 8-column layout, no URL truncation, star column
      sortable.
- [ ] Select 2 rows. The bulk bar shows `[revoke N]` (renamed from `[delete N]`
      per Phase 24). Click. Action-screen confirms. Cancel for now.
- [ ] Click into a channel: `/channels/:slug` shows banner / avatar / title /
      handle / @youtube + @studio links / description / links / analytics
      summary / videos pane (starred first, ~30 cap).
- [ ] Click `[edit]`. Every editable field present (title, handle, description,
      country, language, keywords, links, banner, watermark). 14-day gate UX
      visible on fields YouTube rate-limits. Submit a change.
- [ ] Visit `/calendar/schedule`. Confirm Step 11h reminder auto-created
      (silent + toast).
- [ ] `/channels/:slug/diff` — daily diff cron (`channel_diff_check`) renders
      side-by-side. Per-field `[accept pito]` / `[accept youtube]`. Apply.
- [ ] `/channels/:slug/history` — change log shows the diff resolution.
- [ ] `/channels/:slug/preview` — modal cycles desktop / mobile / TV layouts.
- [ ] `/channels/:slug/preview` watermark tab — faux player + overlay.
- [ ] On `/channels/:slug/edit`, drag-drop a banner image. 4-condition
      validation (dimension / aspect / size / format) gates save.
- [ ] Back on `/channels`, hit the `[sync]` button on a row. Confirm it routes
      to the diff path (never silently overwrites).

---

## 4. Videos surface

**Contract:** `/videos` lists with optional `?channel=<slug>` filter (Phase 21).
Per-video show has stats moved to its own pane row below detail. JSON endpoints
(Phase 21): index, show, search, resync — full CLI / MCP parity. Phase 22 added
the `[import]` modal for pulling existing YouTube videos in (ImportJob +
per-channel modal + RejectedVideoImport tombstones). Phase 23 added the video
sync diff dialog (same shape as channel diff).

- [ ] `/videos` lists. Apply `?channel=<slug>`. Confirm filter persists in
      breadcrumb.
- [ ] Click into a video. Stats render in their own `.pane-row` under the
      detail.
- [ ] `/videos.json` — confirm payload shape. Same for `/videos/:slug.json`.
- [ ] `/videos/search?q=…` — JSON.
- [ ] On `/channels/:slug`, click `[import]`. Modal walks: list YouTube videos
      not yet in Pito → tick the ones you want → submit. ImportJob enqueues.
- [ ] Reject one video in the modal. Confirm a `RejectedVideoImport` tombstone
      is created and the video does NOT re-appear on the next import refresh.
- [ ] Trigger a video sync from `/videos/:slug` (or `[sync]` row button). Diff
      dialog renders. Per-field `[accept pito]` / `[accept youtube]`. Apply.

---

## 5. Projects surface

**Contract:** Projects list with always-on checkboxes (bulk-toggle dropped).
Project show: notes pane + videos pane (timelines pane retired).

- [ ] `/projects` — checkboxes always visible (no `[bulk]` toggle).
- [ ] Click into a project. Confirm notes pane + videos pane render side by
      side. No timelines pane.
- [ ] Select 2 projects on `/projects`. `[delete N]` action-screen confirms.
      Cancel.

---

## 6. Games surface (Phase 27)

**Contract:** Two shelves at top (Genres + Custom collections, alphabetical,
horizontal scroll, `:shelf` cover variant at 65% — see §17). Filter row
(multi-select chips), 3 display modes (Grid default / List alpha-grouped /
Shelves-by-letter), persisted via `User#preferred_games_display_mode`.
Per-platform ownership via `game_platform_ownerships` join (singular
`platform_owned_id` dropped). Shelf cover at 65% of grid (~152 × 203 px).

> 01a ownership data model + 01c shelves + 01d display modes + 01e shelf cover
> are landed. 01b filter row + 01f show/edit ownership UI + 01g MCP/CLI parity
> are NOT yet implemented (see §17).

- [ ] `/games` — two shelves render at top (Genres, Collections), alphabetical,
      horizontal scroll, covers at 65% size.
- [ ] Top-right of `/games`: three bracketed-link buttons
      `[grid] [list] [shelves]`. Click `[list]`. Refresh — preference persists.
- [ ] List mode: alpha-grouped, sticky letter headings, columns (cover thumb /
      title / platforms owned / genres / status).
- [ ] Click `[shelves]` — one shelf per letter, empty letters hidden.
- [ ] Click `[grid]` — back to grid default.
- [ ] (Filter row check — 01b not shipped — skip and note in §17.)

---

## 7. Calendar surface

**Contract:** `/calendar/month/YYYY/MM` grid (h/l = ±day, j/k = ±week).
`/calendar/schedule` list view. Filter chips + `[+]` default-create entry. Phase
7.5 Step 11h reminder integration creates calendar entries silently from the
channel edit form's 14-day gate.

- [ ] `/calendar/month` — grid renders. Press `h` and `l`. Cursor moves ±day.
      Press `j` and `k`. Cursor moves ±week.
- [ ] `/calendar/schedule` — list view. Breadcrumb inverts: `[month-label]`
      becomes the link, `[schedule]` is active.
- [ ] Filter chips toggle visible entries.
- [ ] Click `[+]`. Default-create flow opens.
- [ ] On a `/channels/:slug/edit` field gated to 14 days, submit a change. Then
      visit `/calendar/schedule`. Reminder entry visible.

---

## 8. Notifications surface

**Contract:** Modal-on-navbar pattern (Phase 16). `[ ] unread` filter chip +
bulk mark-read. Notification kinds + severities + glyphs (legend rendered).
Daily cleanup cron (7 days).

- [ ] Click `[notifications]` in the navbar. Modal opens (does NOT navigate).
      Standalone `/notifications` still works for JS-off fallback.
- [ ] Toggle `[ ] unread` filter chip. List narrows.
- [ ] Select rows, bulk mark-read. Confirm.
- [ ] Confirm the glyph legend renders at the top of the modal (kinds +
      severities).
- [ ] Visit `/sidekiq/cron`. Confirm notification daily cleanup cron is
      scheduled.

---

## 9. Settings surface

**Contract:** `ui / ux` section (theme picker + keyboard-nav toggle), user
account, YouTube credentials status card (configured / not-configured per
credential), Phase 26 webhooks (Slack 01b + Discord 01c) — URL + everything /
daily_digest toggles + test-ping + `[update]`, Phase 26 01a timezone picker
(IANA dropdown, browser-detected default, applies to render layer).

- [ ] `/settings` — `ui / ux` pane shows theme picker (light / dark / auto) and
      keyboard-nav toggle. Flip the toggle. Confirm
      `data-keyboard-navigation-enabled` on `<body>` reflects the change.
- [ ] User account pane visible.
- [ ] YouTube credentials status card: `configured` or `not configured` per
      credential (master key, client id, client secret).
- [ ] Slack webhook pane: URL field + `everything` + `daily_digest` toggles +
      `[test ping]` + `[update]`. Submit a known-good URL → test-ping delivers →
      row saves. Submit a malformed URL → form re-renders with regex error.
- [ ] Discord webhook pane: same shape. Different regex (accepts both
      `discord.com` and `discordapp.com`). Submit, test-ping, update.
- [ ] Timezone picker: IANA dropdown. Browser-detected default visible (the
      `timezone-detect` Stimulus controller silently PATCHed if the stored value
      was `Etc/UTC`). Change it. Refresh. Confirm render-layer dates and times
      now display in the new zone.

---

## 10. Search surface

**Contract:** Global `[/]` search modal + per-resource search (channels, videos,
projects, games) + IGDB search (`i` hotkey).

- [ ] Press `/` anywhere. Global search modal opens. Type a query. Submit.
- [ ] Press SPACE → `/` → `C` (channels search) → type a channel query.
- [ ] Press SPACE → `/` → `V` (videos search). Same.
- [ ] Press SPACE → `/` → `P` (projects search). Same.
- [ ] Press SPACE → `/` → `G` (games search). Same.
- [ ] Press `i`. IGDB search modal opens. Type a game name. Submit. Pick a
      result. `[add]` (new) or `[update]` (existing-game overwrite via the
      shared overwrite-confirmation modal).

---

## 11. Keybindings (Phase 7.5 schema)

**Contract:** Single source of truth at `config/keybindings.yml`. Loaded by both
the Rails app (Stimulus `leader-menu`) and the `pito` CLI (serde*yaml + Ratatui
overlay). Leader: SPACE. Web indicator:
`[*]`in footer. TUI indicator:`[_]`in status bar.`?` opens the help modal.

- [ ] Press SPACE on any page. Leader menu opens bottom-right. Items: `h` home /
      `c` calendar / `C` channels / `V` videos / `P` projects / `G` games / `N`
      notifications / `S` settings / `/` search / `|` list ops / `Q` quit +
      logout. (`q` quit is TUI-only.)
- [ ] Press `C`. Navigate to `/channels` + drill into channels submenu. Items:
      `l` list / `+` add / `-` delete / `y` sync.
- [ ] Press Backspace. Up one level (back to root). Press Esc. Close.
- [ ] On `/channels`, press `j` / `k`. Row cursor moves down / up.
- [ ] Press `h` / `l` on a list page. Page prev / next.
- [ ] On a channel row, press `s` (star), `x` (toggle selection — replaces
      legacy SPACE), `D` (delete), `Y` (sync), `e` (edit), `r` (resync).
- [ ] Press `?`. Help modal opens documenting the current keymap.
- [ ] Click the `[_]` link in the footer. Same modal opens (alongside the leader
      popup).
- [ ] In the `pito` CLI: launch the TUI, press SPACE. Same leader menu via
      Ratatui overlay. Status bar shows `[_]`.

---

## 12. Analytics

**Contract:** Phase 13 — 12 timeseries tables + nightly sync orchestrator +
dashboards. Refresh-now buttons with per-resource rate limit (5-second locks).
Charts: chartkick + groupdate, no red, no animation. Backfill rake task
`analytics:backfill`.

- [ ] On `/channels/:slug`, scroll to the analytics summary. Confirm chart
      renders, no animation, no red.
- [ ] Click `[refresh now]`. Confirm refresh completes. Re-click within 5
      seconds — confirm rate-limit message.
- [ ] On `/videos/:slug`, confirm the analytics pane renders with the same
      contract.
- [ ] In a terminal: `bundle exec rake analytics:backfill`. Confirm backfill
      runs without error.
- [ ] Visit `/sidekiq/cron`. Confirm the nightly analytics sync orchestrator is
      scheduled.

---

## 13. Sync engine

**Contract:** Channel sync via OAuth (Phase 7.5 11a) — on-connect + on-demand +
daily diff-check cron (11i). Video sync (Phase 23) — same diff-dialog pattern.
Import vs sync distinction: import pulls new videos (Phase 22); sync diffs
existing. No silent overwrites — every sync produces a diff page.

- [ ] On `/channels`, select a connected row + click bulk `[sync N]`.
      Action-screen confirms. Confirm. Diff page renders for any drift. Apply
      per field.
- [ ] Same for videos — `[sync]` row button routes to the diff page (never
      overwrites).
- [ ] On a fresh channel: trigger import via `/channels/:slug` → `[import]`. New
      videos arrive. Existing videos are untouched (no duplicates —
      `RejectedVideoImport` tombstones honored).
- [ ] Confirm `channel_diff_check` daily cron scheduled at `/sidekiq/cron`.
- [ ] Confirm `video_diff_check` daily cron scheduled.

---

## 14. MCP surface

**Contract:** Two scopes (ADR 0004 — `dev` + `app`). Future `auth` scope queued
for Phase 25 01d (not yet shipped).

- **`dev` scope** (Mobile interop): `list_docs`, `read_doc`, `save_note`.
- **`app` scope**: `get_channel`, `update_channel`, `list_channels`,
  `list_videos`, `list_notifications`, `mark_read`, `mark_all_read`, `badge`,
  `channel_changes_list`, `channel_diff_show`, `channel_diff_apply`,
  `video_diff_show`, `video_diff_apply`, `igdb_search`, etc.
- **`auth` scope (planned, 01d)**: `login_attempts_pending`,
  `login_attempts_list`, `login_attempt_approve`, `login_attempt_block`,
  `login_attempt_purge`, `login_attempt_unblock`.

- [ ] Boot `bin/mcp` (stdio) or `bin/mcp-web` (HTTP on :3001).
- [ ] From a Claude session with a `dev`-scoped token, call `list_docs` with
      `prefix: "plans/beta/"` + `name_pattern: "log.md"`. Confirm sorted by
      mtime.
- [ ] Call `read_doc` on one of the logs.
- [ ] Call `save_note` with a one-line markdown body. Confirm it lands under
      `docs/notes/<timestamp>-<slug>.md`.
- [ ] From an `app`-scoped session: `list_channels` → `get_channel` →
      `channel_diff_show` (if any drift) → `channel_diff_apply` with
      `confirm: "yes"`.
- [ ] `list_videos` → `video_diff_show` → `video_diff_apply`.
- [ ] `igdb_search` with a known game name.
- [ ] `login_attempts_list` (currently gated on `app` scope as a placeholder per
      01a; will move to `auth` in 01d). Confirm `is_success` / `is_failed` /
      `is_blocked` Booleans serialize as `"yes"` / `"no"`.
- [ ] `login_attempts_pending` — same shape; `is_pending` / `is_expired` /
      `has_session` as yes/no.

---

## 15. CLI surface (`pito` binary at `extras/cli/`)

**Contract:** TUI is the default mode. Subcommands: `footage`, `games`,
`calendar`, `notifications`, `auth`, `search`, `views`. Phase 18 added CLI
parity against Phase 21 JSON endpoints. Row selection key is `x` (changed from
SPACE — keyboard-schema unification).

- [ ] `cargo run --bin pito` (no args) — launches the TUI.
- [ ] Press SPACE in the TUI. Leader menu overlay appears (Ratatui).
- [ ] Navigate to channels via the leader. Press `x` to toggle selection on a
      row (NOT SPACE).
- [ ] `pito auth login` — log in via the CLI auth subcommand.
- [ ] `pito auth whoami` — confirm the logged-in user.
- [ ] `pito search "<query>"` — runs the global search against the Rails
      backend.
- [ ] `pito views` — lists saved views (parity with `/saved_views`).
- [ ] `pito games list`, `pito calendar`, `pito notifications` — confirm JSON
      parity with `/games.json`, `/calendar/*.json`, `/notifications.json`.
- [ ] `pito footage <args>` — Phase 4 footage import path.
- [ ] `pito help` + `pito version` — confirm `claude`-style help / version
      output.
- [ ] `cargo test` in `extras/cli/` — confirm ~710 tests pass.

---

## 16. Tests + gates

**Contract:** Roughly 7000+ RSpec examples (Rails), ~710 cargo tests (Rust CLI).
CI: rspec, rubocop, brakeman, prettier-check on markdown. Pre-commit: gpg-signed
commits, rubocop hooks on.

- [ ] `bundle exec rspec` — full Rails suite green. (Take note if any
      pre-existing red appears; see §17 for tracked exceptions.)
- [ ] `bundle exec rubocop` — clean.
- [ ] `bin/brakeman -q -w2` — no new warnings.
- [ ] `prettier --check '**/*.md'` — clean.
- [ ] `cd extras/cli && cargo test` — green.
- [ ] `cd extras/cli && cargo clippy --all-targets -- -D warnings` — clean.
- [ ] Confirm latest CI run on `main` is green.

---

## 17. Phases NOT yet implemented

Specs exist but no implementation has landed. Walk-steps for these surfaces will
be added when each sub-spec ships. Do NOT bump the version on the assumption
these work.

> **Amended 2026-05-11 (afternoon session):** statuses below were re-audited
> after ~15 commits landed since the playbook write. See the "2026-05-11 session
> deltas" section at the bottom for what shipped between the original write and
> this amendment.

**Phase 25 — Login Security + New-Location Approval (specs landed; 01a + 01b
implemented; 01c through 01g pending — unchanged since playbook write):**

- 01c — Notifications integration (web + TUI delivery of login-pending
  notifications via Phase 16 pipeline)
- 01d — MCP tools full set (`login_attempts_*` family + dedicated `auth` scope
  catalog wiring; today the tools are gated on `app` as a placeholder)
- 01e — TOTP 2FA + backup codes (`rotp`, 1Password-compatible seed, AR
  Encryption)
- 01f — Auto-block list + purge UI (BlockedLocation operator surface)
- 01g — Rate limiting + session hardening pass + cross-cutting system specs

**Phase 26 — Webhooks + Timezone + Viewer Analytics (specs landed; 01a + 01b +
01c implemented; 01d IN FLIGHT — see deltas; 01e through 01h pending):**

- 01d — Help-modal Markdown guides (Slack + Discord onboarding). **Currently in
  flight** in the working tree (settings restructure + help-modal updates). Not
  yet committed.
- 01e — Daily digest scheduler (hourly sidekiq-cron + provider-specific
  payloads)
- 01f — Analytics architecture + tz update (`docs/architecture.md` "Timezone
  rendering rule" + "Viewer-time aggregation" sections)
- 01g — Viewer-time analytics implementation (`video_viewer_time_buckets` +
  heatmap component + per-video / per- channel analytics tabs)
- 01h — Video scheduled-publish tz wiring

**Phase 27 — Games Listing Rework (specs landed; 01a + 01c-v1 + 01d + 01e
implemented; 01c-v2 + 01h specs WRITTEN, impl PENDING; 01b + 01f + 01g
pending):**

- 01b — Filter row + platform semantics (`FilterRowComponent` +
  `Games::Filter` + URL state + platform-precedence combinator)
- 01c-v2 — **Nested shelves** (spec landed; supersedes flat-shelf 01c-v1). Outer
  Genres / Custom-collections shelves, each iterating one inner
  horizontally-scrolling sub-shelf per non-empty bucket. Adds
  `Game#primary_genre_id` + bucket-resolver service. Impl pending.
- 01f — Game show/edit per-platform ownership UI
  (`Games::PlatformOwnershipsController` + checklist editor)
- 01g — MCP / CLI parity (`game_update_local` plural + CLI filter chips + Rust
  tests)
- 01h — Collections CoverComposer (compound cover for collection sub-shelf
  leader tile, reuses Phase 14 `Composite::Builder` via a freshly-extracted
  `Compositable` concern). Spec landed; impl pending.

**Phase 11 — Video workflow features:** entirely unstarted. Specs not written;
not in this beta.

---

## 18. Deferred

Explicitly deferred — NOT a blocker for beta version bump.

- **Phase 12 — Distribution / packaging / installer:** deferred ~6 months per
  beta plan. Beta is dogfood-grade, not yet shippable to third parties.
- **B5 — DB reset + seed workflow:** queued, not blocking. Today setup is manual
  via `bin/setup` + credentials editing.

Active follow-ups tracked in `docs/orchestration/follow-ups.md` (Channel Revamp
post-commit cleanup, Rails-app keyboard-shortcut parity with `pito`, `pito`
screen layout parity, `pito` CLI Dependabot alert #1) remain queued after Phase
4 completes — they are non-blocking for the beta bump.

---

## Status verdict

> Fill in after walking the playbook.

- **Date walked:**
- **Walked by:**
- **Top-line status (READY / NOT READY for version bump):**
- **Blockers (if any — link to follow-up issues):**
- **Notes / surprises:**
- **Version bump to:**

---

## 2026-05-11 session deltas

> Audit run against ~15 commits landed since the playbook was first written
> (`6348d4b`). Append-only. The sections above retain their original walks; the
> deltas below note what changed on each surface so a re-walk can re-prioritize.
> Working-tree state at audit time: settings restructure + help-modal updates
> are uncommitted (in flight). Notes folder is empty (`.gitkeep` only) after
> commit `0262bff` curated 26 processed notes out of `docs/notes/`.

### Validation status per section

| §   | Surface                      | Status                         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --- | ---------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Identity + auth              | ready to walk                  | Unchanged since playbook write.                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| 2   | Google + YouTube integration | mostly ready, ONE STEP CHANGED | The Google banner on `/channels` was **dropped** (commit `3cd14bb`). Walks that mention the banner need adjustment — see "Section 2 amendment" below.                                                                                                                                                                                                                                                                                                                           |
| 3   | Channels surface             | ready to walk                  | Avatar distortion fixed (commit `9a24910`). 8-column table unchanged.                                                                                                                                                                                                                                                                                                                                                                                                           |
| 4   | Videos surface               | partial — IN FLIGHT            | Video import modal has uncommitted edits in working tree (commit `4f183c2` is WIP `[skipci]`: bracketed checkboxes + breadcrumb fix + button rename). The `[import]` walk is touchable but copy / behaviour may shift before the next commit.                                                                                                                                                                                                                                   |
| 5   | Projects surface             | ready to walk                  | Unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 6   | Games surface                | partial — IN FLIGHT            | Tile meta now 2 lines (title \n ★ rating · year) per commit `9a24910`. Genre short-form display map committed. The flat 01c-v1 shelves currently live on `/games`; 01c-v2 nested shelves are specced but not implemented. Filter row (01b) still NOT shipped.                                                                                                                                                                                                                   |
| 7   | Calendar surface             | ready to walk                  | j/k row navigation extended to calendar-month + schedule (commit `c6f56b5`).                                                                                                                                                                                                                                                                                                                                                                                                    |
| 8   | Notifications surface        | ready to walk                  | j/k extended to notifications list.                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| 9   | Settings surface             | partial — IN FLIGHT            | Settings page is being restructured into 3 titled sections (`customize` / `integrations` / `stack`), 2-column each. Uncommitted in working tree. **Slack + Discord panes are deliberately dropped from the settings index** per the user-locked layout (controllers / routes / partials remain so request + view specs keep passing). YouTube credentials status card now reads `:google_oauth` credentials block (not `:youtube` — that block does not exist in this install). |
| 10  | Search surface               | ready to walk                  | Unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 11  | Keybindings                  | partial — IN FLIGHT            | Schema reverted: root-menu rows with a submenu now DROP the `action` field. Pressing `C` / `V` / `P` / `G` / `c` / `N` from the root popup drills into the submenu ONLY — the user must press `l` (list) inside the submenu to navigate. `S` (settings) and `h` (home) still navigate directly. Working tree contains in-flight dismiss-on-navigate fix touching the leader-menu controller + the shortcuts modal component.                                                    |
| 12  | Analytics                    | ready to walk                  | Unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 13  | Sync engine                  | ready to walk                  | Unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 14  | MCP surface                  | ready to walk                  | Unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 15  | CLI surface                  | ready to walk                  | Unchanged.                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| 16  | Tests + gates                | check after WIP lands          | Settings + keybindings WIP touches 9 files (5 controller / view / yaml / component + 4 specs). Re-run gates once the working tree is committed. CI was set to `[skipci]` default for routine work via commit `a5368eb`.                                                                                                                                                                                                                                                         |

### Section 2 amendment — Google banner dropped

The original walk for §2 referenced a Google banner on `/channels` with
`[+ add another Google account]` + per-account `[revoke]`. **Commit `3cd14bb`
dropped that banner** + removed the `_google_banner.html.erb` partial + view
spec. Google account add / revoke now happens exclusively via the channel-add
flow + per-channel revoke action; `/settings/youtube` still 301s to `/channels`,
but the visible affordance on `/channels` has changed.

Replace the §2 walk steps with:

- [ ] Visit `/settings/youtube`. Expect 301 to `/channels`.
- [ ] `/channels` no longer renders the Google banner. Confirm.
- [ ] Add a Google account through the channel-add flow (per the post-Phase 24
      affordance — verify the actual UI before walking).
- [ ] Confirm callback auto-discovers channels + duplicate-skips with a flash.
- [ ] `[revoke]` per-row still routes to action-screen + `DeleteChannelDataJob`.

### Section 6 amendment — Games surface state

The original §6 walk assumed the **flat** 01c shelf design (one tile per genre,
one tile per collection). That ships today, plus:

- Tile meta is now 2 lines (`title` \n `★ rating · year`).
- Genre tags use a short-form display map.
- Avatar distortion is fixed.
- Tile + list view + cover sizing all wired (01a + 01c-v1 + 01d + 01e).

**Pending direction change:** the 01c-v2 spec replaces the flat design with
NESTED shelves (outer Genres + Custom-collections shelves, each iterating one
inner horizontally-scrolling sub-shelf per non-empty bucket). When 01c-v2
implementation lands, §6 will need a full rewrite — the outer-shelf rows + the
sub-shelf scroll behaviour are both new affordances.

The §17 reference to "shelf cover variant at 65%" may bump to 70% per the 01c-v2
spec direction; recheck before walking.

### Section 9 amendment — Settings restructure

The original §9 walk listed YouTube credentials card + Slack pane + Discord
pane + timezone picker. Once the in-flight commit lands, the settings index will
instead present:

```
## customize
[ ui / ux ]              [ workspaces ]
[ user ]                 [ time zone ]

## integrations
[ YouTube ]              [ Voyage.ai ]
[ OAuth applications ]   [ sessions ]

## stack
[ sql ]                  [ search ]
[ storage ]              (empty right cell)
```

Slack + Discord panes are dropped from the index page. To walk Slack / Discord
end-to-end, hit the underlying routes directly (`/settings/slack_webhook`,
`/settings/discord_webhook`) or via spec coverage. Section 9 needs a rewrite
once the in-flight commit lands.

### Section 11 amendment — Keybindings drill-only semantics

The original §11 walk says: "Press `C`. Navigate to `/channels` + drill into
channels submenu." That copy is now wrong. Replace with:

- [ ] Press `C`. Leader menu drills into the channels submenu **without
      navigating**. Items: `l` list / `+` add / `-` delete / `y` sync.
- [ ] Press `l` to actually navigate to `/channels`.

`S` (settings) and `h` (home) still navigate directly because they have no
submenu. The combined action + submenu pattern was reverted because a single
keystroke firing both a navigate AND a drill was surprising.

The in-flight working-tree changes (uncommitted) add a dismiss-on-navigate
behaviour to the leader-menu Stimulus controller. Re-walk §11 after that commit
lands.

### Cross-cutting deltas

- **j / k row navigation extended:** commit `80d4d9f` + `c6f56b5` wired
  `data-keyboard-row` across channels, videos, projects, footages, collections,
  notes, games-grid, calendar-month, schedule, notifications. `h` / `l` = prev /
  next page (lists) or prev / next sibling (detail pages).
- **Genre short-form display map:** committed (helper-level, applies to game
  tile rendering).
- **`[skipci]` flag:** commit `a5368eb` added the `[skipci]` guard to 4
  workflows (`ci.yml`, `deploy-website.yml`, `pito-cli-publish.yml`,
  `website-ci.yml`). Routine work defaults to `[skipci]`; user-facing validation
  walks still expect green CI on the previous non-`[skipci]` commit.
- **`docs/notes/` curated to empty:** commit `0262bff` dropped 26 processed
  notes (model annotations folded into source files via annotate-models; spec /
  phase summaries folded into the relevant `additions.md` / `log.md` / phase
  docs). `docs/notes/` now contains only `.gitkeep`.
- **Phase 27 01h spec landed:** `Collections::CoverComposer` spec
  (`01h-collections-cover-composer.md`) is in place; implementation pending.
  Required for the 01c-v2 collection sub-shelves' leading compound-cover tile.

### Walk priority for a re-validation pass

1. Wait until the in-flight settings + keybindings + video-import WIP lands as
   discrete commits.
2. Re-run §16 gates (rspec / rubocop / brakeman / prettier-check / cargo).
3. Re-walk §2 (banner dropped), §6 (tile + cover changes), §9 (3-section
   restructure), §11 (drill-only semantics, dismiss-on-navigate) with the
   amended copy above.
4. Sections 1, 3, 4 (sans modal WIP), 5, 7, 8, 10, 12, 13, 14, 15 are unchanged
   — walk as written in the original sections.
5. Do NOT walk 01c-v2 nested shelves, 01h CoverComposer, or any Phase 25
   sub-spec from 01c onward — those are spec-only at this audit time.

### Files referenced by this delta section

- `docs/plans/beta/25-login-security-and-new-location-approval/log.md` — 01a +
  01b ship logs.
- `docs/plans/beta/26-webhooks-timezone-viewer-analytics/log.md` — 01a + 01b
  (Slack re-dispatch PORO STI refactor) + 01c (Discord) ship logs.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/log.md` —
  01a + 01c-v1 + 01d + 01e ship logs.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01c-v2-nested-shelves.md`
  — supersedes 01c-v1, impl pending.
- `docs/plans/beta/27-games-listing-shelves-filters-display-modes/specs/01h-collections-cover-composer.md`
  — compound-cover service, impl pending.
- `config/keybindings.yml` — drill-only semantics (working tree has the
  uncommitted reversion already documented in inline comments).
