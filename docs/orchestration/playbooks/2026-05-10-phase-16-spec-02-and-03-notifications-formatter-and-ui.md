# Manual test playbook — Phase 16 Spec 02 + Spec 03 (notification formatter + UI + MCP tools)

**Branch:** `main` **Specs:**
`docs/plans/beta/16-notifications/specs/02-notification-formatter.md`,
`docs/plans/beta/16-notifications/specs/03-notification-ui-and-mcp-tools.md`
**Reviewer run:** 2026-05-10 20:42

Spec 01 already audited (security findings F1–F4 closed in `f0e1882`); this
playbook gates Spec 02 (formatter), Spec 03 (UI + four MCP tools), and the
2026-05-10 UX restructure on top of Spec 03 (superscript badge, `[ ] unread`
filter chip, bulk-select checkboxes, dynamic mark-N-as-read button,
`NotificationCleanupJob` 7-day retention cron, modal-based detail view).

## Pipeline summary

- Code review (manual, scoped to the diff): pass with 7 non-blocking concerns —
  see below.
- Simplify (manual, scoped to the diff): 4 simplification suggestions — see
  below.
- Notification-surface RSpec (formatter + requests + system + views + MCP +
  cleanup job + model): **448 examples, 0 failures**
  (`spec/services/notification_formatter*`, `spec/requests/notifications_spec`,
  `spec/system/notifications_*`, `spec/views/notifications/`,
  `spec/mcp/tools/notifications_*`, `spec/jobs/notification_cleanup_job_spec`,
  `spec/models/notification_spec`).
- Full RSpec excluding system specs: **4117 examples, 20 failures, 1 pending**.
  All 20 failures are pre-existing on `main` and unrelated to the notification
  surface (footages, `bundle_friendly_url`, `collection_friendly_url`,
  `milestone_rule_friendly_url`, `project_friendly_url`, `project_spec`
  friendly_id collision branch, `bundle_members`, `bundles`, `calendar/month`,
  `channels#index` open link, `composites` path-traversal, `dashboard` JSON,
  `note_sync_job`, `notes#show`, `projects#index`, `delete_records` MCP preview,
  `sync_records` MCP preview, `mcp/tools/delete_records`,
  `mcp/tools/sync_records`). Same set surfaced in the Phase 16 Spec 01 / 02 / 03
  logs and in adjacent reviewer playbooks.
- Rubocop (notification surface — 48 ruby + spec files spanning the formatter,
  templates, controller, views' associated specs, MCP tools, model, routes,
  cleanup job): **clean**.
- Brakeman (`-q -w2`): **0 security warnings**, scan-clean.
- Bundler-audit (`--update`): advisory DB up to date; **no vulnerabilities
  found**.
- Per-stack gates (Rust / website / MCP rack): no diff under `extras/`; the MCP
  rack tests are folded into the RSpec suite above.

## Blockers

**None.** The pipeline is green. The concerns and suggestions below are
quality-of-life and are safe to ship as-is or queue as follow-ups.

## Concerns (non-blocking — severity-tagged)

1. **[LOW] Modifier-click navigation broken on row title and `[ open ]`.**
   `notification_modal_controller#open` calls `event.preventDefault()`
   unconditionally
   (`app/javascript/controllers/notification_modal_controller.js:41`). So does
   `notification_link_controller#markReadAndNavigate` indirectly (the Stimulus
   action prevents default before the keepalive PATCH). Cmd-click / ctrl-click /
   middle-click on a row title or the detail page's `[ open ]` no longer opens
   in a new tab — users land on the same-tab modal / navigation regardless.
   Common pattern is
   `if (event.metaKey || event.ctrlKey || event.button === 1) return` at the top
   of `open` / `markReadAndNavigate` so modifier clicks fall through to the
   browser default.
2. **[LOW] Index page issues three independent unread-count queries.**
   `NotificationsController#index` reads `Notification.unread.count` (line 45),
   `Notification.unread.where.not(last_error: …).exists?` (line 46), and the
   layout's `_nav` partial then renders the badge by calling
   `Notification.unread.count` (`app/views/layouts/application.html.erb:101`).
   Three queries on one render. With pagination at 50 rows / page and a partial
   index this is fine, but folding the badge render into the view instance via
   `@unread_count` would save one query.
