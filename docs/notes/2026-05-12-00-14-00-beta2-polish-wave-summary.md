# Beta2 polish wave — session summary

Captured 2026-05-12 by the docs-keeper at the close of the beta2 polish wave.
This note is for Mobile to read via `read_doc` on the next session start so the
"what just shipped" picture loads in one file.

## Cadence

8+ convergent commits across ~40+ agents (architect / rails-impl / mcp / rust /
docs / reviewer / security / auditor) over two days (2026-05-10 → 2026-05-12).
The polish wave bracketed by:

- Open: Phase 27 architect spec landing (`316ab6a` — games listing rework, 9
  specs).
- Close: docs handoff (this note) + Phase 28 01a Rails + MCP, Phase 11 01a video
  edit page polish, channel show YouTube-style layout.

Every commit in the wave carried the `[skipci]` token; the CI guard documented
in `docs/orchestration/follow-ups.md` short-circuits the workflows for the
docs-and-polish cadence.

## Phases closed in this wave

- **Phase 25 — Login Security + New-Location Approval.** Sub-specs 01a–01g
  shipped. 01c (TUI new-location overlay), 01g (rate-limit + session hardening),
  01e (TOTP 2FA + backup codes), 01f (auto-block list + purge UI), 01d (MCP
  `login_attempts` tools), 01a (attempt logging + fingerprint), 01b
  (new-location detection + pending sessions), 01c-rails (notifications
  integration), plus three security fix-forwards (F4 backup- code consumer
  hardening, F9 TOTP replay defense via `totp_last_used_step`, F10
  SecureRandom-backed code generation).
- **Phase 26 — Webhooks + Timezone + Viewer-Time Analytics.** 01a (timezone
  foundation), 01b (Slack webhook pane), 01c (Discord webhook pane), 01d
  (help-modal Markdown guides), 01e (daily digest scheduler), 01f (analytics
  architecture + tz docs), 01g (viewer-time analytics), 01h (video
  scheduled-publish tz wiring). Plus reviewer non-blocking concerns
  (install-level digest dispatch, heatmap tooltip accessibility,
  `Pito::TimeZone` relocation).
- **Phase 27 — Games Listing / Shelves / Filters / Display Modes.** Sub-specs
  01a–01h shipped (per-platform ownership data model, filter row + platform
  semantics, genres + collections shelves, nested shelves, display mode
  switcher, shelf cover-art variant, game show/edit per-platform ownership UI,
  MCP `game_update_local`, collection cover composer). Plus Phase B2
  non-blocking concerns (GenreShelfBatch + Filter subquery + N+1 guard).
- **Phase 28 — Multi-version Game Grouping.** 01a Rails + MCP shipped end-to-end
  (Game `version_parent_id` + `version_title` schema, IGDB sync walk,
  primaries-only scope, MCP tools, rake backfill). 01b CLI half deferred —
  tracked in `docs/orchestration/follow-ups.md`.

## Phase 11 — Video workflow features (in flight)

- **Architect spec landed** on 2026-05-11 (`86ef06e`) — 1687 lines, 7 open
  questions, six sub-spec files (01a video edit page polish, 01b pre-publish
  checklist expansion, 01c post-publish workflow, 01d series/sequel tracking,
  01e video links section polish, 01f MCP/CLI parity).
- **01a shipped** on 2026-05-11 (`e4da516`) — thumbnail attachment + tags
  field + chapters nested attributes + end-screens nested attributes + the
  `nested_form_controller.js` Stimulus controller + 91 new specs across models /
  requests / views / system.
- **01b–01f queued** for sequential `pito-rails-impl` dispatch as the open
  questions resolve.

## Big-ticket polish surfaces

- **Settings stack v3.** Storage pane title trim (size/files dropped), notes
  table relabel (`project` instead of `project notes`, `mobile_notes` dropped
  for prod surface), Postgres model rename (`calendar_entries` → `calendar`
  display label), integrations row reshape (Discord + Slack on row 2, OAuth
  apps + sessions on row 3 — 7 pane-rows / 13 panes total).
- **YouTube credentials → AppSetting (ADR 0007).** Encrypted columns on the
  singleton row, four-tier omniauth resolver, rake backfill task. Operator
  rotation moves from `credentials:edit` + redeploy to Settings form + Puma
  restart. Hot rotation is the next iteration (lambda options instead of
  boot-time read).
