# Phase 13.3 — View helpers for the analytics dashboard. Pure
# formatting + label conventions — no DB access here (that lives on
# the decorators / services).
module AnalyticsHelper
  WINDOW_SHORT = {
    "7d"       => "7d",
    "28d"      => "28d",
    "90d"      => "90d",
    "lifetime" => "lifetime"
  }.freeze

  WINDOW_LONG = {
    "7d"       => "last 7 days",
    "28d"      => "last 28 days",
    "90d"      => "last 90 days",
    "lifetime" => "lifetime"
  }.freeze

  # Numeric formatter dispatching by metric type. Counts render with
  # delimiters (1,234,567); durations render `m:ss` (or `h:mm:ss`
  # when ≥ 1 hour); ratios render `%` with two decimal places; money
  # renders `$x.xx`. Nil values render as `—`.
  def format_metric(value, type:)
    return "—" if value.nil?

    case type
    when :count, :integer
      number_with_delimiter(value.to_i)
    when :duration_seconds
      format_analytics_duration(value.to_f)
    when :ratio, :percentage
      number = value.to_f
      number *= 100.0 if number.abs <= 1.0
      "#{format('%.2f', number)}%"
    when :money
      "$#{format('%.2f', value.to_f)}"
    else
      value.to_s
    end
  end

  # Bracketed legend swatch — `[label]` rendered with the series'
  # color. Used inline in chart legends and in summary card labels.
  def bracketed_legend(label, color)
    content_tag(:span, "[#{label}]", class: "bracketed-active",
                style: "color: #{color};")
  end

  def analytics_window_label(window, long: false)
    table = long ? WINDOW_LONG : WINDOW_SHORT
    table.fetch(window.to_s, window.to_s)
  end

  # Human-friendly "synced 3 minutes ago" label per master-agent
  # decision 8. Returns "never synced" when the timestamp is nil.
  def data_freshness_label(timestamp)
    return "never synced" if timestamp.nil?
    "synced #{time_ago_in_words(timestamp)} ago"
  end

  # `MONETIZATION_ENABLED` gate. Dashboard sections that consume the
  # monetization columns hide themselves when this returns false
  # (master-agent decision 13). The flag is mirrored from
  # `AppSetting.get('monetization_enabled')` per spec 02.
  def monetization_enabled?
    AppSetting.get("monetization_enabled").to_s == "yes"
  end

  private

  def format_analytics_duration(seconds)
    seconds = seconds.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60
    if hours > 0
      format("%d:%02d:%02d", hours, minutes, secs)
    else
      format("%d:%02d", minutes, secs)
    end
  end
end
