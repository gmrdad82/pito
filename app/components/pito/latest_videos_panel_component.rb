module Pito
  # Pito::LatestVideosPanelComponent — home-screen panel showing the
  # most recent published videos across all owner channels, sortable
  # by publish date, title, channel, or view count.
  #
  # ## Kwargs
  #
  # @param videos [Array<Video>] pre-fetched, pre-sorted video rows
  #   (includes :channel association). Max N = LATEST_VIDEOS_LIMIT.
  # @param videos_sort [String] current sort column key
  #   (title|channel|views|published_at). Default "published_at".
  # @param videos_dir [String] "asc" or "desc". Default "desc".
  #
  # ## Columns
  #
  # thumbnail (small img or placeholder) / title / channel / views /
  # published at (relative). Sortable headers for title / channel /
  # views / published_at via `sort_link_to`.
  #
  # ## Focusables
  #
  # Each video row is a focusable of style `:row` keyed
  # `video_row_<id>`. j/k navigate rows. ENTER is wired as a stub
  # no-op (open video detail is out of scope for this round).
  #
  # ## Cable channel
  #
  # `pito:home:latest_videos` — derived via `cable_channel_for` from
  # `Tui::PanelBase`. The `Pito::PanelChannel` allowlist already
  # includes `latest_videos`. Broadcasts when a new video is published
  # (see `Video#after_commit` hooks).
  #
  # ## Turbo Frame
  #
  # Sort links target `FRAME_ID = "latest_videos_panel"` so column
  # header clicks refresh only this panel's table without touching
  # other home panels.
  #
  # ## Empty state
  #
  # When `videos` is empty, renders "no published videos yet." hint
  # inside the fieldset.
  #
  # ## TUI parity
  #
  # The Ratatui sibling reads the same panel data attrs emitted here
  # to derive its focusables list + cable subscription. Do NOT inline
  # data attrs in the template — emit via `panel_root_data`.
  class LatestVideosPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :latest_videos
    FRAME_ID   = "latest_videos_panel".freeze

    def initialize(videos: [], videos_sort: "published_at", videos_dir: "desc")
      @videos      = Array(videos)
      @videos_sort = videos_sort.to_s
      @videos_dir  = videos_dir.to_s
    end

    attr_reader :videos, :videos_sort, :videos_dir

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    # Ordered focusables: one `:row` per video.
    def focusables
      videos.map { |v| { key: "video_row_#{v.id}", style: :row } }
    end

    def focusable_keys
      focusables.map { |f| f.is_a?(Hash) ? f[:key] : f }
    end

    def keybinds
      {}
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusable_keys, keybinds: keybinds)
    end

    # Thumbnail URL for a video row. Returns nil when blank (template
    # renders a text placeholder instead of a broken <img>).
    def thumbnail_url_for(video)
      video.thumbnail_url.presence
    end

    # Compact human-readable view count (1.2k, 34k, 1.1m, etc.).
    def formatted_views(video)
      count = video.view_count.to_i
      return "0" if count.zero?

      helpers.number_to_human(
        count,
        units: { thousand: "k", million: "m", billion: "b" },
        format: "%n%u",
        precision: 1,
        significant: false
      )
    end

    # Relative published-at label. Falls back to em-dash when nil.
    def published_at_label(video)
      return "—" if video.published_at.nil?

      helpers.compact_time_ago(video.published_at)
    end
  end
end
