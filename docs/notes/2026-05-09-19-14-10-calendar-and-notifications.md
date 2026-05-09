# Calendar and notifications

Tenant-scoped calendar that tracks publishing schedules, game releases (including pre-IGDB / future titles), and milestones — with daily-digest delivery to Discord / Slack and immediate in-app notifications. Defers email to a future "email-as-its-own-thing" effort.

All rules from `tenant-scope-and-idor` apply (every table has `tenant_id`, every query filters by it, etc.). This note focuses on the calendar and notification surface.

## Concept

A tenant has **one calendar**. Everything on it is a calendar entry with a type. Some entries are derived from existing tenant data (channel publish dates, video publish dates), some are user-created (game releases, milestones), some are computed (auto-tracked milestones from analytics).

Notifications fire from calendar entries and from analytics state changes. Delivery is per-tenant, multi-channel, with two modes: immediate (in-app) and daily digest (Discord / Slack webhooks).

## Calendar entry model

```
calendar_entry(
  id PK (uuid),
  tenant_id NOT NULL,
  entry_type,                   -- enum: see types below
  title,                        -- short display name
  description,                  -- nullable, free-form
  starts_at,                    -- timestamptz
  ends_at,                      -- nullable, timestamptz; null = point-in-time
  all_day boolean,              -- if true, ignore time portion in display
  timezone,                     -- IANA tz; defaults to tenant tz
  source,                       -- enum: 'manual' | 'derived' | 'auto'
  source_ref,                   -- nullable JSON; pointer back to source row(s) for derived/auto
  state,                        -- enum: 'scheduled' | 'occurred' | 'cancelled' | 'superseded'
  metadata jsonb,               -- type-specific fields (see per-type below)
  created_at, updated_at
)
```

`entry_type` values:

- `channel_published` — derived from `channel.created_at` for tenant channels
- `video_published` — derived from `video.publishedAt`
- `video_scheduled` — derived from `video.status.publishAt` while still in the future
- `game_release` — user-created (manual) or attached to an IGDB game
- `purchase_planned` — pre-purchase / pre-order / reservation linked to a game release (see below)
- `milestone_manual` — free-form user milestone
- `milestone_auto` — analytics-derived milestone (see auto-tracked rules below)
- `custom` — anything else the user types in

`source` values:

- `manual` — created by a user via UI / MCP tool
- `derived` — written by a sync job from canonical tables (channel / video / game). Re-syncs overwrite. Last-write-wins.
- `auto` — computed by the milestone evaluator from analytics tables

Derived and auto entries should not be hand-edited; the UI marks them read-only and any user-side changes are kept in `metadata.user_overrides` (e.g., a user-added note on an auto milestone) — those survive re-sync. Overwriting derived fields directly is not supported.

## Entry types in detail

### Channel / video publish entries (derived)

- One `channel_published` per tenant channel, keyed by `source_ref = {channel_id}`.
- One `video_published` per tenant video, keyed by `source_ref = {video_id}`.
- One `video_scheduled` per video where `status.privacyStatus = private` AND `status.publishAt` is set AND in the future. When the scheduled time passes, the entry is **superseded** (not deleted) and a `video_published` entry is written. This preserves the original schedule on the calendar history.

These are written by the daily YouTube sync (per the analytics note). On-demand sync also refreshes them.

### Game release (manual or IGDB-attached)

`metadata` shape:

```
{
  "game_id":            "<local game uuid, nullable>",   -- when attached to a tenant game
  "igdb_id":            "<int, nullable>",               -- when known
  "platforms":          ["PS5", "Switch"],               -- denormalized for display
  "release_precision":  "day" | "month" | "quarter" | "year" | "tba",
  "release_window":     "Q3 2026"                        -- when precision != "day"
}
```

A game release entry can exist **without an IGDB game** — that's the "pre-IGDB" case. The user types name, expected date (or quarter / year / "TBA"), platforms, optional notes. When IGDB later catalogs the game, the user attaches it and the entry's `metadata.game_id` and `metadata.igdb_id` populate; future re-syncs of that game can also update the date if IGDB's release date is more precise than the user's guess (with a "respect manual override" flag — see below).

