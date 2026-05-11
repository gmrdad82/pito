# Phase 26 — Slack/Discord webhook panes + User timezone + Viewer-time analytics

> **Status:** scaffolded by `pito-architect`. Plan + 8 sub-specs (01 umbrella +
> 01a–01h). No code, no commits yet. Dispatch begins after the user reviews and
> resolves the open questions listed in each sub-spec.

## Source of truth

- `docs/notes/2026-05-11-11-12-17-webhooks-timezone-viewer-time-analytics.md` —
  the Claude Mobile drop that originated this phase. Verbatim text drives every
  acceptance bullet in the sub-specs.
- `docs/realignment-2026-05-09.md` — confirms Discord + Slack webhook delivery
  is already in the realignment scope (under "Notification surface + delivery
  channels") and that `notification_delivery_channels` rows ship in Phase 16
  (Notifications). Phase 26 reuses that table; it does not re-create it.

## Why this phase, why this bundle

Three feature areas land together because they touch each other:

1. **Slack + Discord webhook panes** add two new Settings panes wired to the
   existing `notification_delivery_channels` table (Phase 16) with provider-
   specific URL validation, a mandatory test ping, and per-provider state
   (`everything` and `daily_digest` booleans).
2. **User timezone** is the foundation the daily-digest scheduler runs on, and
   the rendering layer every analytics view computes against. UTC stays the
   storage rule; user-tz is the render contract. No exceptions.
3. **Viewer-time analytics** (best-time-to-publish heatmap) is a brand-new
   analytics surface gated on the timezone foundation — every bucket rendered in
   user-tz, every "today" / "this week" computed in user-tz, every aggregate
   rolled up from UTC-stored raw buckets at query time.

The timezone foundation (01a) blocks the digest scheduler (01e), the analytics
architecture update (01f), the viewer-time implementation (01g), and the
scheduled-publish wiring (01h). The two webhook panes (01b, 01c) and the help
modal Markdown content (01d) ride alongside without timezone dependency, except
that 01e cannot ship until 01b + 01c are in.

## Phase number assignment

Phase 26 follows Phase 25 (next sequential slot). On-disk folder is
`docs/plans/beta/26-webhooks-timezone-viewer-analytics/` — full descriptive
slug, no abbreviation. Consistent with the Phase 19 / Phase 25 naming convention
where the folder name carries the phase's three-word identity.

The 2026-05-09 realignment lists "Notification surface + delivery channels"
under "New spec — net-new scope." Phase 26 implements two webhook delivery
channels (Slack + Discord) and the daily-digest scheduler on top of the existing
`notification_delivery_channels` table from Phase 16. Phase 26 also implements
the timezone foundation the realignment's calendar / analytics work assumed but
never explicitly scoped, and the viewer-time analytics surface noted in
realignment work unit 6 (YouTube Analytics) as "cross-video locals (when-to-
publish)."

## Sub-specs (dispatch order)

### Foundation (must ship first)

- [ ] **01 — Overview** (`specs/01-overview-webhooks-tz-viewer-analytics.md`).
      Umbrella. Reads top-down, summarizes scope, points at the eight sub-specs
      below, restates the locked decisions and open questions for the user.
      Docs-only; no dispatch agent.

- [x] **01a — Timezone foundation** (`specs/01a-timezone-foundation.md`).
      User.time_zone column + IANA name validation +
      browser-detection-on-first-load + `Etc/UTC` fallback + tz-aware render
      helpers + ApplicationController hook setting
      `Time.zone = Current.user.time_zone`. **Blocks 01b autosave UX, 01d help
      modal rendering, 01e digest scheduler, 01f analytics architecture, 01g
      viewer-time implementation, and 01h scheduled-publish wiring.**

### Webhook panes (can ship parallel with 01a; tests merge after 01a lands)

- [x] **01b — Slack webhook pane + validation**
      (`specs/01b-slack-webhook-pane-and-validation.md`). New `slack` pane on
      `/settings`. Single URL input, regex validation, mandatory test ping,
      `everything` + `daily_digest` checkboxes. Writes a single
      `notification_delivery_channel` row keyed on `kind: "slack"`. Help link
      opens 01d's Markdown modal.

