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

  # Phase 14 §1 — time-to-beat formatter. IGDB returns seconds; we
  # display "Xh Ym" (or "—" when the field is nil / non-positive).
  def format_seconds(seconds)
    return "—" unless seconds.is_a?(Integer) && seconds.positive?
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    if hours.positive?
      minutes.zero? ? "#{hours}h" : "#{hours}h #{minutes}m"
    else
      "#{minutes}m"
    end
  end

  # Render a sortable column header as a `link_to` whose URL flips the
  # `sort` / `dir` query params while preserving every other URL param
  # (filter chips, saved-view selectors, etc.). The active sort column's
  # link carries a `.sort-asc` / `.sort-desc` class; the directional
  # arrow is rendered exclusively by CSS via the `::after`
  # pseudo-element on the parent `th.sortable` (see the `:has()` rule
  # in `app/assets/tailwind/application.css`). The link text itself is
  # ALWAYS just the bare label — active and inactive headers share the
  # same rendering pipeline so they line up at the pixel level.
  #
  # Used by the index pages whose order is driven by URL state — see
  # `ChannelsController` and `VideosController`. The `/projects` index
  # predates this helper and ships its own inline lambda; the helper is
  # written so it could absorb that view later without behavior change.
  #
  # `current_sort` / `current_dir` come from the controller (`@sort` /
  # `@dir`) so the indicator and the next-direction calculation reflect
  # what the page is actually rendering, not the raw `params`.
  #
  # `sort_param:` / `dir_param:` allow a page to host more than one
  # independently sortable table. The project show page, for example,
  # hosts both a footage table (default `sort` / `dir` params) and a
  # notes table (namespaced `notes_sort` / `notes_dir`) — passing
  # `sort_param: "notes_sort", dir_param: "notes_dir"` keeps each
  # table's URL state distinct while preserving the other's params on
  # each click.
  #
  # Dual-arrow fix (2026-05-06, refined 2026-05-06 polish-2): the active
  # column's link carries a `.sort-asc` / `.sort-desc` class. The
  # `th.sortable::after` neutral indicator is rendered by CSS
  # unconditionally on every sortable header; the
  # `:has(a.sort-asc | a.sort-desc)` rule in
  # `app/assets/tailwind/application.css` overrides the neutral
  # `▲\A▼` stack with a single directional glyph (`▲` or `▼`) on the
  # active column. The arrow is NOT rendered as inline text inside the
  # link — it rides exclusively through the CSS pseudo-element so the
  # active and inactive states share the same rendering pipeline (same
  # absolute-positioned `::after`, same `right: 1px` offset, same
  # font-size). Inline-text arrows produced misaligned glyphs and a
  # trailing space artefact next to active headers.
  #
  # `frame:` opts the link into Turbo Frame navigation. When set, the
  # link carries `data-turbo-frame="<frame-id>"` so Turbo only swaps
  # the matching `<turbo-frame>` element from the response (rather than
  # navigating the whole page) AND `data-turbo-action="advance"` so the
  # browser URL still updates and back/forward navigation works. The
  # frame on the page MUST share its `id` with the frame in the
  # response — otherwise Turbo aborts the swap and falls back to a
  # full-page navigation. Combined with morph (set globally in the
  # layout's `<meta name="turbo-refresh-method" content="morph">`), a
  # framed sort click preserves scroll position and form state while
  # only the frame's contents re-render.
  def sort_link_to(label, key, current_sort:, current_dir:, sort_param: "sort", dir_param: "dir", frame: nil)
    next_dir = (current_sort == key && current_dir == "asc") ? "desc" : "asc"
    active = current_sort == key
    data = {}
    if frame
      data[:turbo_frame] = frame
      data[:turbo_action] = "advance"
    end
    link_to(
      label,
      request.query_parameters.merge(sort_param => key, dir_param => next_dir),
      class: active ? "sort-#{current_dir}" : nil,
      data: data
    )
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

  # Server-side fixed-length middle truncation. Returns a single string
  # with a Unicode ellipsis (U+2026) joining the leading `head` chars
  # and the trailing `tail` chars; the input is returned as-is when it
  # is short enough that truncation would not actually shorten it
  # (i.e. `length <= head + 1 + tail`).
  #
  # Used by the `/channels` and `/videos` index URL cells to keep the
  # YouTube channel ID (the unique tail of
  # `https://www.youtube.com/channel/<id>`) visible while collapsing
  # the boilerplate prefix to `https://…<id>`. The footage filename
  # column shares the same shape via `FootageHelper#filename_truncate_middle`,
  # which delegates here. Caller chooses `head:` / `tail:`; nothing is
  # generic about the choice, so it lives at the call site.
  ELLIPSIS = "…".freeze # Unicode U+2026 — single character, NOT `...`.

  def middle_truncate(str, head:, tail:)
    s = str.to_s
    return "" if s.empty?
    return s if s.length <= head + 1 + tail
    "#{s[0...head]}#{ELLIPSIS}#{s[-tail..]}"
  end

  # Phase B post-commit (2026-05-04) — Note revamp. Server-side markdown
  # rendering used as the SSR fallback for the note editor's preview pane:
  # the page paints with the rendered HTML; `marked.js` then takes over on
  # `input` events client-side and updates the same node live. Commonmarker
  # already ships with the repo (Gemfile.lock); we use its plain
  # `to_html` with safe defaults — the `unsafe_` extensions are NOT enabled,
  # so raw HTML in the source is escaped.
  def render_markdown(text)
    return "".html_safe if text.blank?

    # `hardbreaks: true` makes a single `\n` render as `<br>` instead of
    # collapsing into the surrounding paragraph (CommonMark default). Matches
    # the `breaks: true` flag set on `marked` client-side so SSR and live
    # rendering produce identical output.
    Commonmarker.to_html(
      text.to_s,
      options: { render: { hardbreaks: true } }
    ).html_safe
  end
end