3. **[LOW] Dynamic-button controller registers a global `document` change
   listener.** `notifications_dynamic_button_controller.js:32` adds a listener
   on every connect. Disconnect cleans it up. The cost is negligible (every
   checkbox change anywhere on the page triggers `_update` →
   `document.querySelectorAll(...)`), but if other Stimulus controllers later
   render checkboxes inside a notifications page, every change re-runs the
   selector. Local listener on `this.element` would scope it.
4. **[LOW] `truncate_for` link-rollback heuristic uses simple `rindex` instead
   of bracket-balance counting.** `notification_formatter.rb:195` rolls back
   when `[` appears after the last `)`. If a body string contains a
   parenthetical aside before a markdown link
   (`hello (world) and [click](url) here`) and the cut falls inside the link,
   the heuristic still works because the `)` belongs to a non-link group and
   `last_close > last_open` fails. Not catastrophic; templates today don't emit
   nested-paren bodies. Worth a TODO comment so future templates avoid
   surprising the heuristic.
5. **[LOW] `NotificationsMarkRead` MCP tool does NOT broadcast row replace.**
   `app/mcp/tools/notifications_mark_read.rb:72` runs
   `update_all(in_app_read_at: …)` then broadcasts the badge replace, but skips
   per-row replace. A user with the index page open will see the badge tick down
   but the row stays bold/unread until next reload. The web controller hits the
   same wall (line 70 of the controller — same `update_all`); §3 acknowledges
   this in its inline comment. Acceptable for v1; flag if MCP-driven mark-read
   becomes a hot path.
6. **[LOW] `NotificationsList` MCP tool silently coerces unknown `kind` /
   `severity` filter values to "no filter".** `notifications_list.rb:62-63` uses
   `&& Notification.kinds.key?(kind.to_s)` — an unknown enum value drops to "no
   filter applied" and the response includes everything. The web controller has
   the same posture (line 24-25). Spec 03 acceptance #29 ("`?kind=invalid`: 422
   OR ignored — architect picks: ignored") explicitly accepts this. Worth
   mentioning in the tool description so MCP callers don't wonder why a typo'd
   `kind=sync_errors` returned all rows.
7. **[LOW] In-app `urgent` severity badge color isn't visually distinguishable
   from `warn`.** Per master decision 2026-05-10 #2 + CLAUDE.md (red is
   destructive-only), in-app `urgent` reuses `--color-warn` (amber). This is
   correct per the contract but means the four severities collapse to three
   on-page colors (info / success / warn-and-urgent). The severity TEXT label
   still distinguishes them. Validate during the user walk-through that the
   chosen amber shade is intentional and not visually stale.

## Simplification suggestions (non-blocking)

1. **`NotificationsController#mark_read` and `#mark_all_read` duplicate the
   badge-broadcast turbo-stream block.** Lines 80-88 and 95-104 of
   `app/controllers/notifications_controller.rb` both render
   `turbo_stream.replace("notifications_badge", partial: "notifications/badge", …)`
   inside `format.turbo_stream`. Extract a `render_badge_replace` private method
   so the body of both branches reduces to a one-liner.
2. **Three MCP files duplicate `broadcast_badge_replace`.**
   `app/controllers/notifications_controller.rb:147`,
   `app/mcp/tools/notifications_mark_read.rb:85`, and
   `app/mcp/tools/notifications_mark_all_read.rb:36` all carry the identical
   `Turbo::StreamsChannel.broadcast_replace_to(...)` body wrapped in a
   `rescue StandardError`. A
   `Mcp::Tools::Concerns::NotificationBadgeBroadcaster` module (or a
   `NotificationBadgeBroadcaster` service) would consolidate it.
3. **`Discord#escape_body_preserving_links`, `Slack#rewrite_markdown_links`, and
   `Mcp#escape_body_preserving_links` share a near-identical loop-and-tokenize
   structure** (regex literal repeated three times — see `discord.rb:73`,
   `slack.rb:18` + `:92`, `mcp.rb:43`). Hoisting the tokenizer onto
   `NotificationFormatter` (e.g., `tokenize_links(text) { |kind, value| … }`
   yielding `:text` / `:link` segments) would let each formatter provide just
   the per-segment escape rule.
4. **`NotificationsMarkRead` accepts arrays only, but the web controller's
   `parse_ids` accepts comma-separated strings or arrays.** The MCP tool surface
   should ideally mirror the controller's tolerance for symmetry; the
   `notifications_mark_read.rb:50-55` strict-integer pass rejects the ergonomic
   `"1,2,3"` shape. Today the master-agent decision keeps the tool surface
   strict (and the input_schema declares `items: { type: "integer" }`) — if
   that's intentional, leave as-is and document the asymmetry on the tool.

