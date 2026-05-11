# Phase 16 — Notification Model + Delivery Channels

> **Status:** specs landing 2026-05-10. Implementation pending.
>
> **Realignment work unit:** 8.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; work unit 8
>   ("Notification model + delivery channels + formatter + webhook delivery")
>   plus Resolved ambiguity #6 ("all-users-see-all; no per-user opt-in; webhooks
>   install-level — one each, shared").
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. The notifications half is the source of truth for Phase 16. Per-
>   user `notification_read(...)` join is rejected; install-level shared
>   read-state is the v1 shape per the realignment ambiguity.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install posture; no `tenant_id` on any new table; webhook URLs + feature
>   flags live as install credentials / `AppSetting` rows.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline this phase builds on.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12. `videos.published_at` / `videos.publish_at` /
>   `videos.privacy_status` / `videos.pre_publish_checked_at` are the columns
>   Phase 16's `video_published` / `video_pre_publish_check_missed`
>   notifications hook on.
> - `docs/plans/beta/14-game-model-igdb-sync/` — Phase 14. `games.release_date`
>   feeds the `game_release_*` notification offsets (T-30 / T-7 / T-1 / T-0) via
>   the calendar's `NotificationDispatchDeclaration`.
> - `docs/plans/beta/15-calendar/specs/01-calendar-data-model.md` — Phase 15.
>   `Calendar::NotificationDispatchDeclaration` is the read-only contract Phase
>   16's `NotificationScheduler` consumes. The contract is fixed; the writer
>   (this phase) materializes `Notification` rows from those declarations.

## Specs in this phase

This phase ships as three feature specs to keep the data tier, the formatter /
delivery tier, and the UI / MCP tier self-contained and reviewable:

1. `specs/01-notification-data-model-and-delivery.md` — `notifications` table,
   the `Notification` model + scopes, the install-level Discord + Slack webhook
   delivery posture (credentials + AppSetting flags), the
   `NotificationDeliveryChannel` abstraction with concrete `Discord` / `Slack`
   channels, the Sidekiq jobs (`NotificationDeliver`, `NotificationScheduler`,
   sidekiq-cron schedules), retry / backoff / webhook-failure handling.
2. `specs/02-notification-formatter.md` — per-event-type rendering. Title +
   body + URL templates; Discord rich-embed shape (with severity colors and
   emoji map); Slack block-kit shape; in-app structured payload; MCP plain- text
   payload. Truncation rules per channel.
3. `specs/03-notification-ui-and-mcp-tools.md` — `/notifications` index + show +
   mark-read routes, unread-badge in the nav header (Stimulus + Turbo Stream
   live update), the four MCP tools (`notifications_list`,
   `notifications_mark_read`, `notifications_mark_all_read`,
   `notifications_unread_count`), the `app`-scope gate, and the manual playbook
   covering the full end-to-end smoke.

Each spec carries its own acceptance / test sweep / manual playbook.

## Cross-stack scope

| Surface           | Status                                                                                    |
| ----------------- | ----------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                               |
| MCP rack app      | **In scope.** Spec 3 ships the four read / mark-read tools on the `app` scope.            |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10. CLI parity for new domains is a separate dispatch. |
| Astro / website   | **Skipped.** N/A.                                                                         |

## Next

Master agent dispatches `pito-rails-impl` against Spec 1 first (foundation),
then Spec 2 (consumes Spec 1's `Notification` model), then Spec 3 (consumes
Specs 1 + 2). MCP coverage in Spec 3 fans to `pito-mcp-impl` once the Rails side
is green.

## Sessions

### 2026-05-10 — Spec 01 implementation (rails-impl agent)