- [x] **01c — Discord webhook pane + validation**
      (`specs/01c-discord-webhook-pane-and-validation.md`). Mirror of 01b for
      Discord. Different regex, different test-ping payload (Discord requires an
      inline `content` field), independent row keyed on `kind: "discord"`. Both
      `discord.com` and `discordapp.com` host forms accepted.

- [x] **01d — Help-modal Markdown guides**
      (`specs/01d-help-modal-markdown-guides.md`). Two beginner-friendly
      Markdown guides (one Slack, one Discord) served through Phase 16's
      existing Markdown renderer. Modal pattern reuses Phase 7.5 keyboard-
      shortcuts modal scaffolding (no JS `confirm` / `alert`; close on Esc /
      backdrop click). Files in `app/views/settings/webhooks/help/`.

### Digest delivery (depends on 01a + at least one of 01b/01c)

- [x] **01e — Daily digest scheduler** (`specs/01e-daily-digest-scheduler.md`).
      Hourly sidekiq-cron job picks users whose user-local time just crossed
      09:00. Renders provider- specific digest payload (Slack blocks, Discord
      embeds), POSTs to each enabled `notification_delivery_channel`, retries on
      transient failures, gives up cleanly on 4xx. DST + cross-tz edge cases
      specced exhaustively.

### Analytics (architecture + implementation)

- [ ] **01f — Analytics architecture + tz update**
      (`specs/01f-analytics-architecture-tz-update.md`). Documentation-only
      update to `docs/architecture.md` (new "Timezone rendering rule" section +
      new "Viewer-time aggregation" section). Pins the storage / render contract
      for analytics surfaces, week-start defaults (Monday, configurable later),
      and the source-endpoint + granularity decision for YouTube Analytics'
      hourly viewership. Parallel-safe with everything.

- [x] **01g — Viewer-time analytics implementation**
      (`specs/01g-viewer-time-analytics-implementation.md`). New
      `video_viewer_time_buckets` table + per-video sync job + daily rollup
      job + `ViewerTimeHeatmapComponent` ViewComponent + per-video and per-
      channel analytics tabs. UTC-stored buckets, user-tz rollup at query time.
      Depends on 01a + 01f.

### Scheduled publish wiring (depends on 01a)

- [x] **01h — Video scheduled-publish tz wiring**
      (`specs/01h-video-scheduled-publish-tz-wiring.md`). Wire the existing
      scheduled-publish picker through `Current.user.time_zone`. Pre-publish
      checklist + "publishing in 1 hour" reminders render in user-tz; the job
      that triggers the publish converts to UTC at storage and fires at the
      correct UTC instant. Specs cover DST jurisdictions (US-East), edge zones
      (`Pacific/Kiritimati`, `Pacific/Pago_Pago`).

## Locked decisions (set before dispatch, do not re-litigate)

These were locked by the user in the Mobile drop and the follow-up direction
conversation. Every sub-spec encodes them; do not re-open in implementation.

1. **`User.time_zone`** — string column, IANA name (`Europe/Bucharest`,
   `America/Los_Angeles`, etc.). Default detection via JS
   `Intl.DateTimeFormat().resolvedOptions().timeZone` on first authenticated
   load. Default fallback: `"Etc/UTC"` when detection fails or returns nil.
   Validated against `ActiveSupport::TimeZone.all.map(&:tzinfo).map(&:name)`
   plus the IANA `tzdata` superset (Rails accepts both forms; we normalize to
   IANA on save).
2. **UTC storage, user-tz render.** No exceptions, anywhere. The render layer is
   the only conversion site.
3. **Hourly digest scheduler.** Cron at minute 0 every hour. Picks users whose
   local time just crossed 09:00 since the previous hour's run. Cross-tz + DST
   edge cases are explicitly specced (01e).