## Manual test steps

These steps cover the full happy path AND the edge cases the spec acceptance
sections call out. Execute in order; if a step fails, stop and note which.

1. **Setup preamble — bring the stack up.**
   - **Action:** `bin/dev` (or your usual Foreman / Procfile runner). Wait until
     Puma is listening on `:3000` and Sidekiq has logged "Booted".
   - **Expected:** No exceptions in the Rails log; `/notifications` is reachable
     (anonymous → 302 to login).

2. **Setup preamble — seed a user + a Discord and Slack webhook.**
   - **Action:** `bin/rails credentials:edit --environment development` and
     ensure the `notifications:` block carries `discord_webhook_url:` and
     `slack_webhook_url:` (per Spec 01 manual playbook step 1). Optionally set
     `pito_avatar_url:` for the avatar smoke. In another terminal toggle the
     AppSetting flags:
     ```ruby
     bin/rails runner 'AppSetting.first.update!(discord_delivery_enabled: true, slack_delivery_enabled: true)'
     ```
   - **Expected:** No errors. `AppSetting.first.discord_delivery_enabled?`
     returns `true`.

3. **Setup preamble — seed a small set of notifications across kinds and
   severities.** Run from `bin/rails console`:

   ```ruby
   8.times do |i|
     Notification.create!(
       event_type: "video_published",
       kind: :video_published,
       severity: :info,
       title: "published: video #{i}",
       fires_at: Time.current,
       dedup_key: "manual-#{SecureRandom.hex(4)}",
       event_payload: {
         video_id: 999_000 + i,
         video_title: "video #{i}",
         channel_id: 1,
         channel_title: "test channel",
         published_at: Time.current.iso8601,
         watch_url: "https://youtu.be/abc#{i}"
       }
     )
   end
   Notification.create!(
     event_type: "sync_error", kind: :sync_error, severity: :urgent,
     title: "sync error: ChannelSync", fires_at: Time.current,
     dedup_key: "manual-sync-err",
     event_payload: { job_class: "ChannelSync", error_class: "RuntimeError",
                      error_message: "boom" }
   )
   ```

   - **Expected:** 9 rows in `Notification`, 9 unread.

4. **Discord shape smoke.**
   - **Action:**
     `bin/rails runner 'puts NotificationFormatter::Discord.payload_for(Notification.first).to_json'`
   - **Expected:** JSON contains `"username":"pito"`, `"content"`, and a
     single-element `"embeds"` with `title`, `description`, `color` (an int
     matching `5793266` / `5763719` / `16705372` / `15548997` per severity),
     `url`, `footer.text` shaped `<event_type> · <iso>`, and `timestamp`. If
     `pito_avatar_url` was configured in step 2, `avatar_url` is present;
     otherwise it's omitted entirely (NOT an empty string).

5. **Slack shape smoke.**
   - **Action:**
     `bin/rails runner 'puts NotificationFormatter::Slack.payload_for(Notification.first).to_json'`
   - **Expected:** JSON contains `"username":"pito"` and a three-element
     `"blocks"` array (`header` / `section` / `context`). The
     `section.text.text` ends with `\n\n<…|view in pito>` because the
     notification has a `url`.

6. **In-app shape smoke.**
   - **Action:**
     `bin/rails runner 'puts NotificationFormatter::InApp.payload_for(Notification.first).inspect'`
   - **Expected:** Hash with `:title`, `:body_html` (HTML-safe), `:url`,
     `:severity`, `:severity_class`, `:glyph`, `:kind`, `:fires_at_relative`,
     `:fires_at_iso`, `:read` (Boolean — internal — NOT a "yes"/"no" string).

7. **MCP shape smoke.**
   - **Action:**
     `bin/rails runner 'puts NotificationFormatter::Mcp.payload_for(Notification.first).inspect'`
   - **Expected:** Hash with `:id` (string), `:title`, `:body_md`, `:url`,
     `:severity`, `:kind`, `:fires_at_iso`, **`:read` is `"yes"` or `"no"`**
     (string per CLAUDE.md boundary rule).

