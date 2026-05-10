# Phase 16 §2 — Notification Formatter

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. Builds on
> §1's `Notification` model. Consumed by §1's
> `NotificationDeliveryChannel::Discord` / `Slack` and by §3's in-app + MCP
> tools.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 8.
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. §"Formatter" + §"Suggested visual style" sections are the source of
>   truth for severity-color mapping, emoji shortcuts, per-target link syntax,
>   truncation rules.
> - `docs/plans/beta/16-notifications/specs/01-notification-data-model-and-delivery.md`
>   — §1. `Notification#kind` enum + `event_payload` schema this spec renders
>   against.
> - `docs/design.md` — design system. Lowercase, monospace 13px, bracketed-link
>   convention. Notifications follow the same lowercase discipline in title +
>   body.
> - `CLAUDE.md` — `yes` / `no` for external booleans (the formatter emits
>   `"yes"` / `"no"` only when serializing for MCP / API boundaries; internal
>   Boolean storage stays Boolean).

## Goal

Translate a `Notification` row into a per-channel payload. Four output formats:

- **Discord** — JSON for the Discord webhook endpoint. Rich embeds (title +
  description + color + URL + footer) per Mobile note 5's recommendation. One
  embed per notification (the digest assembly note 5 calls out is collapsed in
  v1 to one-message-per-notification — see Open question #1).
- **Slack** — JSON for the Slack incoming-webhook endpoint. Block Kit blocks
  (header + section + context divider) per Mobile note 5's recommendation.
- **In-app** — structured hash the §3 ERB views render against. The hash carries
  the title / body / url / severity-class / formatted-timestamp.
- **MCP** — plain markdown string + structured metadata. Consumed by §3's
  `notifications_list` tool. Plaintext is renderable in any MCP-host UI without
  further translation.

Each output is per-event-type templated. `event_payload` (per §1's schema)
carries the denormalized data; the formatter never touches the canonical source
rows (Video / Channel / Game / CalendarEntry). The formatter is idempotent: same
`Notification` row → same output every time.

This is realignment work unit 8's formatter tier.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                                                                    |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Per-notification → per-message.** One `Notification` row produces one Discord message + one Slack message. NO digest aggregation in v1. The note 5 digest concept is deferred (see Open question #1). Reasoning: `all-users-see-all` + the install scale means immediate webhooks are fine. Digest is a follow-up.                                                                        |
| Q2  | **Discord shape — rich embeds.** Per note 5: `username: "pito"`, `avatar_url: <pito logo url>`, `content: <one-line emoji-prefixed summary>`, `embeds: [<one embed>]`. Embed: `title`, `description` (markdown links work), `color` (severity-mapped int), `url` (notification URL), `footer.text = "<event_type> · <fires_at iso>"`, `timestamp = fires_at iso8601`.                       |
| Q3  | **Slack shape — block kit.** Per note 5. Sections: header block (`type: header`, plain text `<emoji> <title>`), section block (`type: section`, `text.type: mrkdwn`, body with `<url\|text>` links), context block (`type: context`, elements: muted `event_type`, muted `fires_at`).                                                                                                       |
| Q4  | **Severity → Discord color (decimal int).** Per note 5:                                                                                                                                                                                                                                                                                                                                     |
|     | - `info` → `5793266` (`0x5865F2`, muted blue)                                                                                                                                                                                                                                                                                                                                               |
|     | - `success` → `5763719` (`0x57F287`, green)                                                                                                                                                                                                                                                                                                                                                 |
|     | - `warn` → `16705372` (`0xFEE75C`, amber)                                                                                                                                                                                                                                                                                                                                                   |
|     | - `urgent` → `15548997` (`0xED4245`, red)                                                                                                                                                                                                                                                                                                                                                   |
|     | The "no red" design rule applies to the in-app surface; Discord embed colors are NOT pito's design surface — they're Discord's, and red is the universal "urgent" signal there. Acceptable per note 5's explicit color map.                                                                                                                                                                 |
| Q5  | **Severity → Slack** (no color flood; Slack handles severity via emoji prefix only — note 5's recommendation). Block Kit `header` block carries the emoji per Q6 plus the title; no `color` field is set.                                                                                                                                                                                   |
| Q6  | **Emoji map** (Unicode, works in both Discord + Slack):                                                                                                                                                                                                                                                                                                                                     |
|     | - `video_published` → 📺                                                                                                                                                                                                                                                                                                                                                                    |
|     | - `video_pre_publish_check_missed` → ⚠️                                                                                                                                                                                                                                                                                                                                                     |
|     | - `game_release_upcoming` → 🎮                                                                                                                                                                                                                                                                                                                                                              |
|     | - `game_release_today` → 🎮                                                                                                                                                                                                                                                                                                                                                                 |
|     | - `milestone_reached` → 🏆                                                                                                                                                                                                                                                                                                                                                                  |
|     | - `calendar_entry_firing` → 📅                                                                                                                                                                                                                                                                                                                                                              |
|     | - `sync_error` → 🚨                                                                                                                                                                                                                                                                                                                                                                         |
|     | - `youtube_reauth_needed` → 🔐                                                                                                                                                                                                                                                                                                                                                              |
| Q7  | **Per-target link syntax.**                                                                                                                                                                                                                                                                                                                                                                 |
|     | - Discord: `[text](url)` markdown.                                                                                                                                                                                                                                                                                                                                                          |
|     | - Slack: `<url\|text>`.                                                                                                                                                                                                                                                                                                                                                                     |
|     | - In-app: HTML `<a href="">` rendered by §3.                                                                                                                                                                                                                                                                                                                                                |
|     | - MCP: `[text](url)` markdown.                                                                                                                                                                                                                                                                                                                                                              |
|     | The formatter exposes a `link(text, url, channel:)` helper.                                                                                                                                                                                                                                                                                                                                 |
| Q8  | **Truncation.** Per note 5 + the API docs:                                                                                                                                                                                                                                                                                                                                                  |
|     | - Discord embed `title`: 256 chars max.                                                                                                                                                                                                                                                                                                                                                     |
|     | - Discord embed `description`: 4096 chars max.                                                                                                                                                                                                                                                                                                                                              |
|     | - Discord top-level `content`: 2000 chars max.                                                                                                                                                                                                                                                                                                                                              |
|     | - Slack `header.text`: 150 chars max.                                                                                                                                                                                                                                                                                                                                                       |
|     | - Slack `section.text` (mrkdwn): 3000 chars max.                                                                                                                                                                                                                                                                                                                                            |
|     | The formatter truncates at the relevant boundary with a trailing `…` (single ellipsis char). NEVER mid-link-syntax — the formatter validates the truncated string is balanced (no half-open `[`).                                                                                                                                                                                           |
| Q9  | **Time format.** UTC ISO-8601 in the Discord embed footer + Slack context block (Discord renders the embed `timestamp` field locally for the viewer; Slack does not auto-localize, so we display UTC explicitly). The in-app render uses `time_ago_in_words` with a tooltip showing UTC ISO-8601. The MCP render uses UTC ISO-8601 inline.                                                  |
| Q10 | **Pito branding.** `username: "pito"` on Discord. `avatar_url` reads from credentials (`Rails.application.credentials.notifications.pito_avatar_url`, nullable). For Slack, `username` + `icon_url` are honored only when the Slack workspace allows webhook overrides (Slack returns a 200 either way; the formatter sets them and lets Slack decide).                                     |
| Q11 | **HTML escaping in webhook payloads.** Discord and Slack both interpret markdown / Block Kit text. The formatter MUST escape user-supplied content (notification `title` / `body`, video titles, channel names) before substituting into a markdown string. Helper: `escape_for(text, channel:)`. Per channel:                                                                              |
|     | - Discord: backslash-escape `*`, `_`, `~`, `` ` ``, `\|`, `>`, `<`, `[`, `]`, `(`, `)` per Discord's markdown.                                                                                                                                                                                                                                                                              |
|     | - Slack: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;` per Slack's `mrkdwn` escaping rules.                                                                                                                                                                                                                                                                                                     |
|     | - In-app: rely on Rails ERB auto-escape (no helper needed; the formatter returns raw text and §3's ERB escapes).                                                                                                                                                                                                                                                                            |
|     | - MCP: backslash-escape markdown special chars (same set as Discord).                                                                                                                                                                                                                                                                                                                       |
| Q12 | **Lowercase discipline.** Per `docs/design.md`: pito's surfaces are lowercase. The in-app + MCP outputs follow this. Discord + Slack outputs preserve case from the source (channel titles / video titles / game titles are user-authored — lowercase them would feel wrong). The formatter emits lowercase prefixes / suffixes (e.g., "video published:") and preserves user-content case. |
| Q13 | **`event_payload` is canonical.** The formatter NEVER reads from the source `Video` / `CalendarEntry` / `Channel` row. All rendering data is in `event_payload`. The §1 `NotificationPayloadBuilder` denormalizes the source row's fields into `event_payload` at insert time. The formatter is pure (input: `Notification` row; output: payload). Round-trip-safe across source-row edits. |
| Q14 | **Test posture.** Exhaustive per the brief.                                                                                                                                                                                                                                                                                                                                                 |

## Migration posture (LOCKED)

**No schema changes.** This spec is purely Ruby code (services + formatters).
All rendering data is read from §1's columns + `event_payload` jsonb.

If the implementation agent finds a missing column in `event_payload` that the
formatter needs but §1's `NotificationPayloadBuilder` does not currently
denormalize, STOP and surface — the additional key should be added in §1's
builder (light edit), not in §2.

## Files touched

### Services / formatters

- `app/services/notification_formatter.rb` (new) — namespace + shared helpers
  (`escape_for`, `link`, `truncate_for`, `emoji_for`, `severity_color`,
  `format_timestamp`).
- `app/services/notification_formatter/discord.rb` (new) — Discord payload
  builder. Single public method `payload_for(notification)` returning a hash
  ready to JSON-encode.
- `app/services/notification_formatter/slack.rb` (new) — Slack payload builder.
  Same shape.
- `app/services/notification_formatter/in_app.rb` (new) — structured hash for
  §3's ERB views. Returns
  `{title:, body_html:, url:, severity_class:, glyph:, fires_at_relative:, fires_at_iso:}`.
  The `body_html` is HTML-safe (per Q11; ERB does the auto-escape; Markdown
  links in `body` are converted to `<a>` via a small markdown → HTML stage owned
  by this formatter).
- `app/services/notification_formatter/mcp.rb` (new) — markdown + metadata for
  §3's MCP tools. Returns
  `{title:, body_md:, url:, severity:, kind:, fires_at_iso:}`.

### Per-event-type templates (PORO classes, one per kind)

The formatters call into per-kind template classes for the title + body + URL
strings. The shared classes live under
`app/services/notification_formatter/templates/`:

- `app/services/notification_formatter/templates/base.rb` (new) — abstract base
  with `title`, `body`, `url` methods + shared `payload` reader.
- `app/services/notification_formatter/templates/video_published.rb` (new).
- `app/services/notification_formatter/templates/video_pre_publish_check_missed.rb`
  (new).
- `app/services/notification_formatter/templates/game_release_upcoming.rb`
  (new).
- `app/services/notification_formatter/templates/game_release_today.rb` (new).
- `app/services/notification_formatter/templates/milestone_reached.rb` (new).
- `app/services/notification_formatter/templates/calendar_entry_firing.rb`
  (new).
- `app/services/notification_formatter/templates/sync_error.rb` (new).
- `app/services/notification_formatter/templates/youtube_reauth_needed.rb`
  (new).

`NotificationFormatter::Discord` / `Slack` / `InApp` / `Mcp` resolve the right
template class via a registry (`Templates::REGISTRY` — hash from `event_type`
string to template class).

### Out of scope (this spec)

- Rendering HTML in the in-app inbox views — §3.
- Routes / controllers — §3.
- MCP tool surfaces — §3.
- Webhook delivery (POST + retry) — §1.
- Email / push formatting — non-goals.
- Digest aggregation — Open question #1.
- TZ-aware rendering — defer (UTC ISO-8601 is the v1 contract).

## Per-event-type template specifications

Each template class implements three methods (`#title`, `#body`, `#url`). The
`title` is the short headline (used as Discord embed title and Slack header
text). The `body` is the longer description (Discord embed description, Slack
section text). The `url` is the canonical link.

The template constructor receives the `Notification` row; it reads from
`notification.event_payload` only. NEVER from the source row.

The "in-app" versions of `body` may include `[text](url)` markdown that the
InApp formatter converts to HTML.

### `video_published`

`event_payload` keys (per §1 Copy question #3): `video_id`, `video_title`,
`channel_id`, `channel_title`, `published_at`, `watch_url`.

- `title`: `"published: <video_title>"` (lowercase prefix; user-content case
  preserved).
- `body`:
  `"<channel_title> just published <video_title>. [watch on youtube](<watch_url>)."`
- `url`: `"/videos/<video_id>"` (in-app); Discord/Slack also embed the YouTube
  watch URL inline.

### `video_pre_publish_check_missed`

`event_payload` keys: `video_id`, `video_title`, `missing_checks` (array of
`"game"` / `"age"` / `"paid_promotion"` / `"end_screen"`).

- `title`: `"missed pre-publish check: <video_title>"`.
- `body`:
  `"<video_title> went public without ticking: <missing checks joined>. [review](/videos/<video_id>/edit)."`
- `url`: `"/videos/<video_id>/edit"`.

### `game_release_upcoming`

`event_payload` keys: `game_id`, `game_title`, `release_date` (iso8601),
`days_until` (int), `igdb_url` (string, nullable), `platforms` (array of
strings, nullable).

- `title`: `"<game_title> releases in <days_until> day(s)"`. (The formatter
  pluralizes `day` / `days` correctly.)
- `body`:
  `"<game_title> launches on <release_date_human> on <platforms_joined>. [igdb](<igdb_url>)"`
  (the IGDB link omitted when `igdb_url` is nil).
- `url`: `"/games/<game_id>"`.

### `game_release_today`

`event_payload` keys: same as `game_release_upcoming`.

- `title`: `"<game_title> releases today"`.
- `body`:
  `"<game_title> is out today on <platforms_joined>. [igdb](<igdb_url>)"` (IGDB
  link omitted when nil).
- `url`: `"/games/<game_id>"`.

### `milestone_reached`

`event_payload` keys: `rule_id`, `rule_name`, `metric`, `threshold`,
`metric_value_at_fire`, `scope_type` (`"install"` / `"channel"` / `"video"`),
`scope_id` (nullable for install scope).

- `title`: `"milestone: <rule_name>"`.
- `body`:
  `"<metric> crossed <threshold> at <metric_value_at_fire> on <scope_label>."`
  Where `scope_label` is `"this install"` for `install` scope, or the
  channel/video title resolved by the formatter (the §1 builder denormalizes
  `scope_label` into `event_payload` at insert time so the formatter never looks
  up).
- `url`: `"/calendar/entries/<source_calendar_entry_id>"` (the `milestone_auto`
  calendar entry; from §1's `notification.source_calendar_entry_id`).

### `calendar_entry_firing`

`event_payload` keys: `entry_id`, `entry_type`, `title` (the calendar entry's
title), `description`, `starts_at` (iso8601).

- `title`: `"<calendar entry title>"` (the calendar entry's own title is used
  directly).
- `body`: `"<description>"` if non-blank, else `"calendar entry fired."`
- `url`: `"/calendar/entries/<entry_id>"`.

### `sync_error`

`event_payload` keys: `job_class`, `error_class`, `error_message`.

- `title`: `"sync error: <job_class>"`.
- `body`: `"<error_class>: <error_message>"`. Truncated to fit per Q8.
- `url`: `"/notifications/<id>"` (the in-app inbox detail) — per §1 Copy
  question #5; user picks final.

### `youtube_reauth_needed`

`event_payload` keys: `connection_id`, `connection_email`.

- `title`: `"youtube re-auth needed: <connection_email>"`.
- `body`:
  `"the youtube oauth grant for <connection_email> expired or was revoked. [re-authorize](/oauth/youtube/start)."`
- `url`: `"/oauth/youtube/start"`.

## Discord payload shape

```ruby
{
  username: "pito",
  avatar_url: AVATAR_URL_OR_NIL,
  content: "<emoji> <title-truncated-to-2000>",
  embeds: [
    {
      title: "<title-truncated-to-256>",
      description: "<body-truncated-to-4096>",
      color: SEVERITY_COLOR_INT,
      url: "<absolute_url_or_nil>",
      footer: { text: "<event_type> · <fires_at_iso>" },
      timestamp: "<fires_at_iso>"
    }
  ]
}
```

`absolute_url` is computed by prepending the install host
(`Rails.application.config.app_host` or equivalent) to a leading-slash path. If
the path is already absolute (http(s)), used as-is. The host defaults to
`https://app.pitomd.com` per the project's existing infrastructure (verify
against `config/environments/production.rb` during impl).

`AVATAR_URL_OR_NIL` reads from
`Rails.application.credentials.notifications&.pito_avatar_url`. When absent, the
`avatar_url` key is omitted from the JSON.

## Slack payload shape

```ruby
{
  username: "pito",
  icon_url: AVATAR_URL_OR_NIL,
  blocks: [
    {
      type: "header",
      text: {
        type: "plain_text",
        text: "<emoji> <title-truncated-to-150>",
        emoji: true
      }
    },
    {
      type: "section",
      text: {
        type: "mrkdwn",
        text: "<body-truncated-to-3000-with-slack-link-syntax>"
      }
    },
    {
      type: "context",
      elements: [
        {
          type: "mrkdwn",
          text: "<event_type> · <fires_at_iso>"
        }
      ]
    }
  ]
}
```

If the notification has a non-blank `url`, the section block's body appends
`\n\n<absolute_url|view in pito>`. Per Q7, Slack's `<url|text>` syntax.

## In-app payload shape

```ruby
{
  title:               "<lowercase title text>",
  body_html:           "<html-safe rendered body with <a> tags>",
  url:                 "<leading-slash path or absolute url, nullable>",
  severity:            "info" | "success" | "warn" | "urgent",
  severity_class:      "notification-info" | "...-success" | etc.,
  glyph:               "<one-character glyph per Q6 emoji map>",
  kind:                "<event_type>",
  fires_at_relative:   "5 minutes ago",
  fires_at_iso:        "2026-05-10T12:00:00Z",
  read:                true | false   # mirror of in_app_read_at presence
}
```

The `body_html` conversion: the template's `body` returns a string that may
contain `[text](url)` markdown links. The InApp formatter runs a small markdown
→ HTML stage (own implementation, NOT a third- party Markdown lib — keep the
dependency surface tight) that converts exactly two markdown features:

1. `[text](url)` → `<a href="<url>"><text></a>`.
2. Newlines preserved as-is (rendered via CSS `white-space: pre-line` in §3).

All other Markdown is passed through as text (no bold / italic / code-block
support in v1). Output is HTML-safe via Rails' `sanitize` helper (allowing only
`a` with `href` attribute).

## MCP payload shape

```ruby
{
  id:           "<uuid>",
  title:        "<title text>",
  body_md:      "<markdown body with [text](url) links>",
  url:          "<absolute or leading-slash path, nullable>",
  severity:     "info" | "success" | "warn" | "urgent",
  kind:         "<event_type>",
  fires_at_iso: "<iso8601 utc>",
  read:         "yes" | "no"          # per CLAUDE.md boundary rule
}
```

`read` is a string `"yes"` / `"no"` per the Q13 boundary rule. `id` is the
notification's UUID (string).

## Acceptance

The reviewer agent (or the user via the manual playbook) verifies each:

### Formatter dispatch

- [ ] `NotificationFormatter::Discord.payload_for(n)` returns a hash with
      `username` / `embeds` / `content`.
- [ ] `NotificationFormatter::Slack.payload_for(n)` returns a hash with
      `username` / `blocks`.
- [ ] `NotificationFormatter::InApp.payload_for(n)` returns a hash with `title`
      / `body_html` / `url` / `severity_class` / `glyph` / `kind` /
      `fires_at_relative` / `fires_at_iso` / `read`.
- [ ] `NotificationFormatter::Mcp.payload_for(n)` returns a hash with `id` /
      `title` / `body_md` / `url` / `severity` / `kind` / `fires_at_iso` /
      `read` (the `read` value is the string `"yes"` / `"no"`, NOT a Boolean).

### Per-event-type templates

For each of the eight `kind` enum values:

- [ ] A `Templates::<KindName>` class exists.
- [ ] `#title` / `#body` / `#url` are implemented.
- [ ] `#title` is non-empty.
- [ ] `#body` is a string (may be empty).
- [ ] `#url` is a string (may be nil for system-only events).
- [ ] The class reads ONLY from `notification.event_payload` (verified by
      stubbing the source row to nil; templates still work).
- [ ] `Templates::REGISTRY[event_type]` resolves the right class.
- [ ] An unknown `event_type` raises a clear error (NOT a generic
      `NoMethodError`).

### Helpers

- [ ] `severity_color(:info)` / `:success` / `:warn` / `:urgent` return the
      integers in Q4.
- [ ] `emoji_for(:video_published)` etc. returns the Q6 emoji.
- [ ] `link("watch", "https://...", channel: :discord)` returns
      `[watch](https://...)`.
- [ ] `link(..., channel: :slack)` returns `<https://...|watch>`.
- [ ] `link(..., channel: :mcp)` returns `[watch](https://...)`.
- [ ] `link(..., channel: :in_app)` returns the same input (in_app's consumer is
      ERB; the markdown → HTML stage handles it later).
- [ ] `escape_for("a *bold* string", channel: :discord)` returns
      `"a \\*bold\\* string"`.
- [ ] `escape_for("a < b & c", channel: :slack)` returns `"a &lt; b &amp; c"`.
- [ ] `truncate_for("...", limit: N)` truncates with `…` and never breaks
      mid-link (the helper rolls back to the prior closing `)` if a `[` is
      opened without a matching `)` within the limit).
- [ ] `format_timestamp(time, :iso)` returns ISO-8601 UTC.
- [ ] `format_timestamp(time, :relative)` returns `time_ago_in_words(time)`
      style.

### Discord shape

- [ ] `payload[:username] == "pito"`.
- [ ] `payload[:avatar_url]` is set when credentials carry a non-nil
      `pito_avatar_url`; absent (key omitted) otherwise.
- [ ] `payload[:content]` is `<emoji> <title>` truncated to 2000 chars.
- [ ] `payload[:embeds]` is exactly one embed.
- [ ] `embed[:title]` is truncated to 256 chars.
- [ ] `embed[:description]` is truncated to 4096 chars.
- [ ] `embed[:color]` is the right severity int.
- [ ] `embed[:url]` is the absolute URL (or nil).
- [ ] `embed[:footer][:text]` is `<event_type> · <iso>`.
- [ ] `embed[:timestamp]` is the `fires_at` ISO-8601.

### Slack shape

- [ ] `payload[:username] == "pito"`.
- [ ] `payload[:icon_url]` set / omitted per credentials.
- [ ] `payload[:blocks]` has exactly three blocks (header, section, context).
- [ ] Header `text.text` is `<emoji> <title>` truncated to 150.
- [ ] Section `text.type == "mrkdwn"`.
- [ ] Section text is truncated to 3000.
- [ ] If `url` present, section text ends with `\n\n<url|view in pito>`.
- [ ] Context block carries `<event_type> · <iso>`.

### In-app shape

- [ ] `body_html` is HTML-safe.
- [ ] `body_html` converts `[text](url)` to `<a href="url">text</a>`.
- [ ] `body_html` does NOT pass through `<script>` injected via the
      `event_payload` (sanitize stage strips).
- [ ] `severity_class` matches `notification-info` / etc.
- [ ] `glyph` is the Q6 emoji.
- [ ] `read` is a Boolean (in-app is internal — not boundary).
- [ ] `fires_at_relative` is non-empty for any non-nil fires_at.

### MCP shape

- [ ] `read` is `"yes"` / `"no"` (string, per Q13 boundary).
- [ ] `id` is the UUID string.
- [ ] All other keys per the schema in §"MCP payload shape".

### Truncation

- [ ] Discord: a notification with a 5000-char body produces an embed
      description ≤ 4096 chars (with trailing `…`).
- [ ] Discord: a notification with a 300-char title produces an embed title of
      256 chars (with trailing `…`).
- [ ] Slack: a notification with a 5000-char body produces a section text ≤ 3000
      chars.
- [ ] Slack: a notification with a 200-char title produces a header text of 150
      chars.
- [ ] Truncation never leaves a half-open `[` (the helper rolls back).
- [ ] Truncation appends `…` (single Unicode char, not three dots).

### Escaping

- [ ] **Discord**: a notification with
      `event_payload[:video_title] =     "video *bold*"` produces an embed
      description containing `video \*bold\*`.
- [ ] **Slack**: same input produces section text containing `video *bold*` raw
      (Slack's mrkdwn handles `*` as bold; we don't double-escape).
- [ ] **Slack**: a notification with `<` and `>` in the body produces `&lt;` and
      `&gt;` in the section text.
- [ ] **In-app**: `<script>` in the body is sanitized away.
- [ ] **MCP**: backslash-escapes the same set as Discord.

### Localization-safe

- [ ] Unicode in titles / bodies (emoji, RTL marks, ZWJ): preserved verbatim
      through every formatter; no encoding errors.

## Test sweep

The implementation agent owns the full sweep. Each spec name below MUST end up
in the repo on green.

- `spec/services/notification_formatter_spec.rb` (new) — shared helpers
  (`escape_for`, `link`, `truncate_for`, `emoji_for`, `severity_color`,
  `format_timestamp`).
- `spec/services/notification_formatter/discord_spec.rb` (new) — Discord shape +
  per-kind smoke.
- `spec/services/notification_formatter/slack_spec.rb` (new) — Slack shape +
  per-kind smoke.
- `spec/services/notification_formatter/in_app_spec.rb` (new).
- `spec/services/notification_formatter/mcp_spec.rb` (new).
- `spec/services/notification_formatter/templates/base_spec.rb` (new).
- `spec/services/notification_formatter/templates/video_published_spec.rb`
  (new).
- `spec/services/notification_formatter/templates/video_pre_publish_check_missed_spec.rb`
  (new).
- `spec/services/notification_formatter/templates/game_release_upcoming_spec.rb`
  (new).
- `spec/services/notification_formatter/templates/game_release_today_spec.rb`
  (new).
- `spec/services/notification_formatter/templates/milestone_reached_spec.rb`
  (new).
- `spec/services/notification_formatter/templates/calendar_entry_firing_spec.rb`
  (new).
- `spec/services/notification_formatter/templates/sync_error_spec.rb` (new).
- `spec/services/notification_formatter/templates/youtube_reauth_needed_spec.rb`
  (new).

### Required test cases (exhaustive — implementation agent enumerates each)

#### `spec/services/notification_formatter_spec.rb` (helpers)

- [ ] `severity_color(:info)` returns 5793266.
- [ ] `severity_color(:success)` returns 5763719.
- [ ] `severity_color(:warn)` returns 16705372.
- [ ] `severity_color(:urgent)` returns 15548997.
- [ ] `severity_color("info")` works (string accepted).
- [ ] `severity_color(:unknown)` raises.
- [ ] `emoji_for("video_published")` returns 📺.
- [ ] `emoji_for("video_pre_publish_check_missed")` returns ⚠️.
- [ ] `emoji_for("game_release_upcoming")` returns 🎮.
- [ ] `emoji_for("game_release_today")` returns 🎮.
- [ ] `emoji_for("milestone_reached")` returns 🏆.
- [ ] `emoji_for("calendar_entry_firing")` returns 📅.
- [ ] `emoji_for("sync_error")` returns 🚨.
- [ ] `emoji_for("youtube_reauth_needed")` returns 🔐.
- [ ] `emoji_for("unknown")` returns a stable fallback (e.g., `•`).
- [ ] `link("watch", "https://example.com", channel: :discord)` ==
      `"[watch](https://example.com)"`.
- [ ] `link(..., channel: :slack)` == `"<https://example.com|watch>"`.
- [ ] `link(..., channel: :mcp)` == `"[watch](https://example.com)"`.
- [ ] `link(..., channel: :in_app)` returns the markdown form (the ERB stage
      will convert).
- [ ] `link(..., channel: :unknown)` raises.
- [ ] `escape_for("a *b* c", channel: :discord)` == `"a \\*b\\* c"`.
- [ ] `escape_for("a _b_ c", channel: :discord)` escapes the underscores.
- [ ] `escape_for("a [b](c)", channel: :discord)` escapes brackets + parens.
- [ ] `escape_for("a > b", channel: :discord)` escapes the `>`.
- [ ] `escape_for("a < b & c", channel: :slack)` == `"a &lt; b &amp; c"`.
- [ ] `escape_for(text, channel: :mcp)` mirrors the Discord set.
- [ ] `escape_for(nil, channel: :discord)` returns empty string.
- [ ] `truncate_for("hello world", limit: 5)` returns `"hell…"`.
- [ ] `truncate_for("hello", limit: 100)` returns `"hello"` (no truncation).
- [ ] `truncate_for("[click here](https://x)", limit: 5)`: never leaves a
      half-open bracket (test asserts the result has balanced `[` and `]`).
- [ ] `truncate_for("a" * 5000, limit: 4096)` returns 4096 chars including the
      `…`.
- [ ] `format_timestamp(time, :iso)` returns ISO-8601 with `Z` suffix.
- [ ] `format_timestamp(time, :relative)` returns `"5 minutes ago"`-style.

#### `spec/services/notification_formatter/discord_spec.rb`

For each `kind`, build a notification with valid `event_payload` and assert:

- [ ] `payload_for(n)` returns a hash with `:username`, `:content`, `:embeds`
      keys.
- [ ] `payload[:username]` is `"pito"`.
- [ ] `payload[:embeds]` is exactly one element.
- [ ] `embed[:title]` matches the template's `title`.
- [ ] `embed[:description]` matches the template's `body`.
- [ ] `embed[:color]` matches the severity color.
- [ ] `embed[:url]` is the absolute URL.
- [ ] `embed[:footer][:text]` carries `event_type` + ISO timestamp.
- [ ] `embed[:timestamp]` is the ISO timestamp.

Edge cases:

- [ ] **Avatar URL not configured**: `payload` does NOT carry the `avatar_url`
      key.
- [ ] **Avatar URL configured**: `payload[:avatar_url]` is the configured URL.
- [ ] **Severity warn**: color is amber.
- [ ] **Severity urgent**: color is red.
- [ ] **Title 300 chars**: truncated to 256.
- [ ] **Body 5000 chars**: truncated to 4096.
- [ ] **Markdown asterisks in `event_payload[:video_title]`**: escaped in the
      embed.
- [ ] **Nil `url`**: `embed[:url]` is nil; payload still valid.

#### `spec/services/notification_formatter/slack_spec.rb`

Mirror the Discord matrix:

- [ ] `payload_for(n)` returns a hash with `:username`, `:icon_url`, `:blocks`
      keys.
- [ ] `payload[:blocks]` is three elements.
- [ ] Header block: `type: "header"`; text is `<emoji> <title>` truncated
      to 150.
- [ ] Section block: `type: "section"`; text type is `mrkdwn`.
- [ ] Section text is truncated to 3000.
- [ ] Section text ends with `<url|view in pito>` when the notification has a
      URL.
- [ ] Section text omits the trailing link when URL is nil.
- [ ] Context block: type `context`; elements carry the event-type + timestamp
      line.
- [ ] Slack `<` and `>` in body are HTML-encoded.
- [ ] Slack `&` in body is HTML-encoded.

#### `spec/services/notification_formatter/in_app_spec.rb`

- [ ] Returns the documented hash shape.
- [ ] `body_html` is HTML-safe.
- [ ] `body_html` converts `[text](url)` markdown to `<a href>` with proper
      escaping.
- [ ] `body_html` strips `<script>` tags.
- [ ] `severity_class` is `notification-<severity>`.
- [ ] `glyph` matches the Q6 emoji.
- [ ] `read` is a Boolean (NOT a string — in-app is internal).
- [ ] `kind` is the notification's `kind` string.
- [ ] `fires_at_relative` is a non-empty string.
- [ ] `fires_at_iso` is ISO-8601 UTC.

#### `spec/services/notification_formatter/mcp_spec.rb`

- [ ] Returns the documented hash shape.
- [ ] `id` is the notification's UUID (string).
- [ ] `read` is `"yes"` for read rows, `"no"` for unread.
- [ ] `body_md` carries `[text](url)` markdown links.
- [ ] `severity` is the string severity name.
- [ ] `kind` is the event_type string.
- [ ] `fires_at_iso` is ISO-8601 UTC.
- [ ] All keys present; no extras.

#### Template specs (per kind)

For each of the eight templates:

- [ ] **Construction**: `Templates::<Kind>.new(notification)` reads
      `notification.event_payload` only.
- [ ] **`#title`**: produces the documented string for valid payload.
- [ ] **`#body`**: produces the documented string for valid payload.
- [ ] **`#url`**: produces the documented path for valid payload.
- [ ] **Missing required key in `event_payload`**: graceful (template returns a
      "data unavailable" placeholder rather than crashing — the formatter must
      never raise on a malformed row, since the row is already inserted in the
      DB; the user-visible degradation is acceptable).
- [ ] **Empty / nil values in `event_payload`**: graceful.
- [ ] **Unicode in `event_payload`**: preserved.

Specific template assertions:

- [ ] **`video_published`**: `title` includes `"published:"`; `body` mentions
      the channel + the video; `url` is `/videos/<id>`.
- [ ] **`video_pre_publish_check_missed`**: `body` lists the `missing_checks`;
      `url` is `/videos/<id>/edit`.
- [ ] **`game_release_upcoming` with `days_until=7`**: `title` is
      `"<game> releases in 7 days"`.
- [ ] **`game_release_upcoming` with `days_until=1`**: `title` is
      `"<game> releases in 1 day"` (singular).
- [ ] **`game_release_today`**: `title` is `"<game> releases today"`.
- [ ] **`game_release_*` with nil `igdb_url`**: body omits the IGDB link.
- [ ] **`milestone_reached` with `scope_type: "install"`**: body mentions "this
      install".
- [ ] **`milestone_reached` with `scope_type: "channel"`**: body mentions the
      channel name (resolved from `event_payload[:scope_label]` that §1's
      builder denormalized).
- [ ] **`calendar_entry_firing` with blank `description`**: body falls back to
      `"calendar entry fired."`.
- [ ] **`sync_error`**: title carries the job class; body carries class +
      message.
- [ ] **`youtube_reauth_needed`**: body links to `/oauth/youtube/start`.

#### Cross-channel consistency

- [ ] **Same notification → all four formatters**: each succeeds; the `title`
      text matches across (modulo per-channel emoji prefix); the URL resolves to
      the same path.
- [ ] **Truncation independence**: the Discord truncation does not mutate the
      `Notification` row; running the formatter twice produces the same output.

#### Flaw tests

- [ ] **Smuggle a Discord webhook URL into `event_payload[:url]`**: the
      formatter renders the URL but does NOT alter the delivery target (the
      delivery target is always the credentials URL — §1 enforces).
- [ ] **Smuggle a Slack `<webhook|spoof>` into `event_payload[:body]`**: escaped
      as text via the Slack escape helper; not interpreted as a link.
- [ ] **Smuggle `<script>` into `event_payload[:title]`**: Discord/Slack/MCP
      escape via channel-appropriate rules; in-app sanitizes.
- [ ] **`event_payload` empty `{}`**: every template handles gracefully; no
      `KeyError` raised.
- [ ] **`event_payload` carries unexpected keys**: ignored; no error.
- [ ] **Concurrent renders of the same notification**: idempotent; same output.

## Manual playbook (post-implementation)

1. Run the migration from §1 if not already applied; ensure a few `Notification`
   rows exist (manual `bin/rails console` inserts).
2. **Discord shape smoke.**
   ```ruby
   bin/rails runner "n = Notification.first; puts NotificationFormatter::Discord.payload_for(n).to_json"
   ```
   Confirm the JSON matches the documented shape.
3. **Slack shape smoke.** Same with `Slack`.
4. **In-app smoke.** Same with `InApp`. Confirm `body_html` is HTML-safe and
   converts markdown links.
5. **MCP smoke.** Same with `Mcp`. Confirm `read` is the string `"yes"` /
   `"no"`.
6. **Truncation smoke.** Insert a `Notification` with a 5000-char body. Run
   `Discord.payload_for(n)`; confirm the embed description is ≤ 4096 chars and
   ends with `…`.
7. **Escaping smoke.** Insert a `Notification` with
   `event_payload[:video_title] = "*bold*"`. Confirm the Discord embed
   description carries `\\*bold\\*` (escaped).
8. **End-to-end smoke (combines §1).** Trigger a notification creation; the
   Sidekiq `NotificationDeliver` job calls into the formatter; the resulting
   Discord / Slack messages render correctly in real channels.
9. **Run RSpec.**
   ```bash
   bundle exec rspec spec/services/notification_formatter*
   ```
   Confirm green.
10. **Run rubocop.** Confirm clean.

## Cross-stack scope

| Surface           | Status                                                                                              |
| ----------------- | --------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane. Service code only — no controllers / views.                             |
| MCP rack app      | **Skipped (this spec).** §3 ships the MCP tools; this spec ships the formatter the tools call into. |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10.                                                              |
| Astro / website   | **Skipped.** N/A.                                                                                   |

## Copy questions to escalate (master agent asks user before dispatch)

1. **Per-kind title templates.** The §"Per-event-type template specifications"
   section locks the architect's recommendations. User reviews each title string
   and confirms or adjusts:
   - `video_published`: `"published: <video_title>"`
   - `video_pre_publish_check_missed`:
     `"missed pre-publish check: <video_title>"`
   - `game_release_upcoming`: `"<game_title> releases in <N> day(s)"`
   - `game_release_today`: `"<game_title> releases today"`
   - `milestone_reached`: `"milestone: <rule_name>"`
   - `calendar_entry_firing`: `"<calendar entry title>"` (uses the entry's own
     title verbatim)
   - `sync_error`: `"sync error: <job_class>"`
   - `youtube_reauth_needed`: `"youtube re-auth needed: <email>"`
2. **Per-kind body templates.** Same as above for body strings.
3. **Empty-body fallback** for `calendar_entry_firing`. Suggested:
   `"calendar entry fired."`. User confirms.
4. **"View in pito" link label** appended to Slack messages. Suggested:
   `"view in pito"`. User confirms or picks alternative (e.g., `"open"`).
5. **`pito` username on Discord/Slack.** Suggested: `"pito"`. User confirms.
6. **Avatar URL credentials key.** Architect picks
   `Rails.application.credentials.notifications.pito_avatar_url`. User confirms
   or picks alternative.
7. **Severity → emoji rules**. Q6 locks the per-event-type emoji. User reviews
   and confirms.
8. **Truncation marker.** Architect picks `…` (Unicode ellipsis, single char).
   User confirms or picks `...` (three dots).

## Open questions (architect cannot decide; master agent surfaces to user)

1. **Digest aggregation.** Note 5 describes a daily digest
   (`digest_at_local_time` per delivery channel) where N events collapse into
   one webhook message. v1 ships per-event delivery (one event = one message).
   User confirms or expands to digest.
2. **Severity color override for in-app.** The "no red except destructive"
   design rule means the in-app `severity_class` for `urgent` should NOT be red.
   Architect's lean: use the existing `--color-warn` token (amber) for in-app
   `urgent`; reserve `--color-error` (red) for genuine destructive actions only.
   User confirms.
3. **Discord avatar.** Defer to implementation. The credentials key is reserved;
   the actual image asset is a follow-up.
4. **Markdown subset for in-app.** Architect ships `[text](url)` only. User
   confirms or expands (e.g., bold / code).
5. **Localization / TZ rendering.** Architect ships UTC ISO-8601 for v1. User
   confirms or asks for install-tz rendering.
6. **Per-event-type Discord embed `image` / `thumbnail`** (e.g., video thumbnail
   for `video_published`). Architect's lean: NO for v1; add later if visual
   demand justifies.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions

1. **Per-kind title templates** → Architect's drafts verbatim:
   - `video_published`: `published: <video_title>`
   - `video_pre_publish_check_missed`: `missed pre-publish check: <video_title>`
   - `game_release_upcoming`: `<game_title> releases in <N> day(s)`
   - `game_release_today`: `<game_title> releases today`
   - `milestone_reached`: `milestone: <rule_name>`
   - `calendar_entry_firing`: `<calendar entry title>` (use the entry title
     verbatim)
   - `sync_error`: `sync error: <job_class>`
   - `youtube_reauth_needed`: `youtube re-auth needed: <email>`
2. **Per-kind body templates** → Architect's drafts verbatim (per the
   "Per-event-type template specifications" section of the spec).
3. **Empty-body fallback for `calendar_entry_firing`** → `calendar entry fired.`
4. **Slack "view in pito" link label** → `view in pito`.
5. **`pito` username on Discord/Slack** → `pito` (lowercase).
6. **Avatar URL credentials key** →
   `Rails.application.credentials.notifications.pito_avatar_url`.
7. **Severity → emoji rules** → Architect's Q6 locks verbatim.
8. **Truncation marker** → `…` (single Unicode ellipsis character).

### Open-question decisions

1. **Digest aggregation** → Defer. Per-event delivery in v1.
2. **Severity color override for in-app `urgent`** → Use existing `--color-warn`
   token (amber). Reserve `--color-error` (red) for genuinely destructive
   actions only. Per CLAUDE.md hard rule on red usage.
3. **Discord avatar** → Defer. Credentials key reserved; image asset is a
   follow-up.
4. **Markdown subset for in-app** → `[text](url)` only. No bold / code / italic.
5. **Localization / TZ rendering** → UTC ISO-8601 for v1. Install-tz rendering
   is a follow-up.
6. **Per-event-type Discord embed `image` / `thumbnail`** → Defer. No video
   thumbnails embedded in v1.

## Non-goals (explicit)

- Email / push formatting.
- Digest aggregation.
- Per-event-type Discord image / thumbnail embeds.
- Bold / code / italic markdown in `body`.
- Localization (i18n / TZ-aware rendering).
- Slack workspace-specific styling beyond Block Kit defaults.
- Per-user formatting variants (Q1).

## Implementation lane assignment

Single lane: **rails-impl**. Touches:

- `app/services/notification_formatter.rb` + subdirectory.
- `app/services/notification_formatter/templates/*.rb`.
- `spec/services/notification_formatter/**`.

No `db/`, no `config/`, no `app/views/`, no `app/controllers/`, no `app/mcp/`,
no `extras/`, no `docs/`. Spec 1 + Spec 3 own those.