4. **Webhook URL regex:**
   - Slack:
     `\Ahttps://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+\z`
   - Discord:
     `\Ahttps://(discord|discordapp)\.com/api/webhooks/\d+/[A-Za-z0-9_-]+\z`
5. **Test-ping required before save.** If ping fails (HTTP non-2xx, timeout, DNS
   failure), the URL does NOT save and the form re-renders with the error
   message. Both panes follow this rule independently.
6. **Per-provider state.** Each provider row carries its own `everything` +
   `daily_digest` booleans. Not mutually exclusive; both / neither / either is
   valid. Slack on `everything` + Discord on `daily_digest` only is a valid
   configuration.
7. **`notification_delivery_channels` reuse.** Phase 16 already ships the table.
   Phase 26 writes one row per Settings webhook pane keyed on
   `kind: "slack" | "discord"`. No new table for webhook configuration.
8. **Help modal rendering.** Server-rendered Markdown via Phase 16's existing
   Markdown renderer (`NotificationFormatter` / `MarkdownRenderer` — verify
   exact class name during 01d dispatch). One `.md` file per provider in
   `app/views/settings/webhooks/help/`.
9. **Viewer-time analytics storage.** `video_viewer_time_buckets` table:
   `id, video_id, hour_of_day_utc (0–23), day_of_week_utc (0–6, Sunday=0 per Postgres `extract(dow
   ...)`), view_count, watch_time_seconds, last_synced_at, created_at, updated_at`.
   Composite unique index on `(video_id, day_of_week_utc, hour_of_day_utc)`.
   Rolled up to user-tz at query time. Refresh cadence: **daily** (see 01g for
   the open quota-budget question).
10. **Heatmap component.** ViewComponent. Two axes (day-of-week × hour-of- day).
    Color intensity = view_count by default (toggleable to watch_time later).
    Sized for both desktop and mobile (CSS grid; mobile collapses to a vertical
    stack of 7 daily strips). Single-hue intensity gradient — no red, per design
    rules.
11. **Channel-level aggregation.** `GROUP BY hour_of_day_utc, day_of_week_utc`
    across all `channel.videos`. Same heatmap component, channel-aggregate query
    feeding it.
12. **Boundary booleans.** Every JSON / MCP / form payload that carries the
    webhook checkbox states or the digest scheduler's "enabled" flag uses
    `"yes"` / `"no"` strings at the boundary, Boolean internally. See
    `CLAUDE.md` hard rule.

## Open questions (resolve before dispatch; see each sub-spec for context)

1. **Webhook autosave vs explicit `[update]` per pane.** Note says "TBD — match
   how the rest of Settings works." Existing Settings panes use an explicit
   `[update]` per section. Spec recommends explicit `[update]` for parity.
   **Confirm with user.** Surfaced in 01b + 01c.
2. **Daily digest content shape per provider.** Slack blocks vs Discord embeds
   differ in structure; the digest payload formatter has to emit two distinct
   shapes from the same source data. Detailed schema lives in 01e. **Open: how
   much surface to include in v1?** Suggestion: subject line + 3–5 bullets
   summarizing the last 24h. Confirm with user.
3. **Viewer-time refresh cadence.** Note says "daily? hourly? — TBD based on API
   quota." Suggestion: daily refresh, scheduled at 03:00 server time, one
   `VideoViewerTimeSyncJob` per owned video per channel. **Confirm with user
   once Phase 7 quota tracking surfaces real numbers.**
4. **Start-of-week locale dependency.** Default Monday per the Mobile note;
   configurable later. v1 ships Monday-only. Surfaced in 01f + 01g. Confirm.
5. **Heatmap color palette.** Per design system: no red. Suggestion: single- hue
   intensity gradient using the existing link blue (`#0000cc`) with alpha, or a
   muted teal / violet not used elsewhere. **Confirm with user — design system
   call.** Surfaced in 01g.
