# Security audit — Phase 16 Spec 01: Notification data + delivery

**Branch:** `main` **Spec:**
`docs/plans/beta/16-notifications/specs/01-notification-data-model-and-delivery.md`
**Audit run:** 2026-05-10

## Verdict

**MERGE WITH FIX-FORWARD.** No Critical findings. 1 High (F1 — protocol-relative
URL bypass) does not block Spec 01 merge but MUST be fixed before Spec 03 turns
the `url` column into rendered `href`s. 2 Medium on outbound HTTP hardening
should be fixed in Spec 01 since the cron is enabled.

## Findings by severity

- Critical: 0
- High: 1 (F1)
- Medium: 3 (F2, F3, F4)
- Low: 2 (F5, F6)
- Informational: 2 (F7, F8)

## F1. Protocol-relative URLs bypass app-path validation (HIGH)

- **Location:** `app/models/notification.rb:27`
- **Description:** `APP_PATH_PATTERN = %r{\A/[^\s]*\z}` accepts
  protocol-relative URLs `//evil.com/path`. Browsers resolve
  `<a href="//evil.com/x">` against current scheme. When Spec 03 lands the inbox
  UI rendering `notification.url`, an attacker who influences any notification
  source URL can craft an off-site redirect that looks like a Pito link.
- **Today:** Spec 01 source helpers set hardcoded URLs only — no live exploit
  path. The finding is about the validation contract Spec 03 / future sources
  rely on.
- **Recommendation:** Tighten regex:
  `APP_PATH_PATTERN = %r{\A/(?![/\\])[^\s]*\z}`. Add specs for `//evil.com/x`,
  `/\evil.com/x`, and ensure `/foo//bar` (interior `//`) is still allowed.
- **References:** OWASP Open Redirect (CWE-601), CWE-79.

## F2. Outbound webhook POST has no timeouts (MEDIUM)

- **Location:** `app/services/notification_delivery_channel/{discord,slack}.rb`
- **Description:** `Net::HTTP.new(uri.host, uri.port)` constructed without
  `open_timeout`, `read_timeout`, `write_timeout`, `ssl_timeout`. Defaults are
  60s — generous enough that a hung receiver ties up a worker. ×5 retries × N
  rows × 3 channel jobs/min — under worst case starves `default` queue.
- **Recommendation:**
  `http.open_timeout = 5; http.read_timeout = 10; http.write_timeout = 10; http.ssl_timeout = 5`.
  Hoist to `NotificationDeliveryChannel` base or shared `configure_http` helper.
- **References:** CWE-400.

## F3. No webhook host allowlist — credentials misconfig is SSRF vector (MEDIUM)

- **Location:** `app/services/notification_delivery_channel/{discord,slack}.rb`
- **Description:** `webhook_url` reads credentials and POSTs wherever the URL
  points. Spec calls for HTTPS Discord/Slack hosts only but no validation in
  code. Future Settings UI (deferred per Spec 01 §"Out of scope") makes this
  more meaningful. No SSRF guard against private/loopback (`127.0.0.1`,
  `10.0.0.0/8`, AWS metadata `169.254.169.254`).
- **Recommendation:** Allowlist:
  ```ruby
  DISCORD_HOSTS = %w[discord.com discordapp.com].freeze
  SLACK_HOSTS   = %w[hooks.slack.com].freeze
  def deliverable_url?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && allowed_hosts.include?(uri.host)
  rescue URI::InvalidURIError
    false
  end
  ```
  Integrate into `enabled?`. Log warning on configured-but-not-allowlisted.
- **References:** CWE-918, OWASP SSRF.

## F4. CHECK constraint conflicts with FK nullify cascade (MEDIUM)

- **Location:** `db/migrate/20260510170000_create_notifications.rb`
- **Description:**
  `CHECK (source_calendar_entry_id IS NOT NULL OR dedup_key IS NOT NULL)` + FK
  `ON DELETE: :nullify`. For calendar-derived notifications (dedup_key NULL),
  deleting a calendar entry tries to NULL out the FK, violating CHECK. DELETE on
  calendar_entries raises. Undocumented invariant that calendar entries with
  derived notifications can't be deleted.
- **Recommendation:** Either (1) `ON DELETE: :cascade` (notification dies with
  source), (2) drop the CHECK and rely on partial unique indexes + Rails-level
  validator, OR (3) `before_destroy` on CalendarEntry that backfills `dedup_key`
  before cascade nullify.

## F5. `last_error` stores 500 chars of attacker-influenceable response body (LOW)

- **Location:** `app/services/notification_delivery_channel.rb:53`
- **Description:** Response body persisted on 4xx. If F3 exploited,
  attacker-controlled host can stuff `last_error` with anything; will render in
  Spec 03 inbox UI.
- **Recommendation:** Truncate to ~200 chars; strip control chars; document Spec
  03 must use `<%= %>` escaping; consider dropping body entirely.

## F6. No structured forensic log of outbound webhook calls (LOW)

- **Location:** `app/services/notification_delivery_channel.rb`
- **Description:** Spec accepted-risk per Open Question #6. No log of
  URL/status/elapsed.
- **Recommendation:** `Rails.logger.info` per POST: notification_id, channel,
  response status, elapsed time. NOT the URL (token in path).

## F7. `retry_count` increment not atomic (INFORMATIONAL)

- **Location:** `app/services/notification_delivery_channel.rb:103-108`
- **Description:** Read-modify-write race possible across Discord+Slack jobs for
  same row. Counter undercount in rare cases. Not security; documented for
  follow-up when per-channel counters land.

## F8. `filter_parameters` doesn't include `webhook_url` (INFORMATIONAL)

- **Location:** `config/initializers/filter_parameter_logging.rb`
- **Description:** When future Settings UI ships, form params named
  `discord_webhook_url` / `slack_webhook_url` would land in production logs.
  Defense-in-depth: add `:webhook_url` proactively.

## Out-of-scope but noted

- Token soft-revoke (concern #4): not in Spec 01 codebase.
- Markdown subset / URL allowlist for `[text](url)`: ships in Spec 02 formatter.
- Audit log: deferred per Open Question #6.
- Idempotency: verified clean.
- Retry storm: verified clean.

## Blockers

None for Spec 01 itself. F2/F3 strongly recommended before next deploy. F1 must
land before Spec 03 ships UI rendering `notification.url`.
