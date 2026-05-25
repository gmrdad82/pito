module Pito
  # Pito::ChannelsOverviewPanelComponent — home-screen panel showing a
  # compact sortable summary of all YouTube channels owned by the user.
  #
  # ## Purpose
  #
  # Renders a sessions-style table with one row per channel. Columns:
  # handle, subscriber count, total views, last published video (relative).
  # Sort is server-side via `sort_link_to`; default = `last_published_at DESC`
  # (most recently active channel first).
  #
  # ## kwargs
  #
  # - `channels:`    — ActiveRecord::Relation or Array of Channel records,
  #                    pre-sorted by the controller.
  # - `sort:`        — active sort key String (e.g. "last_published_at").
  # - `dir:`         — active sort direction String ("asc" / "desc").
  #
  # ## Focusables
  #
  # - `row_<channel.id>` — one focusable per channel row (style :row).
  #
  # ## Cable channel
  #
  # `pito:home:channels_overview` — panel-scoped stream per canonical grammar.
  #
  # ## TUI parity
  #
  # The Ratatui sibling reads `panel_root_data` attrs for focusables +
  # cable subscription. Do NOT inline data attrs in the template.
  #
  # ## Formatters
  #
  # - Subscriber / view counts  -> `Pito::Formatter::CompactCount`
  # - Last published timestamp  -> `Pito::Formatter::CompactTimeAgo`
  class ChannelsOverviewPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :channels_overview

    ALLOWED_SORTS = %w[handle subscriber_count view_count last_published_at].freeze
    ALLOWED_DIRS  = %w[asc desc].freeze
    DEFAULT_SORT  = "last_published_at"
    DEFAULT_DIR   = "desc"

    def initialize(channels: [], sort: DEFAULT_SORT, dir: DEFAULT_DIR)
      @channels = channels
      @sort     = ALLOWED_SORTS.include?(sort) ? sort : DEFAULT_SORT
      @dir      = ALLOWED_DIRS.include?(dir)   ? dir  : DEFAULT_DIR
    end

    attr_reader :channels, :sort, :dir

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    def focusables
      channels.map { |c| "row_#{c.id}" }
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {})
    end

    # Compact subscriber count via shared formatter.
    def format_subs(channel)
      Pito::Formatter::CompactCount.call(channel.subscriber_count)
    end

    # Compact view count via shared formatter.
    def format_views(channel)
      Pito::Formatter::CompactCount.call(channel.view_count)
    end

    # Relative time of the most recently published video on this channel.
    # Falls back to "never" when the channel has no published videos.
    # Casts the virtual column value to Time before passing to the formatter
    # because PostgreSQL returns virtual columns as raw strings when AR
    # does not know the column type statically.
    def format_last_published(channel)
      raw = channel.last_published_video_at
      time = raw.is_a?(Time) ? raw : (raw.present? ? Time.parse(raw.to_s) : nil)
      Pito::Formatter::CompactTimeAgo.call(time)
    rescue ArgumentError, TypeError
      Pito::Formatter::CompactTimeAgo.call(nil)
    end

    # Display handle (prefer @handle, fall back to title).
    def display_handle(channel)
      channel.handle.presence || channel.title.presence || "—"
    end
  end
end
