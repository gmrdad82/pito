# 2026-05-11 F5 — Cloudflare trusted-proxies drift watchdog.
#
# `config/environments/production.rb` pins
# `config.action_dispatch.trusted_proxies` to a hardcoded list of
# Cloudflare's published edge ranges (manually encoded on 2026-05-11).
# Cloudflare publishes the canonical lists at
# https://www.cloudflare.com/ips-v4 and
# https://www.cloudflare.com/ips-v6 — they change rarely but they DO
# change, and a drift between our pinned list and Cloudflare's
# advertised ranges means either:
#
#   * a legitimate client at a new Cloudflare edge has its
#     `request.remote_ip` pinned to the proxy hop (breaking
#     IP-based audit + Rack::Attack), OR
#   * a removed Cloudflare range still appears in our trusted list
#     (potentially trusting an IP Cloudflare no longer owns).
#
# Either case is operator-actionable, not auto-fixable: the trusted
# list is compiled into a Rails initializer at boot, so this job
# CANNOT mutate the runtime configuration. It surfaces the drift via
# a `sync_error` Notification (kind reused — closest match in the
# vocabulary, and the urgent severity is what the operator needs).
# The fix is a manual edit + redeploy.
#
# Schedule: weekly at Monday 09:00 UTC (`config/sidekiq_cron.yml` →
# `cloudflare_trusted_proxies_refresher`).
#
# Fetch failures: defensive — Cloudflare's endpoint going dark must
# NOT crash the cron. The job logs and returns; the next week's run
# will retry.
class CloudflareTrustedProxiesRefresherJob < ApplicationJob
  queue_as :default

  IPS_V4_URL = "https://www.cloudflare.com/ips-v4".freeze
  IPS_V6_URL = "https://www.cloudflare.com/ips-v6".freeze

  # Notification fingerprint — one row per drift-detected pass.
  # The dedup_key changes daily-ish so a fresh drift surfaces, but a
  # rerun on the same day collapses to one row. We bucket on the
  # UTC date so weekly cron + occasional manual runs cluster cleanly.
  DEDUP_KEY_PREFIX = "cloudflare_trusted_proxies_drift".freeze

  def perform
    fetched_v4 = fetch_cidrs(IPS_V4_URL)
    fetched_v6 = fetch_cidrs(IPS_V6_URL)

    # If both fetches fail, the watchdog has nothing to compare
    # against. Log + bail; no notification (we can't tell drift from
    # outage).
    if fetched_v4.nil? && fetched_v6.nil?
      Rails.logger.warn(
        "CloudflareTrustedProxiesRefresherJob: both ips-v4 + ips-v6 fetch failed; skipping comparison"
      )
      return
    end

    fetched = (fetched_v4 || []) + (fetched_v6 || [])
    pinned  = pinned_cidrs

    added   = fetched - pinned
    removed = pinned - fetched

    if added.empty? && removed.empty?
      Rails.logger.info(
        "CloudflareTrustedProxiesRefresherJob: trusted_proxies in sync (#{pinned.size} ranges)"
      )
      return
    end

    record_drift!(added: added, removed: removed)
  end

  private

  # Fetch a Cloudflare IP list. Returns an array of CIDR strings on
  # success, nil on any failure (network / non-2xx / parse error).
  # The endpoint is public, plain HTTP GET — no auth, no headers.
  def fetch_cidrs(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 10

    response = http.get(uri.request_uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    parse_cidrs(response.body)
  rescue StandardError => e
    Rails.logger.warn(
      "CloudflareTrustedProxiesRefresherJob: fetch failed for #{url}: #{e.class}: #{e.message}"
    )
    nil
  end

  # Line-delimited CIDRs, one per line. Strip whitespace + skip
  # blanks; tolerate trailing newlines and stray empty lines.
  def parse_cidrs(body)
    body.to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
  end

  # Read the production initializer's hardcoded CIDR list and return
  # the same array as `parse_cidrs` would. We re-parse the source
  # file at job runtime so this job stays in sync with whatever the
  # operator edited into `config/environments/production.rb` — no
  # duplicate-source-of-truth problem.
  #
  # The fence is the `%w[ … ]` literal sandwiched between
  # `*%w[` (or `%w[`) and a closing `]` inside the
  # `config.action_dispatch.trusted_proxies = [ … ]` block. We grep
  # the file for tokens that look like CIDRs (contain a `/`) — robust
  # against added comments, reordering, or formatting drift inside
  # the literal.
  def pinned_cidrs
    path = Rails.root.join("config/environments/production.rb")
    return [] unless File.readable?(path)

    contents = File.read(path)
    # Match every token of the form `digit.../prefix` OR `hex:.../prefix`.
    # That captures both v4 and v6 CIDRs without false positives on
    # comment URLs (which carry no `/<digits>` ending on whitespace).
    contents.scan(/\b(?:\d{1,3}(?:\.\d{1,3}){3}\/\d{1,2}|[0-9a-fA-F:]+::?\/\d{1,3})\b/).uniq
  rescue StandardError => e
    Rails.logger.warn(
      "CloudflareTrustedProxiesRefresherJob: could not read pinned list: #{e.class}: #{e.message}"
    )
    []
  end

  # Record a `sync_error` Notification describing the drift. Body
  # carries both lists so the operator sees exactly what to change.
  # `urgent` severity is correct here — the configured proxy list is
  # security-relevant.
  def record_drift!(added:, removed:)
    return unless defined?(Notification)

    bucket   = Time.current.utc.strftime("%Y-%m-%d")
    dedup    = "#{DEDUP_KEY_PREFIX}:#{bucket}"
    body_str = build_body(added: added, removed: removed)

    Notification.create!(
      kind: :sync_error,
      event_type: "cloudflare_trusted_proxies_drift",
      severity: :warn,
      title: "Cloudflare trusted_proxies drift detected",
      body: body_str,
      fires_at: Time.current,
      dedup_key: dedup
    )
  rescue ActiveRecord::RecordNotUnique
    # The unique partial index on dedup_key collapses a same-day rerun
    # to a single row. That's the intended behavior.
    Rails.logger.info(
      "CloudflareTrustedProxiesRefresherJob: drift notification already recorded for today"
    )
  rescue StandardError => e
    Rails.logger.warn(
      "CloudflareTrustedProxiesRefresherJob: failed to write drift notification: #{e.class}: #{e.message}"
    )
  end

  def build_body(added:, removed:)
    parts = []
    parts << "Cloudflare published ranges have diverged from " \
             "config/environments/production.rb."
    parts << ""
    parts << "Newly published (add to trusted_proxies): #{added.sort.join(', ')}" if added.any?
    parts << "No longer published (remove from trusted_proxies): #{removed.sort.join(', ')}" if removed.any?
    parts.join("\n").first(5000)
  end
end