`release_precision` matters for notifications: an entry with precision `quarter` or coarser doesn't fire T-7 / T-1 / T-0 reminders because there's no concrete day. It can fire a "still TBA" reminder periodically if the user wants; default off.

A `manual_date_override` boolean on the entry says "I set this date by hand, don't let IGDB sync overwrite it." Default false. When true, IGDB sync may update other fields (name, platforms) but never `starts_at`.

### Purchase planned (pre-purchase / reservation) — linked to a game release

This is a **separate entry** that **references** a game release entry, rather than a flag on the game release itself. Reasons:

1. Multiple purchases per game (e.g., physical Switch copy at GAME.es + digital PS5 pre-order on PSN — collector who buys twice). Each is its own calendar entry.
2. Purchase has its own date (when you placed the order), often different from release date.
3. Cancellable independently of the game.

```
calendar_entry where entry_type='purchase_planned', metadata =
{
  "game_release_entry_id":  "<uuid of the game_release entry>",
  "purchase_kind":          "preorder" | "reservation" | "purchased",
  "storefront":             "Steam" | "GOG" | "Epic" | "PSN" | "Nintendo eShop"
                          | "Xbox" | "Physical" | "Other",
  "storefront_name":        "GAME.es",   -- free text, esp. for Physical or Other
  "storefront_url":         "<url, optional>",
  "amount":                 "59.99",
  "currency":               "EUR",
  "ordered_at":             "<iso datetime, optional — when you placed the order>",
  "confirmation_ref":       "<order number, optional>"
}
```

