# Beta progress snapshot — 2026-05-11 00:30

## Implementation: ~88%

## What landed since 22:30

### Phase 21 (JSON endpoints for CLI/MCP parity) — DONE

- 11 endpoints across games / calendar / notifications
- 3 decorators, 21 jbuilder views
- +163 specs

### Phase 21 CLI parity — DONE

- `pito games` / `pito calendar` / `pito notifications` subcommand families
- +145 Rust tests
- Auth posture flagged for follow-up (CLI is bearer; Phase 21 endpoints are
  cookie-session)

### Phase 7.5 Step 11a (channel schema + sync foundation) — DONE

- 3 migrations: channel resource fields, `channel_change_logs`, `Video.title`
- `Channel#title_locked?`, `handle_locked?`, `title_unlock_at`,
  `handle_unlock_at` helpers (14-day gate)
- `Youtube::Client#fetch_channel` extension
- `ChannelSync` job rewritten to real fetch path
- +115 specs

### Phase 7.5 Step 11 sub-specs DRAFTED (not yet implemented)

- 11b channel show page revamp (472 lines, 6 OQ)
- 11c channel edit form (587 lines, 7 OQ)
- 11h calendar reminder integration (242 lines, 5 OQ)
- 11i daily diff-check cron + resolution page (664 lines, 8 OQ)

### Phase 22 — Video import flow

- Architect spec (845 lines, 6 OQ)
- Implementation IN FLIGHT (with locked decisions)

### Phase 23 — Video sync with diff dialog

- Architect spec (583 lines, 8 OQ)
- Implementation IN FLIGHT (with locked decisions)

### OAuth + Settings/youtube overhaul

- OmniAuth scope set widened to full YouTube scopes (`youtube.readonly`,
  `yt-analytics.readonly`, `youtube.force-ssl`)
- 403 PERMISSION_DENIED for insufficient scopes now classifies as
  `NeedsReauthError` (not PermanentError) so `[reconnect]` renders cleanly
- Multi-`YoutubeConnection` support (Path A) + `prompt=select_account` flow
  (Path B)
- `/settings/youtube` restructured: unified table with rowspan-2 per record,
  bulk-select checkboxes, `[disconnect N]` bulk action via action-screen,
  `[+ add another Google account]` below table, brand-account email truncation
- Channel discovery on OAuth callback (auto-add `mine: true` channels;
  duplicates skipped silently with flash note)
- /channels/new URL-paste path DROPPED entirely

### Settings index Google pane

- Channels summary line aggregating all linked channels
- Multi-connection rendering (email per line, `+N more` indicator)
- Brand-account email truncation

### UX polish

- `[bulk]` toggle dropped app-wide (web + TUI) — checkboxes always visible
- Notifications navbar → modal (not page nav)
- Channel show heading: `[|]` → `[+]`
- `/videos?channel=<slug>` filter + filter chip
- Layout footer: `[?]` → `[_]` (leader = SPACE)
- `[ ] unread` filter chip on /notifications (already in)
- Calendar breadcrumb: schedule view inverts `[may YYYY]` link / `[schedule]`
  text
- Video show: stats moved to own row below detail
- Brand casing sweep: "Google" canonical capital case
- Avatar styling on settings (32px rounded)

### Connected attribute

- Derived `connected` surface dropped app-wide (scope, decorator field, MCP
  filter, picker chip, factory trait, [connect]/[disconnect] actions)

### Security follow-ups

- Phase 13 F1+F2+F3 fix-forward (ServiceFactory routing + retry-on-401 +
  per-resource refresh lock)
- Phase 14 F1+F2 fix-forward (IGDB Client + TileCache timeouts) +
  Igdb::TokenCache third-path fix
- Phase 16 02/03 F1+F2+F3 fix-forward (URL scheme allowlist + per-user mark-read
  rate limit)

## Suite size

~5000+ RSpec examples (up from ~4400 at 22:30), all green except 2-3
pre-existing flakes confirmed unrelated.

## Outstanding (the path to 100%)

### Implementation IN FLIGHT

- Phase 22 (video import flow)
- Phase 23 (video sync diff dialog)
- Settings ui/ux section + keyboard-nav AppSetting toggle
- Drop seeded channels + Settings card copy fix

### Specs done, implementation pending

- Phase 7.5 Step 11b (channel show revamp)
- Phase 7.5 Step 11c (channel edit form)
- Phase 7.5 Step 11h (calendar reminder)
- Phase 7.5 Step 11i (daily diff cron + resolution)

### Specs not yet written

- Phase 7.5 Step 11d (multi-layout preview component)
- Phase 7.5 Step 11e (watermark preview)
- Phase 7.5 Step 11f (banner upload flow)
- Phase 7.5 Step 11g (change history view)
- Keybindings unified schema implementation (`config/keybindings.yml` +
  Stimulus + TUI Ratatui)

### Phase 8 — YouTube Data Sync (deferred)

- Broader sync orchestration on top of Step 11a foundation
- Daily cron for video metadata + analytics
- ~30% done via Step 11a + Phase 13

### Deferred / blocked

- Phase 11 (video-workflow-features) — not started
- Phase 12 distribution — deferred ~6 months
- B5 DB reset + seeds workflow — user deferred pending screen review

## Open questions awaiting user input

- 11b: sparkline vs summary in analytics section; starred + latest dedup; banner
  pre-sync rendering; description markdown vs plain
- 11c: watermark dimension validation; remind-me copy; max-5 enforcement layer;
  inline crop
- 11h: toast position; reminder time default; duplicate handling
- 11i: notification dedupe; default radio posture; partial-failure UX; CDN
  rotation filtering
- 22: 6 open questions auto-locked (deferred re-enqueue, per-channel
  confirmation, keep-forever retention)
- 23: 8 open questions auto-locked (14-day rate-limit research, per-video diff
  pages)

## Master agent's next moves

1. Land 4 in-flight agents → commit
2. Dispatch implementation for 11b / 11c / 11h / 11i (specs ready)
3. Architect specs for 11d / 11e / 11f / 11g (the remaining Step 11 sub-specs)
4. Loop to 100%
