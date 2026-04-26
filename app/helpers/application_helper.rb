module ApplicationHelper
  def nav_link(label, path)
    if current_page?(path)
      tag.span("[ #{label} ]", style: "font-weight: bold; color: #1a1a1a;")
    else
      link_to(path, class: "bracketed") do
        "[ ".html_safe + tag.span(label, class: "bl") + " ]".html_safe
      end
    end
  end

  def breadcrumb(*crumbs)
    content_for(:breadcrumbs) do
      separator = tag.span(" / ", class: "text-muted")
      safe_join(crumbs.map.with_index { |crumb, i| breadcrumb_segment(crumb, last: i == crumbs.size - 1) }, separator)
    end
  end

  def view_trend_indicator(video)
    stats = video.video_stats.order(date: :desc).limit(7).pluck(:views)
    return tag.span("—", class: "indicator-flat") if stats.size < 2

    recent = stats.first(3).sum.to_f / [ stats.first(3).size, 1 ].max
    older = stats.last(3).sum.to_f / [ stats.last(3).size, 1 ].max
    return tag.span("—", class: "indicator-flat") if older.zero?

    change = ((recent - older) / older * 100).round(0)
    if change > 5
      tag.span("▲ #{change}%", class: "indicator-up")
    elsif change < -5
      tag.span("▼ #{change.abs}%", class: "indicator-down")
    else
      tag.span("— flat", class: "indicator-flat")
    end
  end

  def format_duration(seconds)
    return "—" unless seconds&.positive?
    hours = seconds / 3600
    mins = (seconds % 3600) / 60
    secs = seconds % 60
    if hours > 0
      format("%d:%02d:%02d", hours, mins, secs)
    else
      format("%d:%02d", mins, secs)
    end
  end

  private

  def breadcrumb_segment(crumb, last: false)
    label, path = crumb.is_a?(Array) ? crumb : [ crumb, nil ]
    truncated = truncate(label.to_s, length: 32)
    if last
      tag.span(truncated, style: "font-weight: bold; color: #1a1a1a;")
    else
      link_to(path || "#", class: "bracketed") do
        "[ ".html_safe + tag.span(truncated, class: "bl") + " ]".html_safe
      end
    end
  end
end
