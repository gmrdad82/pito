module ApplicationHelper
  def nav_link(label, path)
    prefix = path.chomp("/")
    active = current_page?(path) || (prefix.present? && request.path.start_with?(prefix + "/"))
    render(BracketedLinkComponent.new(label: label, href: path, active: active))
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

  def format_watch_time(minutes)
    return "—" unless minutes&.positive?
    minutes = minutes.round
    hours = minutes / 60
    mins = minutes % 60
    if hours > 0
      "#{number_with_delimiter(hours)}h #{mins}m"
    else
      "#{mins}m"
    end
  end

  def cancel_path_for(type)
    case type
    when "channel" then channels_path
    when "video" then videos_path
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
end