- **Channel show YouTube-style layout.** 6.2:1 banner, 160px avatar, 28px
  headline column; analytics + Google connection side-by-side in a single
  pane-row; detail pane uses `.pane--wide` (matches 2-pane row width); zebra
  panes drop `pane--standalone` from analytics + Google panes; equal-height row
  2; title casing `[YouTube] [Studio]`.
- **Calendar refactor.** Daily digest scheduler with install-level anchor (one
  digest per install per day, regardless of user count); video scheduled-publish
  tz wiring; help-modal Markdown guides for webhook panes (5 doc links per
  provider).
- **Games surface v2.** Filter checkboxes (Phase 27 01b), primary-genre picker
  (six-bundled `/games` follow-ups), collections modal, multi-version grouping
  (Phase 28 01a — parent / edition pointers, IGDB walk, rake backfill, MCP
  tools).
- **2FA modal flow (ADR 0009).** Shared `<dialog>` modal with segmented 6-digit
  input, auto-submit on the 6th digit, paste-fill ergonomics, replaces seven
  inline TOTP fields across login + settings + webhook rotations + user-account
  writes.
- **StatusBadge + RatingBadge components (ADR 0008).** Shared cross-cutting
  `StatusBadgeComponent` (info / success / warn / urgent / yes / no / all_day) +
  per-domain `RatingBadgeComponent` (six tier colors). Replaces
  `.notification-severity-badge` + `.calendar-badge--all-day` + ad-hoc
  rating-tier classes. CSS-variable-driven.
- **Custom scrollbar styling.** Vertical + horizontal, sitewide.
- **Videos import modal UX redesign.** Bracketed-checkbox row, race-condition
  reload, nuanced completed labels, breadcrumb fix, rubocop autocorrect.
- **Cloudflare trusted-proxies drift watchdog (ADR 0010).** Weekly Monday 09:00
  UTC job diffs `https://www.cloudflare.com/ips-{v4,v6}` against the hardcoded
  list in `production.rb`; emits a `sync_error` notification on drift. Manual
  operator merge.
- **YouTube Analytics cross-report query split (ADR 0011).** `DAILY_METRICS` →
  `DAILY_BASIC_METRICS` + reserved `DAILY_ENGAGEMENT_METRICS`;
  `WINDOW_RATIO_METRICS` slimmed to `averageViewPercentage` only. Multi-call
  plus merge reserved as a future architect spec.

## Migrations applied this session

- `20260511153000_add_youtube_credentials_to_app_settings` — YouTube credential
  columns on `app_settings` (per ADR 0007).
- `20260511204435_create_video_chapters` — `video_chapters` table (Phase 11
  01a).
- `20260511204436_create_video_end_screens` — `video_end_screens` table (Phase
  11 01a).
- `20260512000000_add_version_parent_to_games` — `games.version_parent_id`
  self-FK + `games.version_title` (Phase 28 01a).
- `20260512000100_add_totp_last_used_step_to_users` — TOTP replay defense
  watermark (Phase 25 F9 fix-forward).

## Outstanding queue items (small)

1. Phase 11 sub-specs 01b–01f — pre-publish checklist, post-publish workflow,
   series/sequel tracking, video links polish, MCP/CLI parity. Architect specs
   ready; dispatch in sequence.
2. Phase 28 01b — CLI multi-version game grouping (primaries-only render +
   drill-down + flat-mode toggle).
3. YouTube credentials hot-rotation gap — switch omniauth to lambda options so
   Settings → YouTube updates take effect without a Puma restart.
4. Phase 13 analytics multi-call merge — engagement metrics and three click-
   rate ratios are reserved (`NULL` columns today); future architect spec adds
   the dedicated `reports.query` calls.

## Paused

- **MCP surface work** — pending the 2026-05-09 realignment dispatches (MCP
  scope simplification work unit + tenant drop work unit).
- **TUI / `pito-rust` work** — paused on the broader CLI parity sweep (work unit
  10 in the realignment). The Phase 28 01b CLI half is the next dispatch when
  CLI work resumes.
- **CLI feature-parity sweep** — channels list / videos list / settings panes /
  search results. Carved out of Phase 7.5 Track B step 02; queued behind the
  realignment work units.