Quick-pick storefronts in the UI: Steam, GOG, Epic, PSN, Nintendo eShop, Xbox, Physical, Other. Selecting one populates `storefront`. `storefront_name` is free-text and used for Physical / Other (where the actual store name is what you'd recognize, like "GAME.es"). For digital storefronts the `storefront_name` defaults to the same as `storefront` but can be overridden.

The presence of a `purchase_planned` entry linked to a game release **suppresses pre-release reminder notifications** for that release (because you're already sorted). If the user wants reminders anyway, a per-entry `notify_anyway` flag overrides this.

### Manual milestones

Free-form. User types a title, date, optional description. Examples: "100k subs party," "podcast appearance on X," "1-year channel anniversary." Just a calendar entry with `entry_type='milestone_manual'`, no special metadata.

### Auto-tracked milestones (declarative rules)

User defines a rule once; the system evaluates it against existing analytics data and writes a `milestone_auto` calendar entry the moment the threshold is crossed. Idempotent — the same threshold won't fire twice.

```
milestone_rule(
  id PK (uuid),
  tenant_id NOT NULL,
  name,                          -- "100 subs on main channel"
  scope_type,                    -- 'channel' | 'video' | 'tenant'
  scope_id,                      -- nullable for tenant scope; uuid for channel/video
  metric,                        -- e.g. 'subscriberCount', 'views', 'likes',
                                 --      'estimatedMinutesWatched', 'subscribersGained'
  metric_window,                 -- 'lifetime' | '7d' | '28d' | '90d'
  threshold numeric,
  direction,                     -- 'cross_up' | 'cross_down'
  fired_at timestamptz,          -- null until first crossing; idempotency key
  enabled boolean,
  created_at, updated_at
)
```

Evaluation runs after each analytics sync (daily nightly + on-demand). For each enabled rule:

1. Read the relevant metric from the appropriate table per metric_window:
   - `lifetime` → `video_window_summary` row with `window='lifetime'` (video scope), `channel_window_summary` row with `window='lifetime'` (channel/tenant scope)
   - `7d` / `28d` / `90d` → corresponding window rows
   - For real-time `subscriberCount` (a Data API stat, not Analytics): from `channel.statistics.subscriberCount` snapshot
2. If `direction='cross_up'` and current value ≥ threshold and `fired_at IS NULL` → write a calendar entry, set `fired_at = now()`.
3. If `direction='cross_down'` and current value ≤ threshold and `fired_at IS NULL` → same.

The calendar entry's `source_ref = {milestone_rule_id, metric_value_at_fire}`. `state` starts as `occurred` (it already happened by the time we wrote the row).

Disabling a rule (`enabled=false`) without clearing `fired_at` means it won't re-fire if later re-enabled. To re-arm: `fired_at = NULL`.

## Notifications

A **notification** is the user-facing alert generated from one or more calendar entries or rule firings.

```
notification(
  id PK (uuid),
  tenant_id NOT NULL,
  kind,                          -- enum: see notification kinds below
  subject_entry_id,              -- nullable, FK to calendar_entry
  subject_rule_id,               -- nullable, FK to milestone_rule
  payload jsonb,                 -- denormalized data for rendering
  severity,                      -- 'info' | 'success' | 'warn' | 'urgent'
  created_at,
  read_at                        -- nullable, for in-app inbox
)
```

`kind` values:

- `game_release_upcoming` — fired at T-30 / T-7 / T-1 / T-0 days for a game release entry without a linked `purchase_planned`. Configurable per-tenant which offsets are active. Default: T-7, T-1, T-0.
- `game_release_today` — fires at T-0 regardless of pre-purchase status (it's still useful to know the game is out today).
- `video_scheduled_publishing_soon` — T-1h before a `video_scheduled` flips public. Default off, opt-in.
- `video_published` — fires when a `video_scheduled` transitions to `video_published`. Default off; useful when sync detects a publish you didn't trigger from pito.
- `milestone_reached` — fires when a `milestone_rule` fires.
- `digest_summary` — synthetic notification representing the day's compiled digest (used internally by webhook delivery; not shown in in-app inbox).

Notifications are first-class rows so the in-app inbox, the digests, and the MCP tool all read from the same source.

## Delivery channels

```
delivery_channel(
  id PK (uuid),
  tenant_id NOT NULL,
  kind,                          -- 'in_app' | 'discord_webhook' | 'slack_webhook' | 'mcp_pull'
  name,                          -- "Discord — main server", "Slack — work"
  config jsonb,                  -- kind-specific (see below)
  enabled boolean,
  digest_enabled boolean,        -- if true, channel receives a daily digest
  digest_at_local_time,          -- e.g. "08:00" — interpreted in tenant timezone
  immediate_kinds text[],        -- list of notification kinds this channel receives immediately
  created_at, updated_at
)
```

`config` shape per kind:

- `in_app`: `{}` — nothing to configure
- `discord_webhook`: `{ "webhook_url": "<encrypted>" }`
- `slack_webhook`: `{ "webhook_url": "<encrypted>" }`
- `mcp_pull`: `{}` — channel is a marker; messages are read via MCP tool, not pushed

Webhook URLs are stored encrypted, in the per-tenant secrets table per Rule 7 of the IDOR spec. They never appear in API responses; the UI shows "configured / not configured" + a last-used timestamp.

A tenant can have multiple channels of the same kind (e.g., two Discord webhooks pointing at different servers). Each can subscribe to different notification kinds and have its own digest timing.

### Default per-channel routing

Sensible defaults when a tenant first sets up:

| Channel kind | Immediate kinds | Digest enabled |
|---|---|---|
| `in_app` | all kinds | no (the inbox itself is the surface) |
| `discord_webhook` | `urgent` severity only | yes |
| `slack_webhook` | `urgent` severity only | yes |
| `mcp_pull` | none | no — pulled on demand |

User-overridable. The intent: the inbox always has everything in real time, while webhooks stay quiet during the day and produce one curated message at the configured hour.

## Delivery rules

### In-app

Every notification creates a row. Read state is per-user (today, one user per tenant — extensible later via a `notification_read(notification_id, user_id, read_at)` join when needed).

### Webhook delivery — daily digest

A scheduler runs every minute looking for `delivery_channel` rows where:
- `enabled = true`
- `digest_enabled = true`
- current time in the tenant's timezone matches `digest_at_local_time` to the minute
- there are unsent notifications since the last digest run

It assembles a digest of all `notification` rows since the previous digest, formats them for the channel kind, posts to the webhook URL, records a `digest_sent` event with the notification IDs covered. Failures retry with exponential backoff up to 1 hour, then mark the channel as failing and surface in the in-app inbox.

### Webhook delivery — immediate

When a notification fires whose `kind` is in a channel's `immediate_kinds` list, post immediately to that channel. Same formatter, same retry policy.

### MCP pull

The MCP server exposes a `notifications_unread` tool that returns the same rows the in-app inbox sees. Reading via MCP marks notifications read in MCP context but does not mark them read in-app — they're separate read pointers (treat MCP reads as "viewed in MCP" not "viewed everywhere"). For v1, simplest: MCP returns unread, with a separate `notifications_mark_read` tool to optionally mark.

## Formatter

A formatter component renders a list of notifications into the right payload for a target. Same content, different output:

- **Discord (`discord_webhook`)**: one POST with `username: "pito"`, `avatar_url: <pito logo>`, a short `content` line ("📅 pito daily — 9 May 2026"), and 1-3 `embeds[]`. Embed structure: title, description (markdown links work as `[text](url)`), color (severity → color), fields for sub-items (e.g., per-game-release lines), timestamp footer. Up to 10 embeds per message; we'll cap at 5 for readability.
- **Slack (`slack_webhook`)**: one POST using `blocks[]`. Header block ("📅 pito daily — 9 May 2026"), section blocks per category (Game releases, Milestones, Upcoming this week), divider blocks between. Slack link syntax: `<https://example.com|text>`. Markdown subset: `*bold*`, `_italic_`, no `**bold**`.
- **MCP**: a list of plain-text or markdown notification objects.
- **In-app**: structured JSON, the UI renders.

Formatter is responsible for:
- Per-target link syntax (Discord markdown vs Slack `<url|text>`)
- Per-target emoji (Unicode in both; Slack `:emoji_name:` only if guaranteed present)
- Truncation rules (Discord: content 2000, embed description 4096; Slack: section text 3000)
- Grouping (game releases by date, milestones by channel, etc.)

### Suggested visual style

- **Brand**: `username: "pito"` and pito logo as `avatar_url` on Discord. Same idea on Slack via `username` + `icon_url` if the workspace allows overrides.
- **Severity colors** (Discord embed `color`, decimal int):
  - info → muted blue (`0x5865F2` ≈ 5793266)
  - success → green (`0x57F287` ≈ 5763719)
  - warn → amber (`0xFEE75C` ≈ 16705372)
  - urgent → red (`0xED4245` ≈ 15548997)
- **Emoji shortcuts** (Unicode, work everywhere):
  - 📅 calendar / digest header
  - 🎮 game release
  - 🛒 purchase / pre-order
  - 🏆 milestone reached
  - 📺 video published
  - ⚡ scheduled / time-sensitive
  - ⚠️ warn
  - 🚨 urgent
- **Links**: every game release links to its store URL if a `purchase_planned` entry has one, otherwise to the IGDB page (constructed from `igdb_slug` if present), otherwise no link. Every milestone links to the relevant pito view if we have URL routing for that.

## Game release reminder logic

For every `game_release` entry on the calendar, the scheduler also creates a notification at:

- T-30 days (default off)
- T-7 days (default on)
- T-1 day (default on)
- T-0 (release day, fires once at midnight tenant tz; default on)

Suppression: if any `purchase_planned` entry references this `game_release` entry and `notify_anyway = false`, skip T-7 and T-1 (the user is already sorted). T-0 still fires (game out today, useful regardless).

If `release_precision` is coarser than `day` (i.e., `month` / `quarter` / `year` / `tba`), no offset reminders fire — there's no exact date. Optional `tba_remind_monthly` per entry (default off): if true, the system fires an `info` reminder on the 1st of each month while the entry is still TBA.

User-tunable global defaults at the tenant level: which offsets are enabled, time-of-day for offset firings (default 09:00 tenant tz).

Emitted notifications carry `kind='game_release_upcoming'` and severity escalating from `info` (T-30) → `info` (T-7) → `warn` (T-1) → `success` (T-0). Severity controls default routing.

## Calendar views

Read-side queries we expect the UI / TUI to need. All inherently scoped by tenant via Rule 3.

- **Day view**: entries where `starts_at` falls on a given local date.
- **Week / month**: range queries on `starts_at`.
- **Upcoming game releases**: `entry_type='game_release' AND starts_at >= now() ORDER BY starts_at LIMIT N`.
- **Upcoming without purchase**: same, with `LEFT JOIN purchase_planned` where the join row is null (the "you should pre-order" list).
- **Recent milestones**: `entry_type IN ('milestone_manual','milestone_auto') AND starts_at BETWEEN now() - 30d AND now()`.
- **Stream of recently-reached milestones**: subset of above, `state='occurred'`.
- **Calendar export** (future): iCal feed per tenant. Out of scope for v1.

All of these are SQL queries against `calendar_entry` with the relevant `entry_type` filter and ordering.

## Sync / write paths

- **YouTube sync** writes `channel_published`, `video_published`, `video_scheduled`. Idempotent — re-running overwrites by `source_ref`.
- **IGDB sync** for a game writes / updates `game_release` entries when a game has a `first_release_date`. Respects `manual_date_override`.
- **User actions** (UI, MCP tools) write `manual` entries directly.
- **Milestone evaluator** runs after every analytics sync. Idempotent via `milestone_rule.fired_at`.
- **Reminder scheduler** runs every minute, generates `notification` rows for game releases hitting their offsets, and triggers digest assembly.

## MCP tools we'll expose

For the MCP-on-request surface mentioned earlier:

- `calendar_list(start, end, type?)` — list entries in a range
- `calendar_create(...)` — create a manual entry (game release, milestone, custom)
- `calendar_update(id, ...)` — update a manual entry; rejects updates to derived/auto entries
- `calendar_delete(id)` — same constraint
- `purchase_create(game_release_entry_id, ...)` — register a pre-purchase
- `notifications_unread()` — list unread notifications
- `notifications_mark_read(ids)` — mark read in MCP context
- `milestone_rule_create(...)` / `milestone_rule_list()` / `milestone_rule_disable(id)` — manage auto rules

All tool calls run through the tenant-scoped data layer (Rule 8 of the IDOR spec). The MCP session's tenant is authoritative; client-supplied `tenant_id` is ignored.

## Future hooks (not now)

- **Email delivery**: deferred. When implemented, it'll be its own design — packed daily/weekly summaries with richer content (top videos, retention trends, what to publish next), not a 1:1 notification mirror.
- **iCal export**: subscribe-to feed for external calendar apps.
- **Per-game subscription cost tracking**: extend `purchase_planned` with `subscription_renewal` for things like Game Pass.
- **Cross-channel digest grouping**: bundle multiple channels' published entries into one digest line ("3 videos published today across 2 channels").
- **More milestone metric sources**: comments per video, sentiment, retention thresholds (`audienceWatchRatio` floor).
- **Smarter game release sources**: scrape GOG / Steam upcoming pages for releases not in IGDB. Out of scope; user enters them manually for now.

## Tenancy and IDOR — explicit cross-references

Per `tenant-scope-and-idor`:

- `calendar_entry`, `milestone_rule`, `notification`, `delivery_channel` all have `tenant_id NOT NULL`.
- `delivery_channel.config.webhook_url` is encrypted at rest; reads scoped by tenant; never echoed in responses.
- A `purchase_planned` entry's `metadata.game_release_entry_id` must reference an entry in the same tenant (Rule 5: cross-resource tenancy check). Verified before insert.
- A `milestone_rule.scope_id` (when scope is channel or video) must reference a row in the same tenant. Verified before insert.
- Webhook delivery jobs run with explicit tenant context (Rule 8). Outbound HTTP calls to Discord / Slack are not security-sensitive cross-tenant-wise (the URL itself is the tenant's), but the assembly of the digest payload runs through tenant-scoped reads.
- IDOR test obligations (Rule 12) apply to every new endpoint and every MCP tool listed above.