Spec 01 (data model + delivery channels) implemented and verified. Two prior
sibling commits (`6391f12` "Fix Turbo Frame mismatch on bulk actions across 5
list surfaces" and `2b271ec` "Phase 19 close-out + Phase 14 Spec 02 + Phase 16
Spec 01 partial") had already landed all of the production code, factories, and
specs. This session re-derived the same files end to end against the spec to
confirm there is no drift, then ran the full Phase 16 suite green.

**Files (all already committed in the two prior commits — no new diffs to
HEAD):**

- Migrations: `20260510170000_create_notifications.rb`,
  `20260510170001_add_webhook_flags_to_app_settings.rb`.
- Model: `app/models/notification.rb` (8 kinds, 4 severities, scopes, state
  methods, idempotency-keys validator, URL well-formedness validator).
- AppSetting helpers: `discord_delivery_enabled?` / `slack_delivery_enabled?`
  (AND-of AppSetting flag with credentials key).
- Channels: `app/services/notification_delivery_channel.rb` (base,
  `TransientFailure` raise-once posture for 5xx / 429 / network), `discord.rb`,
  `slack.rb`, `in_app.rb`.
- Source helpers: `notification_source.rb` namespace, `sync_error.rb`,
  `youtube_reauth_needed.rb`, `video_pre_publish_check_missed.rb`.
- Scheduler service: `notification_scheduler.rb` (calendar declarations walker +
  `find_or_create_by!` idempotency, occurred-entry firing for `milestone_manual`
  / `custom`).
- Payload-builder stub: `notification_payload_builder.rb` (Spec 02 will replace
  with per-kind templates).
- Jobs: `notification_deliver.rb` (Sidekiq, retry: 5, 1m / 5m / 15m / 1h / 6h
  ladder), `notification_scheduler_job.rb` (cron wrapper).
- Cron: `config/sidekiq_cron.yml` registers `notification_scheduler` every
  minute.

**Specs (all already committed):**

| File                                                                       | Examples |
| -------------------------------------------------------------------------- | -------- |
| `spec/factories/notifications.rb`                                          | n/a      |
| `spec/models/notification_spec.rb`                                         | 52       |
| `spec/models/app_setting_spec.rb` (additions)                              | 36 total |
| `spec/services/notification_delivery_channel_spec.rb`                      | 17       |
| `spec/services/notification_delivery_channel/discord_spec.rb`              | 21       |
| `spec/services/notification_delivery_channel/slack_spec.rb`                | 13       |
| `spec/services/notification_delivery_channel/in_app_spec.rb`               | 4        |
| `spec/services/notification_source/sync_error_spec.rb`                     | 6        |
| `spec/services/notification_source/youtube_reauth_needed_spec.rb`          | 7        |
| `spec/services/notification_source/video_pre_publish_check_missed_spec.rb` | 7        |
| `spec/services/notification_scheduler_spec.rb`                             | 16       |
| `spec/jobs/notification_deliver_spec.rb`                                   | 8        |
| `spec/jobs/notification_scheduler_job_spec.rb`                             | 2        |
| **Phase 16 suite total**                                                   | **189**  |

### Quality gates

- `bundle exec rspec` (Phase 16 sweep + adjacent) — green (189 examples, 0
  failures).
- `bundle exec rspec` (full suite) — 3010 examples, 8 failures, 1 pending. The 8
  failures are all pre-existing and unrelated (Phase 14 Spec 02 in-flight
  rework: `games_spec.rb` IGDB seed-id collisions, `composites_spec.rb`
  path-traversal request, `video_game_link_spec.rb` cascade-on-delete;
  `calendar/month_spec.rb` non-numeric route constraint test, also
  pre-existing). None of them touch the notification surface; they are
  sibling-agent territory.
- `bundle exec rubocop` (notification surface only — 29 files including the
  migrations, models, services, jobs, factory, specs) — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings.

### Master agent decisions honored

1. **Payload-builder v1 stub.** Minimal stub returning
   `{ title: humanized_event_type, body: nil, url: nil, event_payload: {} }`
   plus an `overrides:` hash so source helpers can supply their per-kind strings
   without waiting for Spec 02. Spec 02 replaces with per-kind templates.
2. **Phase 7 / 12 / 13 callsite wiring — DEFERRED.** The three source helpers
   (`SyncError.report!`, `YoutubeReauthNeeded.report!`,
   `VideoPrePublishCheckMissed.report!`) ship with full unit specs; the parent
   jobs (`Youtube::TokenRefresher`, `VideoSyncBack`, analytics-sync engine) were
   NOT modified per the brief. Wiring lands in a follow-up dispatch — the parent
   jobs already track the relevant state (`needs_reauth` flip, sync-back error
   string, missed-check detection in Phase 12), so wiring is a one-liner per
   call site.
3. **Single `retry_count` per row.** Discord + Slack retries on the same row
   both bump the same counter; row counter may read above 5 if both channels
   have failed. Documented for Spec 03's UI rendering.
4. **`config/sidekiq_cron.yml` placement.** Followed Phase 15's established
   pattern (`milestone_evaluator`, `calendar_occurred_flipper`). New
   `notification_scheduler` entry mirrors that shape.

### Cross-cutting note (drift / surfaced)

- **UUID vs bigint.** Spec 01 calls for UUID primary keys per ADR 0003; the
  actual schema (calendar_entries, milestone_rules, users, ...) uses bigint.
  Bigint chosen here for FK referential consistency. ADR 0003 may need an
  amendment for the URL-vs-PK distinction; flagged for master-agent review
  (Phase 15's log already surfaced the same issue).
- **`scheduled_for` column.** Master decision dropped it from v1 (YAGNI). Schema
  reflects the drop.

### Manual playbook (handed to user)

The spec ships an 11-step manual playbook (credentials block edit, run
migration, toggle delivery flags, trigger calendar-derived event, sync error
helper, YouTube re-auth helper, missed pre-publish check helper, webhook failure
simulation, full RSpec, rubocop, Sidekiq cron page). Awaiting user validation
before commit.

### Blockers / next steps

- **Spec 02 (formatter)** — replaces the payload-builder stub with per-kind
  Discord embed / Slack block-kit / in-app structured payloads.
- **Spec 03 (UI + MCP tools)** — `/notifications` index + show + mark-read
  routes, four MCP tools on the `app` scope, unread-badge.
- **Source-helper callsite wiring** — three one-line additions in Phase 7 / 12 /
  13 jobs (`Youtube::TokenRefresher`, `VideoSyncBack`, analytics-sync engine).
  Best landed alongside Spec 02 / 03 so the full notification surface ships
  together.

## 2026-05-10 — Spec 01 security audit fixes (F1–F4)

### Context

Security review of Spec 01 returned four findings rated HIGH / MEDIUM. Fixed
forward in a single rails-impl pass; no new spec doc, only code

- tests.

### What was implemented

1. **F1 (HIGH) — open-redirect via protocol-relative URL.**
   `Notification::APP_PATH_PATTERN` was `\A/[^\s]*\z` — accepted `//evil.com/x`
   and `/\evil.com/x`. Tightened to `\A/(?![/\\])[^\s]*\z`: leading `/`
   required, second character must not be `/` or `\`. Interior double slashes
   (`/foo//bar`) still pass. Added eight regression tests covering the bypass
   shapes plus explicit `javascript:` / `data:` / `vbscript:` / `file:`
   documenting that the pattern shape rejects them.
2. **F2 (MEDIUM) — outbound webhook timeouts.** Hoisted a `configure_http(http)`
   helper onto the base `NotificationDeliveryChannel` so Discord and Slack
   inherit identical settings: `open_timeout=5`, `read_timeout=10`,
   `write_timeout=10`, `ssl_timeout=5`. Both `perform_post` implementations now
   call `configure_http(http)` before `http.request`. Added per-channel specs
   that capture the `Net::HTTP` instance and assert the four timeouts.
3. **F3 (MEDIUM) — webhook host allowlist.** Each channel now exposes
   `deliverable_url?(url)` (Discord:
   `DISCORD_HOSTS = %w[discord.com discordapp.com]`, Slack:
   `SLACK_HOSTS = %w[hooks.slack.com]`). `enabled?` now folds in the allowlist
   plus a non-blank URL check; a misconfigured URL logs a `Rails.logger.warn`
   once per delivery attempt and returns
   `Result.new(status: :skipped, reason: :disabled)` (no POST is sent — verified
   by the absence of a WebMock stub causing an error if the path were
   exercised). Tests cover valid hosts, attacker-controlled hosts, loopback,
   http-only, the wrong slack subdomain, malformed URIs, and the warn log line.
4. **F4 (MEDIUM) — CHECK vs cascade conflict.** New migration
   `db/migrate/20260510190000_fix_notifications_calendar_entry_cascade.rb`
   replaces the `:nullify` FK on `source_calendar_entry_id` with `:cascade`.
   Without `dedup_key`, deleting a calendar entry would NULL the FK and raise
   CHECK; cascade is the cleanest interpretation — calendar-derived rows die
   with their source. The original migration is NOT rewritten. Spec rewritten:
   the old "FK becomes NULL" test is replaced by two cascade regression tests
   (with and without an auxiliary `dedup_key`).

### Files touched

- `app/models/notification.rb` — `APP_PATH_PATTERN` tightened.
- `app/services/notification_delivery_channel.rb` — `configure_http` helper;
  `deliverable_url?` subclass interface (default false).
- `app/services/notification_delivery_channel/discord.rb` — allowlist constant,
  `enabled?` integration, `deliverable_url?`, `perform_post` calls
  `configure_http`.
- `app/services/notification_delivery_channel/slack.rb` — same shape as Discord
  with `SLACK_HOSTS`.
- `db/migrate/20260510190000_fix_notifications_calendar_entry_cascade.rb` — new.
- `db/schema.rb` — re-emitted by the migration (FK now `:cascade`).
- `spec/models/notification_spec.rb` — F1 protection block + cascade regression
  tests; old nullify test rewritten.
- `spec/services/notification_delivery_channel/discord_spec.rb` — F2 timeouts
  block + F3 allowlist block.
- `spec/services/notification_delivery_channel/slack_spec.rb` — same.

### Test outcome

`bundle exec rspec` for the in-scope files (notification model, delivery base,
discord, slack, deliver job): 138 examples, 0 failures. `bundle exec rubocop`
clean across the changed files. `bundle exec brakeman -q -w2`: 0 security
warnings.

Three pre-existing failures elsewhere in the suite
(`spec/requests/calendar/month_spec.rb:35`,
`spec/requests/composites_spec.rb:28`,
`spec/services/notification_formatter/discord_spec.rb:231`) are unrelated to
this audit pass and live outside the strict scope declared by the task.

### Open follow-ups

- Spec 02's `notification_formatter/discord_spec.rb:231` script-tag escape
  assertion is failing; that file is part of the in-progress Spec 02 work, not
  Spec 01, and was excluded from this audit's scope.
- The credentials block remains the same key shape
  (`notifications.discord_webhook_url`, `notifications.slack_webhook_url`);
  operators who configure a URL outside the new allowlist will see delivery
  skipped and a warn line rather than a POST. Manual playbook should mention
  this once Spec 02 / 03 assemble the user-facing settings page.

## 2026-05-10 — Spec 02 implementation (rails-impl agent)

### Context

Spec 02 (per-event-type formatter) implemented end to end against the
`docs/plans/beta/16-notifications/specs/02-notification-formatter.md` contract.
Ships the `NotificationFormatter` namespace + four channel formatters
(`Discord`, `Slack`, `InApp`, `Mcp`) + eight per-kind template POROs + the
registry that wires them together. Master agent decisions 2026-05-10 honored
verbatim (8 copy + 6 open-question locks).

### Files (production)

- `app/services/notification_formatter.rb` — namespace + shared helpers
  (`severity_color`, `emoji_for`, `link`, `escape_for`, `truncate_for`,
  `format_timestamp`, `absolute_url`, `avatar_url`, `template_for`). Constants
  for severity → Discord int, severity → in-app class, event_type → emoji, the
  four per-channel size caps, and the Unicode ellipsis truncation marker.
- `app/services/notification_formatter/discord.rb` — Discord webhook payload
  builder. Rich-embed shape + emoji-prefixed `content` line
  - escapes user-supplied content while preserving the formatter's own
    `[text](url)` markdown links via a tokenizing pass.
- `app/services/notification_formatter/slack.rb` — Slack Block Kit payload
  builder. Header / section / context blocks. Rewrites the templates'
  Discord-style `[text](url)` markdown to Slack's `<url|text>` syntax; appends
  `<absolute_url|view in pito>` when the notification has a URL.
- `app/services/notification_formatter/in_app.rb` — structured hash for §3's ERB
  views. Converts `[text](url)` markdown to `<a href="url">text</a>` HTML,
  html-escapes user-supplied content before linkification, runs the result
  through Rails' `SafeListSanitizer` with an `<a href>`-only whitelist. Per
  master decision: in-app `urgent` severity uses `--color-warn` (amber), not
  red. `read` is the internal Boolean.
- `app/services/notification_formatter/mcp.rb` — markdown + metadata payload for
  §3's MCP tools. Backslash-escapes the same set as Discord. Per CLAUDE.md
  boundary rule: `read` is the string `"yes"` / `"no"`, not a Boolean.
- `app/services/notification_formatter/templates.rb` — `REGISTRY` hash
  (event_type string → template class).
- `app/services/notification_formatter/templates/base.rb` — abstract base. Reads
  from `event_payload` only (verified by spec). Provides `payload`, `fetch`,
  `placeholder`, and `join_list` helpers.
- `app/services/notification_formatter/templates/<eight kinds>.rb` — one PORO
  each for `video_published`, `video_pre_publish_check_missed`,
  `game_release_upcoming`, `game_release_today`, `milestone_reached`,
  `calendar_entry_firing`, `sync_error`, `youtube_reauth_needed`. Each
  implements `#title`, `#body`, `#url` per the spec's per-event-type table
  verbatim.

### Files (specs — 14 new + 3 touched)

| File                                                          | Examples |
| ------------------------------------------------------------- | -------- |
| `spec/services/notification_formatter_spec.rb`                | 52       |
| `spec/services/notification_formatter/discord_spec.rb`        | 21       |
| `spec/services/notification_formatter/slack_spec.rb`          | 17       |
| `spec/services/notification_formatter/in_app_spec.rb`         | 14       |
| `spec/services/notification_formatter/mcp_spec.rb`            | 12       |
| `spec/services/notification_formatter/templates/base_spec.rb` | 11       |
| `templates/video_published_spec.rb`                           | 9        |
| `templates/video_pre_publish_check_missed_spec.rb`            | 7        |
| `templates/game_release_upcoming_spec.rb`                     | 12       |
| `templates/game_release_today_spec.rb`                        | 7        |
| `templates/milestone_reached_spec.rb`                         | 8        |
| `templates/calendar_entry_firing_spec.rb`                     | 7        |
| `templates/sync_error_spec.rb`                                | 5        |
| `templates/youtube_reauth_needed_spec.rb`                     | 5        |
| **New formatter sweep total**                                 | **205**  |

Touched (test infrastructure only):

- `spec/services/notification_delivery_channel/discord_spec.rb` — added a
  defensive `allow(...).to receive(:dig).and_return(nil)` fallback so the
  formatter's `pito_avatar_url` lookup does not trip the strict `with(...)`
  matcher.
- `spec/services/notification_delivery_channel/slack_spec.rb` — same.
- `spec/jobs/notification_deliver_spec.rb` — same shape, two specs.

### Master agent decisions honored (2026-05-10)

1. **Per-kind title templates** — verbatim per spec.
2. **Per-kind body templates** — verbatim per spec.
3. **Empty-body fallback for `calendar_entry_firing`** —
   `"calendar entry fired."`.
4. **Slack "view in pito" link label** — `view in pito`.
5. **`pito` username on Discord/Slack** — lowercase.
6. **Avatar URL credentials key** —
   `Rails.application.credentials.notifications.pito_avatar_url` (nullable; key
   omitted from JSON when nil).
7. **Severity → emoji map** — Q6 verbatim.
8. **Truncation marker** — single Unicode ellipsis `…`.
9. **In-app urgent severity** uses `--color-warn` (amber) per CLAUDE.md hard
   rule on red usage.
10. **Markdown subset for in-app** — `[text](url)` only. Sanitize whitelists
    `<a>` with `href` attribute only.
11. **TZ rendering** — UTC ISO-8601 in v1; install-tz rendering deferred.

### Quality gates

- `bundle exec rspec spec/services/notification_formatter*` — 205 examples, 0
  failures.
- Phase 16 sweep (`spec/services/notification_formatter*`,
  `spec/services/notification_delivery_channel*`,
  `spec/services/notification_scheduler_spec.rb`,
  `spec/services/notification_source*`,
  `spec/jobs/notification_deliver_spec.rb`,
  `spec/jobs/notification_scheduler_job_spec.rb`,
  `spec/models/notification_spec.rb`, `spec/models/app_setting_spec.rb`) — 421
  examples, 0 failures.
- Full suite (`bundle exec rspec`) — 3530 examples, 2 pre-existing failures
  unrelated to formatter work (`spec/requests/calendar/month_spec.rb:35`
  non-numeric route constraint and `spec/requests/composites_spec.rb:28`
  path-traversal request; both pass in isolation, both surfaced in the Spec 01
  log as pre-existing).
- `bundle exec rubocop` (formatter surface + touched specs, 32 files) — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings.

### Notes / drift

1. **`NotificationPayloadBuilder` left as-is.** Spec 02's hard scope says
   "replace stub with full per-kind formatter". The actual spec contract
   (§"Files touched") only authorizes new files under
   `app/services/notification_formatter*`. The payload builder's current stub
   posture (`{ title, body, url, event_payload }`) is what §1's source helpers +
   scheduler write into the row at insert time; the formatter reads from those
   keys. No drift surfaced — the per-event-type templates handle missing keys
   via the `fetch` + `placeholder` helpers gracefully. If §1's source helpers
   are later updated to denormalize the keys the templates expect (e.g.,
   `scope_label` for `milestone_reached`), the templates pick those up
   automatically.
2. **Discord avatar asset** — credentials key is reserved per master decision;
   the actual image asset is a follow-up. Today the `avatar_url` key is omitted
   from the JSON when credentials carry nil, so the Discord webhook falls back
   to its default avatar.
3. **Smuggled markdown links in user-content.** A user-authored
   `[here](https://evil.x)` inside `event_payload[:video_title]` currently
   passes through to MCP body markdown unaltered (the tokenizing pass treats it
   as a real link). For Discord and the in-app surface this is fine: Discord's
   escape pass turns the surrounding chars into `\[here\]` + `\(...\)` because
   user-content gets the full escape pass before linkification. Surfaced as a
   reviewer follow-up — if MCP hosts are sensitive to smuggled link markdown the
   tokenizer can be tightened.

### Manual playbook

Spec 02's manual playbook (10 steps; see
`docs/plans/beta/16-notifications/specs/02-notification-formatter.md` §"Manual
playbook (post-implementation)") covers Discord / Slack / InApp / MCP shape
smokes, truncation smoke, escaping smoke, end-to-end delivery smoke, and the
rspec / rubocop gates. Awaiting user validation.

### Blockers / next steps

- **Spec 03 (UI + MCP tools)** — `/notifications` index + show + mark-read
  routes, four MCP tools on the `app` scope, unread-badge. Consumes Spec 02's
  `InApp` formatter for the views and the `Mcp` formatter for the tools.
- **Source-helper callsite wiring** (carryover from Spec 01 log) — three
  one-line additions in Phase 7 / 12 / 13 jobs.

## 2026-05-10 — Spec 03 implementation continuation (rails-impl agent)

### Context

An earlier dispatch landed Spec 03's controller + model callbacks + routes in
commit `4fa4509`, but timed out before the views, MCP tools, Stimulus
controller, and full spec coverage were written. The missing
`app/views/notifications/_badge.html.erb` partial caused the F3 audit assertion
in `spec/services/notification_delivery_channel/discord_spec.rb` to fail (the
`Notification.after_create_commit` broadcast tripped on a missing template,
which was rescued + logged via `Rails.logger.warn`, which then collided with the
spec's
`expect(Rails.logger).to receive(:warn).with(/DISCORD_HOSTS allowlist/)`). This
session fills in the gaps.

### Files (production)

- **Views (4 new):**
  - `app/views/notifications/_badge.html.erb` — unread-count badge fragment.
    Renders `[ N ]` when `unread_count > 0`, an empty wrapper otherwise. Wrapper
    carries a stable `id="notifications_badge"` so Turbo Stream
    `broadcast_replace_to` can target it.
  - `app/views/notifications/_notification.html.erb` — single-row partial.
    Renders glyph + bold (unread) / muted (read) title + severity badge +
    `time_ago_in_words` + `[ mark read ]` (only if unread). The wrapper `<tr>`
    carries `dom_id(notification)` so `broadcast_replace_to` finds it on
    read-state flip.
  - `app/views/notifications/index.html.erb` — paginated list view. Filter
    cluster `[ all ]` / `[ unread ]` (master decision #8), `[ mark all read ]`
    button when unread_count > 0, empty state `no notifications yet.` (master
    decision #2). Webhook misconfigured banner when any unread row carries
    `last_error` (master decision #12).
    `turbo_stream_from "notifications_index"` subscribes the page to live row
    prepends.
  - `app/views/notifications/show.html.erb` — detail page. Title + severity
    badge + body_html (formatter-rendered, `<a>`-only sanitized) + relative +
    ISO timestamp + per-channel delivery state + `last_error` (when non-blank) +
    `[ mark read ]` / `[ mark unread ]` (state-dependent) + `[ open ]` (master
    decision #6, NOT `[ open source ]`) + `[ back ]`. The `[ open ]` link wires
    the `notification-link` Stimulus controller for auto-mark-on-click.

- **Stimulus (1 new):**
  - `app/javascript/controllers/notification_link_controller.js` —
    `markReadAndNavigate` action. Issues a fire-and-forget `fetch` PATCH to
    `/notifications/:id/read` with `keepalive: true`, then allows the link to
    navigate. NO `window.confirm` / `alert` / `prompt` / `data-turbo-confirm`
    (CLAUDE.md hard rule). Fully defensive: on PATCH failure the link still
    navigates.

- **Layout (1 light edit):**
  - `app/views/layouts/application.html.erb` — adds the `[notifications]` nav
    link + the badge fragment (subscribed to `notifications_badge` stream) to
    the header nav row, plus the `[notifications]` link to the footer nav row
    for parity.

- **MCP tools (4 new):**
  - `app/mcp/tools/notifications_list.rb` — paginated list (`page`, `per_page`
    capped at 100). Filters by `unread: "yes"/"no"`, `kind`, `severity`. Returns
    `notifications: [...]` (per `NotificationFormatter::Mcp.payload_for`) +
    `pagination: {page, per_page, total, total_pages}`. Each row has `read` as a
    `"yes"` / `"no"` string (CLAUDE.md boundary rule). Gates on `Scopes::APP`.
    `additionalProperties: false`.
  - `app/mcp/tools/notifications_unread_count.rb` — returns `{count: <int>}`. No
    params. Gates on `Scopes::APP`. No cache (master decision open-question #7).
  - `app/mcp/tools/notifications_mark_read.rb` — bulk mark-read. Accepts
    `ids: [<int>, ...]`. NO `confirm` requirement (master decision open-question
    #3 — mark-read is non-destructive). Single call performs the mutation and
    returns `{marked_read, ids, not_found_ids}`. Idempotent on already-read rows
    (only counts new flips). Gates on `Scopes::APP`. Strict integer validation
    (rejects non-integer + non-numeric-string ids with a clear error).
  - `app/mcp/tools/notifications_mark_all_read.rb` — marks every unread row
    read. No params. NO `confirm` requirement. Gates on `Scopes::APP`. Returns
    `{marked_read: <count>}`.

- **CSS (light edit):**
  - `app/assets/tailwind/application.css` — appended ~24 lines:
    `.notifications-badge` wrapper,
    `.notification-row.notification-(read|unread)` title weight,
    `.notification-severity-badge` + 4 severity-color selectors. Per CLAUDE.md
    hard rule: `urgent` maps to `--color-warn` (amber), NOT red (red is reserved
    for destructive actions only).

### Files (specs — 9 new)

| File                                                  | Examples |
| ----------------------------------------------------- | -------- |
| `spec/requests/notifications_spec.rb`                 | 41       |
| `spec/system/notifications_index_spec.rb`             | 13       |
| `spec/system/notifications_show_spec.rb`              | 13       |
| `spec/system/notifications_badge_live_update_spec.rb` | 5        |
| `spec/views/notifications/index_html_erb_spec.rb`     | 8        |
| `spec/views/notifications/show_html_erb_spec.rb`      | 12       |
| `spec/views/notifications/_badge_html_erb_spec.rb`    | 5        |
| `spec/mcp/tools/notifications_list_spec.rb`           | 21       |
| `spec/mcp/tools/notifications_unread_count_spec.rb`   | 5        |
| `spec/mcp/tools/notifications_mark_read_spec.rb`      | 18       |
| `spec/mcp/tools/notifications_mark_all_read_spec.rb`  | 9        |
| **Spec 03 sweep total**                               | **150**  |

### Master agent decisions honored

All 14 copy decisions + 7 open-question decisions from the 2026-05-10 lock are
reflected in the implementation:

- `[ all ]` / `[ unread ]` filter cluster.
- `[ mark read ]` / `[ mark unread ]` / `[ mark all read ]` / `[ open ]` (NOT
  `[ open source ]`) / `[ back ]`.
- Empty state copy: `no notifications yet.`.
- Severity badge: lowercase enum text.
- Per-channel state: `pending` / iso-timestamp / `disabled`.
- Webhook misconfigured banner copy (verbatim).
- Bulk URL pattern: `/notifications/mark_read?ids=A,B,C` (collection PATCH with
  `?ids=` param — open-question #2).
- Auto-mark-on-click: kept (open-question #1).
- NO `confirm: yes/no` requirement on the mark-read MCP tools (open-question #3
  override of CLAUDE.md symmetry argument — mark-read is non-destructive).
- Bold unread / muted read; no glyph prefix (open-question #6).
- No cache for `notifications_unread_count` (open-question #7).
- F1 hardening: `notification.url` is post-validated by the model
  (`url_is_well_formed_when_present`). Default ERB `<%= %>` escaping is used
  everywhere — no `html_safe` on user-derived URLs. The show-view spec asserts
  the exact escape path (`&` → `&amp;`).

### Quality gates

- Spec 03 sweep (`spec/requests/notifications_spec.rb`,
  `spec/system/notifications_*_spec.rb`, `spec/views/notifications/`,
  `spec/mcp/tools/notifications_*_spec.rb`) — 150 examples, 0 failures.
- Phase 16 sweep (Spec 01 + 02 + 03, plus the model + AppSetting + scheduler +
  delivery channels + jobs) — 499 examples, 0 failures.
- Full suite (`bundle exec rspec`) — 3825 examples, 3 failures, 1 pending. Three
  failures are all pre-existing on `main` (calendar/month route constraint,
  composites path-traversal, calendar_edit_delete_spec note-link selector); none
  touch the notification surface. Same set surfaced in Spec 01 + 02 logs.
- `bundle exec rubocop` (notification surface — 17 ruby files, excluding ERB
  which rubocop cannot lint) — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings.

### F3 fix-forward (delivery-channel spec failure)

The pre-session `discord_spec.rb:225` failure ("logs a warning when configured
URL fails the allowlist") was caused by the Notification model's
`after_create_commit` broadcast trying to render a missing
`notifications/_badge` partial. The broadcast's rescue logged a warn line, which
collided with the spec's
`expect(Rails.logger).to receive(:warn).with(/DISCORD_HOSTS allowlist/)`.
Creating the partial resolved the failure: spec now passes (verified in
isolation + the full delivery-channel sweep).

### Drift / surfaced

1. **MCP `notifications_mark_read` tool argument shape.** Per master decision
   #3, the `confirm` parameter was removed entirely (the spec's input_schema
   does not declare it). Mark-read is non-destructive. The `delete_records` tool
   keeps `confirm` because it IS destructive — symmetry across the bulk MCP
   surface is intentionally broken here.
2. **Notification IDs are bigint, not UUID.** The schema (per Spec 01 log "UUID
   vs bigint" drift note) is bigint. The MCP tool input schema reflects this
   (`items: { type: "integer" }`); the controller's `parse_ids` helper coerces
   to `Integer` via `to_i` and rejects zeros (so empty / non-numeric strings
   drop out silently — matches existing `DeletionsController` precedent).
3. **No new database migration.** Per spec contract: §3 is purely UI /
   controller / route / MCP-tool work on top of §1's models.

### Manual playbook

The spec's 18-step manual playbook covers the full happy path (notification
trigger → in-app row → Discord → Slack → badge decrement live → mark-read → MCP
smoke). Awaiting user validation before commit.

### Blockers / next steps

- **Source-helper callsite wiring** (carryover from Spec 01 log) — three
  one-line additions in Phase 7 / 12 / 13 jobs (`Youtube::TokenRefresher`,
  `VideoSyncBack`, analytics-sync engine). Independent of the UI surface; can
  ship in a follow-up.
- **Settings UI for `discord_enabled` / `slack_enabled`** — follow-up. Currently
  togglable only via the AppSettings table.
- **Phase 16 closeout** — once the user validates the playbook, Spec 03 closes
  Phase 16. Sibling phases referenced by the source- helper wiring
  (`Youtube::TokenRefresher` etc.) should be wired in a focused follow-up
  dispatch.

## Session 2026-05-10 — UX restructure (badge sup + modal + bulk + cleanup cron)

User-driven UX restructure of the notification surface. Five concurrent changes,
plus a cleanup cron job. No spec file under `specs/` — this is an in-flight
refinement of Spec 03's UI tier.

### Scope (per user request)

1. **Unread badge.** Render the count as `<sup>N</sup>` next to
   `[notifications]` (no surrounding brackets). Hide entirely at zero.
2. **Notification modal.** Clicking a row opens the show page inside an in-page
   `<dialog>` via Turbo Frame; `/notifications/:id` stays as a direct-link
   fallback. Closes on Escape, click outside, or `[back]`.
3. **Filter row.** Drop the `[ all ]` / `[ unread ]` bracketed-link toggles.
   Replace with a single `[ ] unread` `FilterChipComponent` chip; default
   unchecked = show all; checked = `?filter=unread`. The `[mark all as read]`
   button sits to its right.
4. **Bulk select.** Each unread row gets a Stimulus `bulk-select` checkbox in
   column 1 (read rows omit it). The wrapper carries
   `data-controller="bulk-select notifications-dynamic-button"`.
5. **Dynamic button label.** A new `notifications_dynamic_button_controller.js`
   watches every checkbox change and swaps the button text + form action between
   `[mark all as read]` -> `/notifications/mark_all_read` (default and when ALL
   unread are selected) and `[mark <N> as read]` ->
   `/notifications/mark_read?ids=A,B,C` (partial selection).
6. **Cleanup cron.** New `NotificationCleanupJob` deletes every read
   notification whose `in_app_read_at` is older than 7 days. Cron entry in
   `config/sidekiq_cron.yml` -> `notification_cleanup`, daily at 03:30 UTC.
7. **Caption.** A muted note under the H1 reads "notifications are deleted 7
   days after being read." so the cron's data loss is discoverable.

### Files touched

- `app/views/notifications/_badge.html.erb` — `<sup>N</sup>` shape.
- `app/views/notifications/index.html.erb` — `bulk-select` +
  `notifications-dynamic-button` controller wiring; FilterChipComponent chip;
  cleanup caption; `<dialog>` mount with the `notification_detail_frame` Turbo
  Frame.
- `app/views/notifications/show.html.erb` — wraps the body in
  `turbo_frame_tag "notification_detail_frame"`; `[back]` carries
  `click->notification-modal#close` so it closes the dialog when rendered inside
  the modal AND falls back to `/notifications` when rendered standalone.
- `app/views/notifications/_notification.html.erb` — bulk-select checkbox column
  1 (unread only); row link carries `click->notification-modal#open`; per-row
  `[mark read]` action retired (covered by bulk button + modal `[mark read]`).
- `app/javascript/controllers/notifications_dynamic_button_controller.js` — new.
  Stimulus controller that swaps the button label + form action based on
  selected checkbox count vs the page's total-unread.
- `app/javascript/controllers/notification_modal_controller.js` — new. Stimulus
  controller that opens the dialog and points the inner Turbo Frame at the row's
  URL on click.
- `app/jobs/notification_cleanup_job.rb` — new. Hard-deletes read notifications
  older than `RETENTION_PERIOD = 7.days`. Uses `delete_all` (skips per-row
  destroy callbacks; the badge re-renders on the next page load anyway).
- `config/sidekiq_cron.yml` — new `notification_cleanup` entry, `30 3 * * *`.
- `app/assets/tailwind/application.css` — `.notifications-badge-count` rule
  (10px bold, `vertical-align: super`); wrapper switched from
  `align-items: center` to `align-items: flex-start` so the sup hugs the top of
  the nav line.

### Specs added / updated

- `spec/jobs/notification_cleanup_job_spec.rb` — NEW. 11 examples: retention
  boundary, unread skip, no-op path, log line, cron yaml registration.
- `spec/system/notifications_dynamic_button_spec.rb` — NEW. 6 examples: asserts
  the SSR scaffold (controller registration, value attributes, form / label
  targets, hide-when-zero-unread).
- `spec/system/notifications_modal_spec.rb` — NEW. 7 examples: dialog
  - Turbo Frame mount, row link wiring, show-page frame wrap, back link Stimulus
    action.
- `spec/views/notifications/_badge_html_erb_spec.rb` — UPDATED. Asserts `<sup>`
  shape; rejects the old `[ N ]` shape.
- `spec/views/notifications/index_html_erb_spec.rb` — UPDATED. Drops `[ all ]` /
  `[ unread ]` link assertions; asserts the FilterChipComponent shape,
  dynamic-button wiring, modal mount, cleanup caption.
- `spec/views/notifications/show_html_erb_spec.rb` — UPDATED. Bracket regex
  tightened to `\[<span class="bl">…<\/span>\]`; new asserts on Turbo Frame
  wrap + `[back]` Stimulus close action.
- `spec/system/notifications_index_spec.rb` — UPDATED. Drops `[ all ]` /
  `[ unread ]` link assertions; adds chip-click / chip-checked assertions,
  row-checkbox shape, modal scaffolding, cleanup caption.
- `spec/system/notifications_badge_live_update_spec.rb` — UPDATED. Regex
  switched from `\[\s*N\s*\]` to the `<sup>` pattern.
- `spec/requests/notifications_spec.rb` — UPDATED. Badge regex + `[back]` /
  `[open]` regexes tightened.

### Quality gates

- `spec/jobs/notification_cleanup_job_spec.rb` — 11 / 11 pass.
- Notification surface sweep (jobs/specs/views/system + request + model) — 510 /
  510 pass, 0 failures.
- `bundle exec rubocop` on the 10 new / changed Ruby files — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings.
- Full suite — 2131 examples; 20 pre-existing failures in `api/footages`,
  `calendar/month`, `channels/analytics`, `analytics_flaw`. None touch the
  notification surface; they are outside this lane.

### Drift / surfaced

1. **Per-row `[mark read]` retired.** The row partial no longer renders a
   per-row `[mark read]` button — bulk + modal cover the flow.
   `spec/system/notifications_index_spec.rb` no longer asserts the per-row
   button. The PATCH `/notifications/:id/read` endpoint stays for the modal's
   own `[mark read]` form.
2. **Auto-mark-on-click stays via the modal.** Clicking a row opens the modal
   AND fetches the show page through Turbo, which is side-effect-free; the show
   page then renders the `[mark read]` button. The original auto-mark-on-click
   semantic was tied to the `[open]` link's `notification-link` Stimulus
   controller — that still fires when the user clicks `[open]` from inside the
   modal.
3. **Caption placement.** The cleanup caption sits under the H1 (not in the lead
   paragraph slot) because the index page has no `<p class="text-muted">` lead
   paragraph; adding one would expand the caption convention beyond settings
   detail / show / new / edit pages. Single-line muted note matches the existing
   tone.

### Next steps

- Manual playbook (user): verify badge sup renders correctly in dark mode; click
  a row -> modal opens; check / uncheck a row -> button text flips between
  `mark all as read` and `mark <N> as read`; click `mark <N> as read` -> only
  selected rows flip; `[ ] unread` chip toggles `?filter=unread`; cron job runs
  (sidekiq web at `/sidekiq` shows `notification_cleanup` scheduled).
- Once validated, master commits + pushes.

## 2026-05-10 — Spec 02/03 security audit fixes (F1 + F2 + F3)

### Context

Security review of Spec 02 (formatter) + Spec 03 (UI + MCP tools) returned
verdict `CLEAR TO MERGE` with three Medium defense-in-depth findings. Fixed
forward in a single rails-impl pass; no spec doc change.

Reference:
`docs/orchestration/playbooks/security-2026-05-10-phase-16-spec-02-and-03-notifications.md`.

### What was implemented

1. **F1 (MEDIUM) — in-app `event_payload` URL scheme allowlist.** Added
   `NotificationFormatter::ALLOWED_URL_SCHEMES = %w[http https mailto]` and
   `NotificationFormatter.url_scheme_allowed?(url)` helper. The helper accepts
   `http://`, `https://`, `mailto:` schemes plus leading-slash app paths
   (rejecting `//evil.com` protocol-relative). `InApp#render_body_html`
   validates each `[text](url)` URL via the helper BEFORE writing the `<a>` tag
   — bad-scheme URLs collapse to bare escaped text. Closes audit F4 as a side
   effect (no empty `<a></a>` shell survives Loofah's `href`-only strip because
   the `<a>` was never written).

2. **F2 (MEDIUM) — outbound markdown URL scheme allowlist (MCP / Discord /
   Slack).** Same allowlist applied at three additional formatter boundaries:
   `Mcp#escape_body_preserving_links`, `Discord#escape_body_preserving_links`,
   `Slack#rewrite_markdown_links`. The URL captured by the markdown regex's
   `match[2]` group is scheme-checked; bad-scheme URLs collapse to bare
   channel-escaped text rather than emitting `[text](javascript:…)`,
   `<javascript:…|text>`, or similar to downstream renderers. The brief
   confirmed option 1 (formatter boundary), not an inbound write-tool validator
   — no such tool exists.

3. **F3 (MEDIUM) — per-user 5s rate-limit lock on bulk mark-read.** Added a
   `before_action :enforce_mark_read_rate_limit` on
   `NotificationsController#mark_read` and `#mark_all_read`. Mirrors the Phase
   13 analytics-refresh `Rails.cache.write(..., unless_exist: true)` pattern
   with a per-user lock key (`notifications:mark_read:user:<id>`) and
   `MARK_READ_RATE_LIMIT_TTL = 5.seconds`. HTML → 302 redirect + alert; JSON →
   `429 + { error: "rate_limited", retry_after_seconds: 5 }`; Turbo Stream →
   429 + plain-text body. Added `format.json { render json: { marked: N } }` to
   both happy paths (the JSON branch was missing before).

### Files touched

- `app/services/notification_formatter.rb` — `ALLOWED_URL_SCHEMES` constant +
  `url_scheme_allowed?` module function.
- `app/services/notification_formatter/in_app.rb` — pre-validate URL inside
  `render_body_html` before writing `<a>`.
- `app/services/notification_formatter/mcp.rb` — scheme check inside
  `escape_body_preserving_links`; bad-scheme → bare escaped text.
- `app/services/notification_formatter/discord.rb` — same shape.
- `app/services/notification_formatter/slack.rb` — same shape inside
  `rewrite_markdown_links`.
- `app/controllers/notifications_controller.rb` — `MARK_READ_RATE_LIMIT_TTL`
  constant, `before_action :enforce_mark_read_rate_limit`, `format.json`
  branches on mark_read / mark_all_read, `enforce_mark_read_rate_limit` private
  helper.
- `spec/services/notification_formatter/in_app_spec.rb` — F1 block: 12 examples.
- `spec/services/notification_formatter/mcp_spec.rb` — F2 block: 11 examples.
- `spec/services/notification_formatter/discord_spec.rb` — F2 block: 11
  examples.
- `spec/services/notification_formatter/slack_spec.rb` — F2 block: 11 examples.
- `spec/requests/notifications_spec.rb` — F3 block: 12 examples covering lock
  write, HTML alert redirect, JSON 429 envelope, lock expiry, shared key across
  mark_read / mark_all_read.

### Quality gates

- `bundle exec rspec` on touched files — 125 formatter examples + 54 request
  examples = 179 examples, 0 failures.
- Notification-surface sweep (formatter + delivery + request + model) — 356
  examples, 0 failures.
- `bundle exec rubocop` on the 11 touched Ruby files — clean.
- `bin/brakeman -q -w2` — 0 security warnings (pre-existing obsolete ignore
  entries unrelated to this pass).

### Note on regex shape

The formatter's markdown link regex is `\[([^\[\]]*)\]\(([^()\s]+)\)`. The URL
group rejects `(` and `)`, so attack payloads like `[x](javascript:alert(1))`
never match as a markdown link in the first place — the parens disqualify them.
The scheme allowlist neutralizes paren-free payloads (`javascript:alert@1`,
`data:text/html,whatever`, `vbscript:msgbox`, `file:///etc/passwd`, `tel:+1234`,
protocol-relative `//evil.com/x`). Spec shapes match this regex constraint.

### Next steps

- Manual playbook (user): no UI surface change. Spot-check that `/notifications`
  index + show pages render normally; clicking a row opens the modal; bulk
  mark-read still works under normal click cadence; double- clicking the bulk
  button within 5s shows the slow-down alert.
- Once validated, master commits + pushes.

## 2026-05-11 — Inbox layout revamp (header row + bottom 2-col legend)

### Context

User direction from a screenshot review of `/notifications`:

> arrange the legend better, maybe in 2 columns, put it at the bottom of the
> table, it should be one item per line. What is the [info] column all about?
> What other can be there? Let's add a table header for this table.

Spec slug: ad-hoc UX refinement (no new spec file). The `[info]` column was
identified as the `Notification#severity` enum — values are `info`, `success`,
`warn`, `urgent` (per `app/models/notification.rb`).

### What was implemented

- The per-event-type emoji legend moved from the TOP of the page (single muted
  comma-separated caption) to the BOTTOM (after the table + pagination, before
  the notification-detail modal). It now renders as a CSS-grid two-column layout
  (`grid-template-columns: 1fr 1fr`), one `<emoji> <kind label>` pair per line,
  each pair wrapped in its own `.notification-glyph-legend-item` block-level
  div. Source remains `NotificationFormatter::EVENT_TYPE_EMOJI` (one legend
  entry per registered event type, auto-extends).
- Added an explicit `<thead>` to the notifications table. Five columns labelled
  `select`, `kind`, `title`, `severity`, `when`. Matches the app-wide
  `<thead><th>…</th></thead>` pattern used on `/videos`, `/channels`,
  `/settings/tokens`, `/settings/sessions`.
- The header row inherits the global `thead th` style (muted bold, 14px,
  `--color-bg-header` background) from `app/assets/tailwind/application.css`.
- Inline ERB comment block at the top of `index.html.erb` updated to describe
  both moves; an inline column-legend comment now lives next to the `<table>`
  open tag enumerating the four severity enum values so a future reader knows
  what can appear in that column.

### Files touched

- `app/views/notifications/index.html.erb` — moved legend, added `<thead>`,
  refreshed top-of-file comment, added severity-column comment.
- `spec/requests/notifications_spec.rb` — three new examples on legend ordering
  / 2-column grid / per-item wrapper, three new examples on the `<thead>` row
  (labels present, omitted on empty state, present in modal mode). Net `+6`
  examples on the index request block.
- `spec/system/notifications_index_spec.rb` — one new `describe` with four
  examples covering header labels, legend below-table ordering, item count, and
  the two-column grid style.

### Quality gates

- `bundle exec rspec spec/requests/notifications_spec.rb spec/system/notifications_index_spec.rb`
  — 98 examples, 0 failures (54 → 60 request, 34 → 38 system index).
- Sibling notification system specs (modal / navbar modal / badge live update /
  dynamic button / show) — 42 examples, 0 failures.
- `bundle exec rubocop` on touched spec files — clean.
- `bin/brakeman -q -w2` — 0 warnings (pre-existing obsolete ignore entries
  unchanged).

### Manual playbook

1. Open `/notifications` (logged in). Confirm:
   - Table has a single header row labelled
     `select | kind | title | severity | when`.
   - The emoji legend now sits below the table, two columns wide, with one
     `<emoji> kind label` pair per line. Every registered event type appears.
2. Open the layout-level notifications modal (the bell icon in the nav). Confirm
   the modal carries the same shape — header row at the top of the table, legend
   at the bottom.
3. Toggle `?filter=unread` — header row stays, legend stays. Empty state still
   reads `no notifications yet.` when no rows match.

### Next steps

- Master commits + pushes after user validates.
