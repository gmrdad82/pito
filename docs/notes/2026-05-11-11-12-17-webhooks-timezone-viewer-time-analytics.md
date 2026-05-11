# Settings: Slack + Discord webhooks · User timezone · Viewer-time analytics

Three things bundled here because they touch each other (timezone is needed by
the digest scheduler and by analytics).

---

## 1. Slack + Discord webhook panes in Settings

Add two new panes to Settings:

- **Slack**
- **Discord**

Each pane contains:

- A single text input for the webhook URL.
- An `[update]` button (per pane — independent save).
- A `[help]` (or `[how to]`) link.
- Two checkboxes:
  - `[ ] everything` — send every notification event.
  - `[ ] daily digest` — single roll-up per day.
- Hint text under `daily digest`: "Sent daily at 09:00 in your timezone."

### Help / how-to modal

Clicking `[help]` opens a modal dialog rendering a Markdown guide. The guide is
written for a brand-new user who has never created a webhook before — every step
illustrated, no assumed knowledge. One guide per provider.

Slack guide must cover: create an app at api.slack.com/apps, enable Incoming
Webhooks, add to workspace, pick a channel, copy URL, paste into pito, hit
`[update]`.

Discord guide must cover: open the target server → channel settings →
Integrations → Webhooks → New Webhook → name + avatar (optional) → copy URL →
paste into pito → hit `[update]`.

Both guides should include a "test it" section — pito sends a test message on
`[update]` and the user should see it land.

### Behavior

- `[update]` validates the URL shape (Slack:
  `https://hooks.slack.com/services/...`, Discord:
  `https://discord.com/api/webhooks/...` or `discordapp.com`), sends a test
  ping, and stores the URL only if the ping succeeded.
- Checkboxes save independently (autosave or save on `[update]`, TBD — match how
  the rest of Settings works).
- `everything` and `daily digest` are not mutually exclusive — both can be on,
  neither can be on, etc.
- Per-provider state; you can have Slack on `everything` and Discord on
  `daily digest` only.

### Daily digest job

A scheduler runs hourly (or at minute 0 of every hour) and fires the digest for
any user whose local time has just crossed 09:00. Content: a summary of the last
24 hours of pito activity — diffs detected, imports completed, login attempts
(if security feature lands), etc. Format per provider (Slack blocks, Discord
embeds).

### Specs

- Webhook URL validation (good + bad inputs per provider).
- Test-ping success path saves; failure path does not save and surfaces the
  error.
- Checkbox state persists per provider.
- Help modal renders Markdown.
- Daily digest scheduler picks the right users at the right local 09:00.
- Webhook delivery retries on transient failure, gives up cleanly on permanent
  failure.

---

## 2. User timezone support (app-wide)

We have to add timezone support across pito. YouTube has its own (channel-level
setting), and the user might be in a different one entirely. For now, scope:

- Add a `time_zone` field to the User (or Settings) model.
- Tzdata-backed (IANA names: `Europe/Bucharest`, `America/Los_Angeles`, etc.).
- Settings UI: dropdown / typeahead to pick it. Default to the browser-detected
  zone on first load, but user can override.
- Everywhere we render a time or compare against "now," route through the user's
  zone.

### Where it has to apply right now

- **Daily digest** — 09:00 user-local (see §1).
- **Calendar reminders / events** — already user-facing, must respect the zone.
- **Scheduled video publish** — uses the user's zone for the publish-at picker,
  converts to UTC at storage. (YouTube's own tz handling is separate; we store
  UTC, render in user-tz.)
- **Login attempt log** — display in user-tz, store UTC.
- **Change history views** — display in user-tz, store UTC.
- **Notifications** — display in user-tz.

### Storage rule

Store UTC in the DB. Convert at render time. No exceptions.

### YouTube timezone

YouTube channels expose their own timezone. We record it on the channel (Phase
7.5 Step 11 already pulls channel meta — verify this field is captured). Surface
it on the channel show page next to the user's tz so the difference is obvious.
Anywhere we compare pito state ↔ YouTube state (diff dialogs, scheduled
publishes), be explicit about which tz we're rendering in.

