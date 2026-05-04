module ApplicationHelper
  # Item 6 — Mobile nav single-char labels.
  # On desktop, the full word ("channels") renders. On mobile, a short
  # one-char label ("C") renders instead, toggled via the existing
  # .hide-mobile / .show-mobile utility classes (768px breakpoint). Drops
  # `[home]` on mobile entirely (the logo image already routes home) when
  # `short:` is the empty string — the helper short-circuits and returns
  # an empty wrapper that lays out only on desktop.
  def nav_link(label, path, short: nil)
    short = short.nil? ? label[0].to_s.upcase : short
    prefix = path.chomp("/")
    active = current_page?(path) || (prefix.present? && request.path.start_with?(prefix + "/"))

    safe_label = ERB::Util.html_escape(label)
    safe_short = ERB::Util.html_escape(short)
    label_html = if short.empty?
      # Desktop-only label. Wrap full text in .hide-mobile so the entire
      # nav link disappears on mobile (no empty `[]` flash).
      %(<span class="hide-mobile">#{safe_label}</span>).html_safe
    else
      %(<span class="hide-mobile">#{safe_label}</span><span class="show-mobile">#{safe_short}</span>).html_safe
    end

    if active
      content_tag(:span, class: "bracketed bracketed-active") do
        ("[" + label_html + "]").html_safe
      end
    else
      link_to(path, class: "bracketed") do
        ("[<span class=\"bl\">" + label_html + "</span>]").html_safe
      end
    end
  end

  def breadcrumb(*crumbs)
    content_for(:breadcrumbs) do
      render(BreadcrumbComponent.new(crumbs: crumbs))
    end
  end

  def view_trend_indicator(video)
    stats = video.video_stats.order(date: :desc).limit(7).pluck(:views)
    return render(StatusIndicatorComponent.new(kind: :flat, text: "—")) if stats.size < 2

    recent = stats.first(3).sum.to_f / [ stats.first(3).size, 1 ].max
    older = stats.last(3).sum.to_f / [ stats.last(3).size, 1 ].max
    return render(StatusIndicatorComponent.new(kind: :flat, text: "—")) if older.zero?

    change = ((recent - older) / older * 100).round(0)
    if change > 5
      render(StatusIndicatorComponent.new(kind: :up, text: "#{change}% ▲", sort_value: change))
    elsif change < -5
      render(StatusIndicatorComponent.new(kind: :down, text: "#{change.abs}% ▼", sort_value: change))
    else
      render(StatusIndicatorComponent.new(kind: :flat, text: "— flat", sort_value: 0))
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

  def format_video_watch_time(minutes)
    return "—" unless minutes&.positive?
    hours = (minutes / 60.0).round
    "#{number_with_delimiter(hours)}h"
  end

  def cancel_path_for(type)
    case type
    when "channel"    then channels_path
    when "video"      then videos_path
    when "project"    then projects_path
    when "collection" then collections_path
    when "game"       then games_path
    # Notes/timelines have no top-level user-facing index — fall back to
    # the projects index, the closest reasonable parent.
    when "note"       then projects_path
    when "timeline"   then projects_path
    else root_path
    end
  end

  def app_version
    @_app_version ||= Rails.root.join("VERSION").read.strip
  end

  def git_sha
    @_git_sha ||= begin
      sha = `git rev-parse --short HEAD 2>/dev/null`.strip
      sha.present? ? sha : nil
    end
  end

  def version_label
    sha = git_sha
    version = "v#{app_version}"
    if sha
      repo_url = "https://github.com/gmrdad82/pito/commit/#{sha}"
      "#{version} · #{link_to(sha, repo_url, target: '_blank', rel: 'noopener')}".html_safe
    else
      version
    end
  end

  def pane_breadcrumb_label(panes, show: 3, trunc_length: 14)
    return label_for_pane(panes.first) if panes.size == 1

    shown = panes.first(show)
    extra = panes.size - show

    labels = shown.map do |pane|
      truncate(label_for_pane(pane), length: trunc_length, omission: "…")
    end

    labels << "+#{extra} more" if extra > 0

    labels.join(" · ")
  end

  def label_for_pane(pane)
    return "unknown" if pane.nil?
    return pane.title if pane.respond_to?(:title) && pane.try(:title).present?
    return "##{pane.id}" if pane.respond_to?(:id)
    "unknown"
  end

  # Initial-paint palette for Chartkick / Chart.js. Mirrors the
  # --color-chart-1..5 CSS custom properties on the light theme. The
  # client-side `recolorCharts` reader (in `application.js`) replaces
  # these with the live CSS-var values shortly after first paint and
  # again on theme toggle, so this helper exists only to give the
  # initial pre-recolor frame design-system colors instead of Chart.js
  # defaults. Keep in sync with `--color-chart-N` in
  # `app/assets/tailwind/application.css`.
  CHART_PALETTE = %w[#0000cc #2e7d32 #8b5cf6 #d97706 #0891b2].freeze

  def chart_palette(count = CHART_PALETTE.length)
    CHART_PALETTE.first(count)
  end
end
