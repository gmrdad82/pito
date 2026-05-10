# Security review — Phase 16 Spec 02 (formatter) + Spec 03 (UI + 4 MCP tools)

**Branch:** `main` **Specs:**
`docs/plans/beta/16-notifications/specs/02-notification-formatter.md`,
`docs/plans/beta/16-notifications/specs/03-notification-ui-and-mcp-tools.md`
**Reviewer playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-16-spec-02-and-03-notifications-formatter-and-ui.md`
**Audit run:** 2026-05-10

## Verdict

**CLEAR TO MERGE.** No Critical / High findings. Three Medium findings on
defense-in-depth (URL-scheme allowlist on link-bearing event_payload keys,
rate-limit on bulk mark-read collection actions, MCP outbound markdown URL
allowlist), four Low findings, three Informational. The notification surface
honours the Phase 16 Spec 01 audit closeout (F1 protocol-relative regex tighten,
F2 webhook timeouts, F3 host allowlist) and inherits Sessions::AuthConcern +
CSRF correctly. Single-shared-inbox semantics (Spec 01 Q1) collapse classical
IDOR vectors by design.

## Findings by severity

- Critical: 0
- High: 0
- Medium: 3 (F1, F2, F3)
- Low: 4 (F4, F5, F6, F7)
- Informational: 3 (F8, F9, F10)

## F1. In-app `event_payload` link URLs are not scheme-validated (MEDIUM)

- **Location:** `app/services/notification_formatter/in_app.rb:46-65`
  (`render_body_html`), `app/services/notification_formatter/templates/*.rb`
  (the URL fields inside `[text](url)` markdown).
- **Description:** Every per-event-type template substitutes `event_payload`
  values straight into `[watch on youtube](#{watch_url})` /
  `[igdb](#{igdb_url})` markdown — see `VideoPublished#body` line 21,
  `VideoPrePublishCheckMissed#body` line 20, `GameReleaseUpcoming#body` line 30,
  `GameReleaseToday#body` line 18, `YoutubeReauthNeeded#body` line 17. The InApp
  formatter runs the rendered HTML through Loofah's
  `Rails::Html::SafeListSanitizer`, which scrubs `javascript:` and `vbscript:`
  per Loofah's default `ACCEPTABLE_PROTOCOLS`. **But**: Loofah's default
  allowlist includes `data:`, `mailto:`, `tel:`, `sms:`, `xmpp:`, `feed:`,
  `irc:`, and ~20 more. Today's source helpers (Phase 12 / 13 / 15) write only
  YouTube / IGDB / pito paths, so there is no live exploit, but a future source
  helper that denormalizes any user-controllable URL (e.g. a channel
  description, video description, or third-party data ingestion) would land an
  unvalidated `data:image/svg+xml;base64,...` or `mailto:?subject=…` link in the
  in-app body without an enforcement layer.
- **Recommendation:** Either (a) tighten Loofah's allowlist in `InApp#sanitizer`
  to `%w[http https]` only — pass `scrubber:` or override `ALLOWED_PROTOCOLS`
  via a per-instance subclass — OR (b) validate URLs at the formatter layer
  before they enter `[text](url)`. Option (a) is the smaller change. Recommend:
  ```ruby
  class StrictScrubber < Loofah::Scrubber
    def scrub(node)
      return CONTINUE unless node.element?
      node.attributes.each do |name, attr|
        next unless %w[href src].include?(name)
        uri = attr.value.to_s.downcase
        next if uri.start_with?("/", "http://", "https://")
        node.remove_attribute(name)
      end
      CONTINUE
    end
  end
  ```
  And in `InApp#sanitizer` pass `scrubber: StrictScrubber.new`. The MCP surface
  inherits the same fix-forward (see F2).
- **References:** OWASP XSS Cheat Sheet (URL contexts), CWE-79, Loofah source
  `lib/loofah/html5/safelist.rb:983`.

## F2. MCP `body_md` link URLs are passed through unsanitized (MEDIUM)

- **Location:** `app/services/notification_formatter/mcp.rb:34-62`
  (`escape_body_preserving_links`).
- **Description:** The MCP formatter backslash-escapes Discord-style markdown
  control chars in the surrounding text but the URL inside `[text](url)` is
  emitted **verbatim**. `escape_for(... channel: :mcp)` is applied to the link
  text only — the URL captured by `match[2]` is concatenated directly into the
  output buffer (line 56). A YouTube `watch_url` or IGDB URL containing
  `javascript:`, `data:text/html,...`, or any spoofing scheme reaches the MCP
  host renderer untouched. Whether the renderer (Claude.ai chat, Claude Mobile,
  third-party MCP UI) follows it depends on that renderer's posture, but pito
  has emitted it.
- **Today:** Source helpers write hardcoded YouTube / IGDB URLs only. Live
  exploit absent. Same forward-looking concern as F1.
- **Recommendation:** Mirror F1's scheme allowlist at the MCP layer. Reject or
  strip URLs that are not `http(s):` OR a leading-slash app path. The Discord
  formatter has the same shape (`discord.rb:64-92`) — apply the same allowlist
  there too; Discord's own renderer already strips unsupported protocols, but
  defense-in-depth is cheap.
- **References:** CWE-79, OWASP A03 Injection.

## F3. No rate limit on `mark_all_read` / `mark_read` collection endpoints (MEDIUM)

- **Location:** `app/controllers/notifications_controller.rb:63-105`,
  `config/initializers/rack_attack.rb`.
- **Description:** `PATCH /notifications/mark_read` and
  `PATCH /notifications/mark_all_read` issue an `update_all` over
  `Notification.unread` plus a Turbo Stream broadcast. `rack_attack.rb`
  rate-limits failed-auth + OAuth token endpoints but no rule covers
  authenticated bulk operations on notifications. An authenticated user
  (single-tenant install) hammering `mark_all_read` would thrash the
  `notifications_badge` broadcast and the `update_all` query. Inside the trust
  boundary (every authenticated user has full install access by Spec 01 Q1) this
  is a denial-of-service from a logged-in actor, not from an anonymous attacker
  — but the broadcast amplifies every call to every connected ActionCable
  subscriber.
- **Recommendation:** Add a `Rack::Attack.throttle` per-user (or per-IP) for
  `PATCH /notifications/mark_read*` paths. Example:
  ```ruby
  Rack::Attack.throttle("notifications/mark_read", limit: 60, period: 1.minute) do |req|
    req.path =~ %r{\A/notifications/(mark_read|mark_all_read)\z} && req.ip
  end
  ```
  Choose limits that allow rapid mark-N-as-read clicking but cut off scripted
  spam.
- **References:** CWE-770 (Allocation of Resources Without Limits), OWASP
  API4:2023 Unrestricted Resource Consumption.

## F4. Loofah-stripped attributes do not strip the surrounding `<a>` shell (LOW)

- **Location:** `app/services/notification_formatter/in_app.rb:60-65`.
- **Description:** When Loofah rejects an `href` (e.g. `javascript:alert(1)`)
  via `scrub_uri_attribute`, it removes the **attribute** only; the empty
  `<a></a>` element stays in the DOM. The detail page renders an underlined-blue
  "watch on youtube" link that goes nowhere. Not a security issue, but UX-broken
  in a way users may mistake for a Pito bug. The same applies to the MCP
  formatter when F2 is fixed — strip both URL and the surrounding markdown
  wrapping.
- **Recommendation:** After sanitize, post-process `with_links` to remove any
  `<a>` whose `href` is absent. Or, validate the URL **before** writing the
  `<a>` tag in `render_body_html`. Pre-validation is cleaner.
- **References:** N/A (UX-correctness / defense-in-depth).

## F5. `notification_modal_controller#open` reads `href` from clicked element without validation (LOW)

- **Location:**
  `app/javascript/controllers/notification_modal_controller.js:40-53`.
- **Description:** `open()` calls `anchor.getAttribute("href")` on the clicked
  link and assigns it to `frameTarget.setAttribute("src", url)`. The Turbo Frame
  then fetches whatever same-origin path the href points at. In the rendered
  template this is always `notification_path(notification)` (server-built,
  safe), but the controller does not constrain the URL to a same-origin
  notifications path. A future template re-use that wires up
  `data-action="click->notification-modal#open"` on a different link would
  silently render an arbitrary page inside the dialog. Cross-origin URLs would
  be refused by Turbo Frame's same-origin policy, so the worst case is opening
  an unintended same-origin page inside the modal.
- **Recommendation:** In `open()`, parse `url` and bail when the path does not
  match `^/notifications/\d+$`. Single-line guard. Documents the contract.
- **References:** CWE-601 (Open Redirect — adjacent class), defense-in-depth.

## F6. `notification.url` rendered as `link_to` text shows the raw URL (LOW)

- **Location:** `app/views/notifications/show.html.erb:50-58`.
- **Description:** The detail page renders
  `<span class="text-muted"><%= @notification.url %></span>` next to the
  `[open]` link. The URL is validated as either absolute HTTP(S) or a
  leading-slash app path (model `url_is_well_formed_when_present` — Spec 01 F1
  fix). The display itself is ERB-escaped (default `<%= %>`) so no HTML
  injection. **But**: a long absolute URL containing Unicode RTL marks or
  look-alike Punycode hosts (e.g. `аpp.pitomd.com` with Cyrillic `а`) appears
  verbatim on the detail page next to the legit `[open]` link. This is a
  phishing-display concern, not an injection. The template surface where this
  matters is any future "open the URL" path where the URL itself is
  user-influenceable.
- **Recommendation:** Add a Unicode-confusable check on URL display (e.g.
  warn/highlight when the host contains non-ASCII) OR Punycode-encode the host
  for display via Addressable's IDN handling. Low priority while source helpers
  write hardcoded URLs only.
- **References:** CWE-1007 (Insufficient Visual Distinction of Homoglyphs), IDN
  homograph attack class.

## F7. `notifications_dynamic_button_controller` builds URL without `encodeURIComponent` (LOW)

- **Location:**
  `app/javascript/controllers/notifications_dynamic_button_controller.js:51`.
- **Description:**
  `const url = ${this.markReadUrlValue}?ids=${selected.join(",")}` concatenates
  checkbox `value` attributes into the URL without `encodeURIComponent`. Today
  the model only stores integer IDs and the bulk-select component renders them
  verbatim, so there is nothing to encode. If a future change introduces
  non-integer notification IDs (UUIDs, slugs) the URL construction would
  silently emit raw characters that break query-string parsing or carry meaning.
  The server-side `parse_ids` strips non-integers defensively (controller line
  137-144) — this is purely a client-side hygiene gap.
- **Recommendation:** Use `encodeURIComponent(selected.join(","))` or build with
  `URLSearchParams`. One-line fix.
- **References:** Defensive coding only.

## F8. `event_payload` carries raw user-supplied strings; size cap relies on enum integrity (INFORMATIONAL)

- **Location:** `app/services/notification_formatter/templates/*.rb`,
  `app/services/notification_payload_builder.rb` (Spec 01 surface).
- **Description:** The formatter trusts `event_payload` to be small and
  well-formed because Spec 01's `NotificationPayloadBuilder` denormalizes source
  rows at insert time. There is no schema-level size cap on `event_payload`
  (jsonb) and no per-key length cap on `video_title` / `channel_title` /
  `description` etc. inside the jsonb blob. The `truncate_for` helpers cap
  **final output**, but a 1 MB `event_payload[:description]` runs through
  `escape_for` / `rewrite_markdown_links` (a regex scan + character-by-character
  buffer build) before truncation. Worst-case latency, not an exploit.
- **Recommendation:** Document in Spec 01's `NotificationPayloadBuilder` that
  per-key strings should be pre-trimmed to ~5 KB before insert.
- **References:** CWE-400 (Resource Exhaustion).

## F9. Discord/Slack outbound bodies have no max-size cap (INFORMATIONAL)

- **Location:** `app/services/notification_delivery_channel/{discord,slack}.rb`,
  `app/services/notification_formatter/{discord,slack}.rb`.
- **Description:** The formatter caps per-field strings (Discord 256/4096/2000;
  Slack 150/3000) but does not cap the **JSON body** as a whole. Both Discord
  and Slack reject bodies > 8 KB / 4 KB respectively at the API layer with a 4xx
  that the channel records as terminal failure. Worst case is a wasted POST, not
  data loss. The HTTP timeouts (Spec 01 F2 fix, 5s open / 10s read / 10s write /
  5s ssl) bound the impact further.
- **Recommendation:** None today. Track if future templates approach the
  per-channel envelope limit.
- **References:** N/A — informational.

## F10. Turbo Stream subscription is signed but install-wide stream names are stable across all users (INFORMATIONAL)

- **Location:** `app/views/layouts/application.html.erb:100`,
  `app/views/notifications/index.html.erb:23`.
- **Description:** Both `notifications_badge` and `notifications_index` streams
  use stable string names (not per-user). Turbo's `StreamsChannel#subscribed`
  verifies the HMAC-signed stream name via `Turbo.signed_stream_verifier` — only
  clients who got the signed name from an authenticated page render can
  subscribe. Per single-shared-inbox semantics (Spec 01 Q1) every authenticated
  user receives the install-wide count broadcast intentionally. This is the
  right shape today. **But**: the signed stream name `notifications_badge` is
  the same string for every user, so the signed token derived from it is
  identical for every user. If pito ever pivots to per-user inboxes, the stream
  naming pattern must switch to `[user, :notifications_badge]` so subscriptions
  scope to the authenticated user.
- **Recommendation:** None today (matches Spec 01 Q1 + Q10 of Spec 03). Flag in
  `docs/plans/beta/16-notifications/` follow-ups if multi-user isolation is ever
  re-introduced.
- **References:** Architectural note only.

## Out-of-scope but noted

- **Spec 01 follow-ups already merged.** F1 (protocol-relative URL regex
  tighten), F2 (webhook timeouts), F3 (host allowlist) are verified in source:
  `notification.rb:32-33` carries the tightened
  `APP_PATH_PATTERN = %r{\A/(?![/\\])[^\s]*\z}`,
  `notification_delivery_channel.rb:103-109` carries the 5s/10s/10s/5s
  `configure_http` helper, and
  `notification_delivery_channel/{discord,slack}.rb` both implement
  `deliverable_url?` with `DISCORD_HOSTS` / `SLACK_HOSTS` allowlists.
- **TLS verify.** `Net::HTTP` with `use_ssl = true` defaults to `VERIFY_PEER`.
  `notification_delivery_channel/{discord,slack}.rb` does not weaken this (no
  `verify_mode` overrides). Outbound TLS is enforced.
- **CSRF.** `NotificationsController` inherits `ApplicationController`'s CSRF
  protection (Rails 8 default). `notification_link_controller.js` sends
  `X-CSRF-Token` from the `meta[name=csrf-token]` value. The fire-and-forget
  keepalive PATCH does not bypass CSRF — it sets the header.
- **SQL injection.** All three filter params (`filter`, `kind`, `severity`) are
  whitelisted via `FILTER_VALUES.include?` etc. before hitting any ActiveRecord
  where-clause. `params[:page]` runs `to_i`. `parse_ids` strict integer
  coercion. MCP `notifications_mark_read` strict `raw.match?(/\A\d+\z/)`. No
  raw-SQL string interpolation in any notification controller / tool path.
- **Cleanup-job boundary.**
  `Notification.where("in_app_read_at IS NOT NULL AND in_app_read_at < ?", cutoff).delete_all`.
  Unread rows are filtered out by the explicit `IS NOT NULL` clause; a user
  marking-unread within 7 days resets `in_app_read_at` to NULL and the row
  becomes immune to the next sweep. Mark-unread is reversible before the cutoff.
  Soft-cancel boundary correct.
- **Modal IDOR.** Single-shared-inbox model (Spec 01 Q1) collapses the classical
  IDOR scope: every authenticated user sees every notification by design. The
  Turbo Frame `notification_detail_frame` loads `/notifications/:id`, which
  honors `Sessions::AuthConcern` (auth required) and renders
  `Notification.find(params[:id])` (404 on unknown id via
  `ApplicationController#render_not_found`). No cross-tenant leak.

## Quality gate evidence

- **Security static analysis (strict).** `bundle exec brakeman -q -A -w1` was
  run against the notification surface; **0 new security warnings**. This
  matches the reviewer's `-w2` clean result and confirms no high-confidence
  findings at the stricter warning level.
- **Dependency audit.** `bundle exec bundle-audit check --update` returns **no
  vulnerabilities found** (reviewer playbook line 41 confirms).
- **/security-review summary.** The slash command's scoped review of the diff
  surfaces no Critical or High findings on the formatter, controller, views, or
  MCP tools. The Medium findings above are forward-looking defense-in-depth
  concerns that the slash command flags as defense-in-depth rather than
  vulnerabilities.
- **Notification-surface RSpec.** 448 examples, 0 failures (reviewer playbook).
  Confirms the formatter escape paths, the cleanup-job boundary, the MCP scope
  guards, and the controller's filter whitelists all carry test coverage.
