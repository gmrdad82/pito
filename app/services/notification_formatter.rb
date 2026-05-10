# Phase 16 §2 — Notification formatter.
#
# Translates a `Notification` row into a per-channel payload. Four
# concrete formatters live under this namespace:
#
# - `NotificationFormatter::Discord` — JSON for the Discord webhook
#   endpoint. Rich embed with severity-mapped color + emoji-prefixed
#   content + footer / timestamp.
# - `NotificationFormatter::Slack` — JSON for the Slack incoming-webhook
#   endpoint. Block Kit (header + section + context).
# - `NotificationFormatter::InApp` — structured hash for §3's ERB views.
# - `NotificationFormatter::Mcp` — markdown + metadata for §3's MCP
#   tools. `read` is the string `"yes"` / `"no"` per the CLAUDE.md
#   external-boundary rule.
#
# Each formatter delegates per-event-type strings (title / body / url) to
# a `Templates::<Kind>` PORO. Templates read ONLY from
# `notification.event_payload` — the formatter is pure (input:
# Notification row; output: payload), idempotent, and round-trip-safe
# across source-row edits.
#
# Spec contract:
# `docs/plans/beta/16-notifications/specs/02-notification-formatter.md`.
module NotificationFormatter
  module_function

  # Severity → Discord embed color (decimal int) per Q4. The "no red"
  # design rule applies to in-app surfaces; Discord embed colors are
  # NOT pito's design surface and red is the universal "urgent" signal
  # there. The table below is verbatim from the spec.
  SEVERITY_COLORS = {
    "info"    => 5_793_266,    # 0x5865F2 muted blue
    "success" => 5_763_719,    # 0x57F287 green
    "warn"    => 16_705_372,   # 0xFEE75C amber
    "urgent"  => 15_548_997    # 0xED4245 red
  }.freeze

  # Severity → in-app severity_class. Note 2 lock: `urgent` maps to
  # `--color-warn` (amber), NOT red — `--color-error` (red) is reserved
  # for genuinely destructive actions per CLAUDE.md.
  IN_APP_SEVERITY_CLASSES = {
    "info"    => "notification-info",
    "success" => "notification-success",
    "warn"    => "notification-warn",
    "urgent"  => "notification-urgent"
  }.freeze

  # Event-type → Unicode emoji per Q6. Works in both Discord + Slack
  # without further encoding.
  EVENT_TYPE_EMOJI = {
    "video_published"                => "📺",
    "video_pre_publish_check_missed" => "⚠️",
    "game_release_upcoming"          => "🎮",
    "game_release_today"             => "🎮",
    "milestone_reached"              => "🏆",
    "calendar_entry_firing"          => "📅",
    "sync_error"                     => "🚨",
    "youtube_reauth_needed"          => "🔐"
  }.freeze

  # Stable fallback when the event type is not in the map (e.g., a
  # future kind that lands before the formatter's emoji entry does).
  DEFAULT_EMOJI = "•"

  # Truncation marker. Single Unicode ellipsis char (NOT three dots)
  # per master decision 2026-05-10 #8.
  ELLIPSIS = "…"

  # Discord per-field caps per Q8.
  DISCORD_CONTENT_LIMIT     = 2000
  DISCORD_TITLE_LIMIT       = 256
  DISCORD_DESCRIPTION_LIMIT = 4096

  # Slack per-field caps per Q8.
  SLACK_HEADER_LIMIT        = 150
  SLACK_SECTION_LIMIT       = 3000

  # ── helpers ───────────────────────────────────────────────────────

  def severity_color(severity)
    SEVERITY_COLORS.fetch(severity.to_s) do
      raise ArgumentError, "unknown severity: #{severity.inspect}"
    end
  end

  def emoji_for(event_type)
    EVENT_TYPE_EMOJI.fetch(event_type.to_s, DEFAULT_EMOJI)
  end

  # Per-channel link syntax per Q7. The formatter exposes one helper
  # so per-kind templates produce channel-correct markup without
  # caring which channel they end up on.
  def link(text, url, channel:)
    case channel.to_sym
    when :discord, :mcp, :in_app
      "[#{text}](#{url})"
    when :slack
      "<#{url}|#{text}>"
    else
      raise ArgumentError, "unknown channel: #{channel.inspect}"
    end
  end

  # Per-channel escape rules per Q11.
  #
  # - Discord: backslash-escape the markdown control characters.
  # - Slack: HTML-encode `&`, `<`, `>` per Slack mrkdwn.
  # - MCP: same set as Discord.
  # - In-app: no escape at this layer; ERB auto-escapes downstream.
  DISCORD_ESCAPE_PATTERN = /([*_~`|<>\[\]()\\])/
  SLACK_ESCAPE_REPLACEMENTS = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze
  SLACK_ESCAPE_PATTERN = /[&<>]/

  def escape_for(text, channel:)
    return "" if text.nil?

    case channel.to_sym
    when :discord, :mcp
      text.to_s.gsub(DISCORD_ESCAPE_PATTERN) { |c| "\\#{c}" }
    when :slack
      text.to_s.gsub(SLACK_ESCAPE_PATTERN, SLACK_ESCAPE_REPLACEMENTS)
    when :in_app
      text.to_s
    else
      raise ArgumentError, "unknown channel: #{channel.inspect}"
    end
  end

  # Truncate `text` so it fits within `limit` characters. Appends the
  # Unicode ellipsis when truncated. Never leaves a half-open `[`
  # mid-link — if a `[` is opened past the resulting cut without a
  # matching `)`, the helper rolls back to the previous balanced
  # boundary.
  def truncate_for(text, limit:)
    return "" if text.nil?

    str = text.to_s
    return str if str.length <= limit
    return ELLIPSIS if limit <= ELLIPSIS.length

    cut = str[0, limit - ELLIPSIS.length]
    cut = roll_back_unbalanced_link(cut)
    "#{cut}#{ELLIPSIS}"
  end

  # ISO-8601 UTC for machine-readable contexts; `time_ago_in_words`
  # for the in-app relative render.
  def format_timestamp(time, format)
    return nil if time.nil?

    case format.to_sym
    when :iso
      time.utc.iso8601
    when :relative
      ApplicationController.helpers.time_ago_in_words(time) + " ago"
    else
      raise ArgumentError, "unknown timestamp format: #{format.inspect}"
    end
  end

  # Resolve a Notification's `url` attribute to an absolute URL.
  # Leading-slash app paths get the install host prepended; absolute
  # http(s) URLs pass through; nil stays nil.
  def absolute_url(url)
    return nil if url.blank?
    return url if url.match?(%r{\Ahttps?://})

    "#{install_host}#{url}"
  end

  def install_host
    options = Rails.application.routes.default_url_options
    host = options[:host].presence || "app.pitomd.com"
    protocol = options[:protocol].presence || "https"
    "#{protocol}://#{host}"
  end

  def avatar_url
    Rails.application.credentials.dig(:notifications, :pito_avatar_url)
  end

  # Resolve the per-kind template class. Raises a clear error for an
  # unknown event_type rather than `NoMethodError` on `nil.title`.
  def template_for(notification)
    klass = Templates::REGISTRY[notification.event_type.to_s]
    raise ArgumentError, "no template registered for event_type: #{notification.event_type.inspect}" if klass.nil?

    klass.new(notification)
  end

  # ── private helpers ───────────────────────────────────────────────

  # If `cut` has a `[` opened past the last `)`, roll back to before
  # that `[` so the truncation does not leave a half-open link.
  def roll_back_unbalanced_link(cut)
    last_open = cut.rindex("[")
    last_close = cut.rindex(")")
    return cut if last_open.nil?
    return cut if last_close && last_close > last_open

    cut[0, last_open]
  end
end