### Specs

- Round-trip: pick a date in user-tz on a form → stored as UTC → re-rendered in
  user-tz unchanged.
- Daylight-saving transitions (spring-forward, fall-back) don't break scheduled
  jobs.
- Changing the user's tz updates all rendered times immediately.
- Cross-tz scenario: user in `Europe/Bucharest`, channel in
  `America/Los_Angeles` — diff dialog labels both sides clearly.
- Digest scheduler edge cases (user in `Pacific/Kiritimati` UTC+14, user in
  `Pacific/Pago_Pago` UTC-11, DST jurisdictions).

### Analytics implementation note (record this in the analytics architecture doc)

Anywhere analytics deals with relative time ("this week," "last 7 days," "today
vs yesterday") it must compute in the user's timezone, not server time and not
UTC. A "day" in the analytics layer is a user-local day. Same for week
boundaries (start-of-week is locale-dependent — default Monday, but make it
configurable later).

Bucket aggregation in storage may still be UTC for raw rows; the rollup layer
applies the tz offset. Document this clearly so we don't end up with
off-by-one-day bugs at month boundaries.

### Video management on scheduled date

When the user schedules a video for `2026-06-01 09:00`, that's user-local. The
job that triggers the publish must fire at the right UTC instant. Pre-publish
checklist and reminder windows ("publishing in 1 hour") are user-local.

---

## 3. Viewer-time analytics (best time to publish)

New analytics surface: **when are viewers actually watching?**

### What I want to see

- A chart showing viewership distribution across the day (hour-of-day) and
  across the week (day-of-week).
- Aggregated **per video** and **per channel**.
- All times rendered in the user's timezone (see §2).
- Goal: identify the best window to publish so a new upload lands when the
  audience is online.

### Suggested visualizations

- Heatmap: day-of-week × hour-of-day, intensity = view count or watch time.
- Line chart: average views per hour over a rolling window (7d / 28d / 90d).
- Highlight: "your peak window is Tuesday 18:00–21:00 in your timezone."

### Data source

YouTube Analytics API exposes hourly viewership (or close to it — verify exact
granularity available). Pull and store as time-bucketed rows.

### Per-video view

On a video's analytics tab, show the viewership distribution for that video
specifically — when did its viewers watch? Useful for "should I have published
this earlier in the week?"

### Per-channel view

On a channel's analytics tab, show the aggregate distribution across all the
channel's videos — the channel's audience pattern, not any single upload.

### Architecture note (record in analytics doc)

Add a section: **"Viewer-time aggregation"**. It must specify:

- Source endpoint and granularity.
- Storage schema (per-video hourly buckets in UTC, rolled up at query time to
  user-tz).
- Refresh cadence (daily? hourly? — TBD based on API quota).
- Query patterns for heatmap rendering.
- Cross-reference with §2: all rendering goes through user timezone.

---

## Dispatch instructions

Dispatch agents to work this **in parallel** where it makes sense:

1. **Timezone foundation** (User.time_zone, tz-aware helpers, render layer).
   Blocking for everything else — push first but parallelize the spec work.
2. **Webhook panes + per-provider validation + test ping** (Slack and Discord
   can run as two separate agents).
3. **Help-modal Markdown content** — drafted carefully for true beginners. Two
   separate guides, one per provider.
4. **Daily digest scheduler** — depends on §1 (timezone). Spec the cross-tz
   cases hard.
5. **Analytics architecture update** — record the timezone rule + the
   viewer-time aggregation design. This is documentation work, can run alongside
   §1.
6. **Viewer-time analytics implementation** — heatmap component, per-video tab,
   per-channel tab, data ingestion.
7. **Video scheduled-publish** — wire the existing scheduler through user-tz.

Specs and tests required at every layer:

- Webhook panes: unit + system specs.
- Timezone: extensive round-trip + DST + edge-zone coverage.
- Digest scheduler: time-travel specs around 09:00 boundaries in multiple zones.
- Viewer-time analytics: chart-rendering specs, data-rollup correctness,
  tz-aware bucketing.

Address any CI issues that come up. Push for **100% autonomously**.