6. **YouTube channel timezone field.** Per the Mobile note + Step 11a, the
   YouTube Data API doesn't expose a channel-level `timeZone` field directly. We
   may need to derive from `country` + `defaultLanguage`, or just record what
   YouTube returns (often nothing). v1 records what's available; surface raw +
   derived in the channel show page. **Confirm with user.** Surfaced in 01a.
7. **Cross-tz diff dialog UX.** When a channel's tz differs from the user's,
   diff dialogs need to label which column is in which tz (e.g., "Pito (your tz:
   Europe/Bucharest)" vs "YouTube (channel tz: America/Los_Angeles)"). v1 labels
   both columns explicitly. **Confirm copy with user.** Surfaced in 01a.
8. **DST transition behavior for the digest scheduler.** Spring-forward skips an
   hour; fall-back repeats one. Suggestion: when DST jumps an hour forward
   across 09:00, fire the digest at the next hourly slot (would be 10:00
   user-local). When DST repeats an hour at 09:00, fire only once (track
   last-fired-at to prevent duplicates). Specs exhaustive in 01e. **Confirm
   policy with user.**
9. **TOTP 2FA gate on webhook URL changes.** Webhooks carry delivery surface to
   external services; replacing the URL is sensitive. v1 question: require 2FA
   confirmation on URL change (delete + replace), or treat as a normal Settings
   update? Suggestion: normal Settings update for now; revisit when 2FA ships.
   **Confirm with user.** Surfaced in 01b + 01c.

## Cross-stack scope

| Surface | In scope? | Notes                                                       |
| ------- | --------- | ----------------------------------------------------------- |
| Web     | yes       | All eight sub-specs ship through the Rails app.             |
| MCP     | partial   | 01a (user tz) needs an MCP tool to update `time_zone` for   |
|         |           | Mobile Claude. 01b / 01c webhook config is Settings-only    |
|         |           | (no MCP tool surface for v1). 01g viewer-time data is read- |
|         |           | only via a future `yt:analytics` tool (deferred to a later  |
|         |           | phase).                                                     |
| CLI     | partial   | `pito settings` reads / writes user tz (parity with Rails). |
|         |           | Webhook config and digest scheduler are server-side only;   |
|         |           | the CLI doesn't expose them. Viewer-time analytics rendered |
|         |           | as ASCII heatmap in `pito videos <id> analytics` (later).   |
| Website | no        | Marketing site untouched.                                   |

Cross-stack work that doesn't fit v1 (CLI analytics rendering, MCP analytics
tool surface) is carved out and tracked under "deferred follow-ups" inside 01g's
"Open questions" block.

## Dispatch sequencing

Per the Mobile note's 7-step suggestion, lightly reordered for parallelism:

1. **01a** — Timezone foundation. **Blocks 01b autosave UX (browser-detect
   wiring), 01d, 01e, 01f, 01g, 01h.** Ship first.
2. **01b** — Slack webhook pane. Parallel with 01c.
3. **01c** — Discord webhook pane. Parallel with 01b.
4. **01d** — Help-modal Markdown content. Parallel with 01b + 01c.
5. **01f** — Analytics architecture update (docs-only). Parallel with
   everything.
6. **01e** — Daily digest scheduler. Depends on 01a + 01b + 01c.
7. **01g** — Viewer-time analytics implementation. Depends on 01a + 01f.
8. **01h** — Video scheduled-publish tz wiring. Depends on 01a.

Master agent dispatches 01a → (01b ‖ 01c ‖ 01d ‖ 01f) → (01e ‖ 01g ‖ 01h).
Reviewer dispatch after each wave. Commit + push + CI watch per the user's
cadence rule.

## Quality gates (per phase, per `beta.md`)

1. Every checkbox above ticked.
2. `log.md` close-out entry summarizing the phase.
3. RSpec green at the new full count. Spec pyramid coverage per sub-spec.
4. Brakeman clean. bundler-audit clean.
5. `docs/design.md` updated if the heatmap component introduces new tokens.
6. `docs/architecture.md` updated by 01f (timezone rule + viewer-time
   aggregation section).
7. Manual test instructions in `log.md` per session.
8. User validation before commit, every time.
