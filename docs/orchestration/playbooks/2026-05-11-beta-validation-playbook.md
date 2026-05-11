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

**Phase 25 — Login Security + New-Location Approval (specs landed; 01a + 01b
implemented; 01c through 01g pending):**

- 01c — Notifications integration (web + TUI delivery of login-pending
  notifications via Phase 16 pipeline)
- 01d — MCP tools full set (`login_attempts_*` family + dedicated `auth` scope
  catalog wiring; today the tools are gated on `app` as a placeholder)
- 01e — TOTP 2FA + backup codes (`rotp`, 1Password-compatible seed, AR
  Encryption)
- 01f — Auto-block list + purge UI (BlockedLocation operator surface)
- 01g — Rate limiting + session hardening pass + cross-cutting system specs

**Phase 26 — Webhooks + Timezone + Viewer Analytics (specs landed; 01a + 01b +
01c implemented; 01d through 01h pending):**

- 01d — Help-modal Markdown guides (Slack + Discord onboarding)
- 01e — Daily digest scheduler (hourly sidekiq-cron + provider-specific
  payloads)
- 01f — Analytics architecture + tz update (`docs/architecture.md` "Timezone
  rendering rule" + "Viewer-time aggregation" sections)
- 01g — Viewer-time analytics implementation (`video_viewer_time_buckets` +
  heatmap component + per-video / per- channel analytics tabs)
- 01h — Video scheduled-publish tz wiring

**Phase 27 — Games Listing Rework (specs landed; 01a + 01c + 01d + 01e
implemented; 01b + 01f + 01g pending):**

- 01b — Filter row + platform semantics (`FilterRowComponent` +
  `Games::Filter` + URL state + platform-precedence combinator)
- 01f — Game show/edit per-platform ownership UI
  (`Games::PlatformOwnershipsController` + checklist editor)
- 01g — MCP / CLI parity (`game_update_local` plural + CLI filter chips + Rust
  tests)

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
