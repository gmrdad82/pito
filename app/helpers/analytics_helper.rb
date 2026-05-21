# Phase 13.3 — View helpers for the analytics dashboard. Pure
# formatting + label conventions — no DB access here (that lives on
# the decorators / services).
module AnalyticsHelper
  # Numeric formatter dispatching by metric type.
  # Delegates to Pito::Formatter::AnalyticsMetric — see that module for
  # full type list and examples. Nil values render as "—".
  def format_metric(value, type:)
    Pito::Formatter::AnalyticsMetric.call(value, type: type)
  end

  # Delegates to Pito::Formatter::AnalyticsWindowLabel.
  def analytics_window_label(window, long: false)
    Pito::Formatter::AnalyticsWindowLabel.call(window, long: long)
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
end