8. **Truncation smoke.**
   - **Action:** `bin/rails runner` with:
     ```ruby
     n = Notification.create!(
       event_type: "sync_error", kind: :sync_error, severity: :info,
       title: "long body test", fires_at: Time.current,
       dedup_key: "manual-trunc-#{SecureRandom.hex(2)}",
       event_payload: { job_class: "X", error_class: "X",
                        error_message: "x" * 5000 }
     )
     d = NotificationFormatter::Discord.payload_for(n)
     puts d[:embeds].first[:description].length
     puts d[:embeds].first[:description].end_with?("…")
     ```
   - **Expected:** Length ≤ 4096, ends with `…` printed `true`.

9. **Escaping smoke (Discord).**
   - **Action:** `bin/rails runner` with:
     ```ruby
     n = Notification.create!(
       event_type: "video_published", kind: :video_published, severity: :info,
       title: "smuggle test", fires_at: Time.current,
       dedup_key: "manual-esc-#{SecureRandom.hex(2)}",
       event_payload: { video_id: 1, video_title: "*bold*",
                        channel_id: 1, channel_title: "ch",
                        published_at: Time.current.iso8601,
                        watch_url: "https://x" }
     )
     puts NotificationFormatter::Discord.payload_for(n)[:embeds].first[:description]
     ```
   - **Expected:** Output contains literal `\*bold\*` (backslash-escaped) —
     Discord won't render bold.

10. **Escaping smoke (in-app sanitization).**
    - **Action:** `bin/rails runner` with:
      ```ruby
      n = Notification.create!(
        event_type: "video_published", kind: :video_published, severity: :info,
        title: "smuggle script", fires_at: Time.current,
        dedup_key: "manual-script-#{SecureRandom.hex(2)}",
        event_payload: { video_id: 1, video_title: "<script>alert(1)</script>",
                         channel_id: 1, channel_title: "ch",
                         published_at: Time.current.iso8601,
                         watch_url: "https://x" }
      )
      puts NotificationFormatter::InApp.payload_for(n)[:body_html]
      ```
    - **Expected:** Output contains escaped `&lt;script&gt;` (NOT a raw
      `<script>` tag); `body_html.html_safe?` is `true`.

11. **Cleanup job smoke.**
    - **Action:** `bin/rails runner` with:
      ```ruby
      stale = Notification.create!(
        event_type: "video_published", kind: :video_published, severity: :info,
        title: "stale", fires_at: 30.days.ago,
        dedup_key: "manual-stale-#{SecureRandom.hex(2)}",
        event_payload: { video_id: 1, video_title: "stale",
                         channel_id: 1, channel_title: "ch",
                         published_at: 30.days.ago.iso8601,
                         watch_url: "https://x" }
      )
      stale.update_column(:in_app_read_at, 8.days.ago)
      puts "before: #{Notification.where(id: stale.id).count}"
      NotificationCleanupJob.perform_now
      puts "after: #{Notification.where(id: stale.id).count}"
      ```
    - **Expected:** `before: 1`, `after: 0`. Plus a Rails log line:
      `NotificationCleanupJob: deleted 1 read notification older than 7 days`.

12. **Sidekiq cron registration.**
    - **Action:** Open `http://localhost:3000/sidekiq/cron` (HTTP basic auth per
      the Sidekiq Web credentials block).
    - **Expected:** `notification_cleanup` entry at `30 3 * * *` mapped to
      `NotificationCleanupJob`.

13. **Run full RSpec on the notification surface.**
    - **Action:**
      ```bash
      bundle exec rspec \
        spec/services/notification_formatter \
        spec/services/notification_formatter_spec.rb \
        spec/requests/notifications_spec.rb \
        spec/system/notifications_index_spec.rb \
        spec/system/notifications_show_spec.rb \
        spec/system/notifications_badge_live_update_spec.rb \
        spec/system/notifications_dynamic_button_spec.rb \
        spec/system/notifications_modal_spec.rb \
        spec/views/notifications \
        spec/mcp/tools/notifications_list_spec.rb \
        spec/mcp/tools/notifications_unread_count_spec.rb \
        spec/mcp/tools/notifications_mark_read_spec.rb \
        spec/mcp/tools/notifications_mark_all_read_spec.rb \
        spec/jobs/notification_cleanup_job_spec.rb \
        spec/models/notification_spec.rb
      ```
    - **Expected:** **448 examples, 0 failures.**

14. **Rubocop on the notification surface.**
    - **Action:** Run rubocop against the notification ruby files (formatter,
      templates, controller, MCP tools, model, cleanup job, related specs). The
      reviewer ran 48 files on this surface.
    - **Expected:** No offenses.

15. **Brakeman.**
    - **Action:** `bundle exec brakeman -q -w2`.
    - **Expected:** 0 security warnings.

16. **MCP tool smoke from the rails console.**
    - **Action:**
      ```ruby
      bin/rails runner 'pp Mcp::Tools::NotificationsUnreadCount.call.content'
      ```
      (Expect a `Mcp::ToolAuth.require_scope!` error if you don't have an `app`
      scope active — the smoke is to confirm the scope gate works. To validate
      the happy path, exercise the tool through the MCP transport instead.)
    - **Expected:** Either a scope-error response object OR a JSON
      `{count: <int>}` payload matching the `Notification.unread.count` value.

## Cleanup

If you want to start over from a clean state:

```bash
bin/rails runner 'Notification.delete_all'
bin/rails runner 'AppSetting.first.update!(discord_delivery_enabled: false, slack_delivery_enabled: false)'
```

To reset the Sidekiq queue (drains pending `NotificationDeliver` jobs without
running them):

```bash
bin/rails runner 'Sidekiq::Queue.new("default").clear'
```

## User Validation

The notification surface IS the user-facing change here, so this section walks
through every UI surface that landed in the Spec 02 / Spec 03 / UX restructure
work. Step through in a browser; the page has no command-line prerequisites
beyond the dev server being up.

[ ] 1. **Notification badge — superscript shape.** Visit any page (e.g. `/`)
while at least one unread notification exists. The header nav shows
`[notifications]` immediately followed by a small superscript number (e.g.
`[notifications]³`). No surrounding brackets on the count, and the sup hugs the
top of the line.

[ ] 2. **Notification badge — hides at zero.** Mark every unread notification
read (use `[mark all as read]` on `/notifications`). The header nav collapses to
just `[notifications]` with NO superscript, NO trailing space, NO empty bracket.

[ ] 3. **Notifications index empty state.** Visit `/notifications` after
deleting all rows (`Notification.delete_all` from console). The page shows the
heading `notifications`, the muted caption "notifications are deleted 7 days
after being read.", the `[ ] unread` filter chip, and the body line
`no notifications yet.` (lowercase, period). No `[mark all as read]` button
appears.

[ ] 4. **Notifications index populated.** Re-create some notifications (run
manual step 3 above). Reload `/notifications`. Each row shows in this column
order: bulk-select checkbox (only on unread rows), glyph emoji, title, severity
badge (lowercase text), relative timestamp ("less than a minute ago"). Unread
rows render with bold titles; read rows render in muted gray.

[ ] 5. **Filter chip toggle.** Click `[ ] unread`. The URL changes to
`?filter=unread` and the chip flips to `[x] unread`. The list narrows to unread
rows only. Click the chip again. URL drops the param, chip flips back to
`[ ] unread`, all rows reappear.

[ ] 6. **Cleanup caption.** Confirm the "notifications are deleted 7 days after
being read." line is muted (gray), sits directly under the `notifications` H1,
and reads as a single sentence on one line on a typical desktop window.

[ ] 7. **Mark a single row read via bulk select.** Tick the leftmost checkbox on
one unread row. The button to the right of the filter chip flips its text from
`[mark all as read]` to `[mark 1 as read]`. Submit the button. The page reloads;
that row is now muted and its checkbox is gone (read rows omit the bulk
checkbox). The badge superscript decrements by 1.

[ ] 8. **Mark several rows read via bulk select.** Tick three unread rows. The
button now reads `[mark 3 as read]`. Submit. Three rows flip to muted gray and
lose their checkboxes; the badge decrements by 3.

[ ] 9. **Selecting all unread reverts to mark-all.** Tick every remaining unread
row's checkbox. The button text reverts to `[mark all as read]` (because
selected count equals total unread, the controller flips back to the canonical
mark-all path). Submit. All rows flip read; the badge disappears.

[ ] 10. **Modal-based detail view.** Re-create some notifications. On
`/notifications`, click any row's title. An in-page dialog opens centered on
screen with the detail content (title, severity badge, body, timestamp,
per-channel delivery state, action footer). The URL bar does NOT change. The
rest of the page sits underneath (dimmed by the native backdrop).

[ ] 11. **Modal close on click outside.** With the dialog open, click outside
the dialog (on the dimmed backdrop). The dialog closes; you're back on the
index. The URL bar still says `/notifications`.

[ ] 12. **Modal close on Escape.** Open the dialog again. Press Escape. The
dialog closes (native `<dialog>` behavior).

[ ] 13. **Modal `[ back ]` button.** Open the dialog. Click the `[back]`
bracketed link in the action footer. The dialog closes; you're back on the
index. (When you visit `/notifications/:id` directly without coming from the
index, the same `[back]` link navigates to `/notifications` instead of trying to
close a non-existent modal.)

[ ] 14. **Direct navigation to detail page works as a fallback.** Visit
`/notifications/:id` directly (copy a row's id from the rails console). The full
document renders the same detail content (title, severity, body, timestamp,
delivery state, footer). The page has NO open modal — it's a standalone detail
view.

[ ] 15. **Auto-mark-on-click via `[ open ]`.** Open a notification with a source
URL (`event_payload.watch_url` was set in step 3). The detail surface shows a
`[open]` link with the URL printed muted next to it. Click `[open]`. The browser
navigates to the source URL. Return to `/notifications` and confirm that row is
now read (muted; no checkbox).

[ ] 16. **Severity badges render for all four severities.** Create one
notification each at `info` / `success` / `warn` / `urgent` severity (via
`bin/rails console`). On the index, each row's severity badge text reads the
lowercase severity name. Confirm that `urgent` does NOT render in red — per the
design rule (red is destructive-only) it shares the amber `--color-warn` palette
with `warn`. Severity is still visually distinguishable via the badge TEXT.

[ ] 17. **Webhook misconfigured banner.** From the rails console, set a
notification's `last_error` to a non-blank string and ensure it's unread:
`Notification.first.update!(in_app_read_at: nil, last_error: "boom")`. Reload
`/notifications`. A muted banner appears above the list reading "webhook
delivery failing — see notification detail."

[ ] 18. **Per-channel delivery state on detail page.** Open the detail
modal/page for a notification. The "delivery state" block shows three lines:
`in_app: yes`, `discord: pending` or `discord: <iso-timestamp>` or
`discord: disabled`, and `slack: …` mirror. Confirm the appropriate state
matches your AppSetting flags + delivery progress.

[ ] 19. **Mark-read / mark-unread toggle in the detail view.** On a unread
notification's detail, click the `[mark read]` button in the action footer. The
footer's first button flips to `[mark unread]` and the index badge decrements
live (no full page reload). Click `[mark unread]`. The badge increments back;
the button label flips back to `[mark read]`.

[ ] 20. **Live badge update — open two browser tabs.** In tab A visit
`/notifications`; in tab B visit any other page (e.g. `/`). In tab A, click
`[mark all as read]`. In tab B, the header `[notifications]` superscript should
update live (within ~1 second) without a manual reload. (This requires the
Action Cable / Solid Cable transport to be running per `bin/dev`.)

[ ] 21. **Live row prepend — open the index then trigger a notification.** With
`/notifications` open in one tab, open another tab / console and create a fresh
notification:
`ruby     Notification.create!(event_type: "video_published", kind: :video_published, severity: :info,                          title: "live insert", fires_at: Time.current,                          dedup_key: "live-#{SecureRandom.hex(2)}",                          event_payload: { video_id: 1, video_title: "live insert",                                           channel_id: 1, channel_title: "ch",                                           published_at: Time.current.iso8601,                                           watch_url: "https://x" })     `
The new row appears at the top of the index without manual reload. The badge
superscript increments live.

[ ] 22. **No JS confirm / alert / prompt.** Spot-check across the surfaces:
clicking `[mark read]`, `[mark unread]`, `[mark all as read]`, `[open]`,
`[back]`, the row title, and the filter chip should NEVER pop a browser confirm
/ alert / prompt dialog. (CLAUDE.md hard rule.)

[ ] 23. **Pagination boundaries.** Bulk-create > 50 notifications. Visit
`/notifications`. The bottom of the list shows `[ next page ]` plus a "page 1 /
2" indicator. Click `[ next page ]`. The next 50 render; the bottom shows
`[ prev page ]` and the indicator updates to "page 2 / 2".

[ ] 24. **Sidekiq Web shows the cleanup cron registered.** Visit `/sidekiq/cron`
(HTTP basic auth from credentials). The `notification_cleanup` row appears with
cron `30 3 * * *` and class `NotificationCleanupJob`. (The Sidekiq Web admin is
gated by basic auth and is NOT linked from the app nav per CLAUDE.md.)
