module Pito
  # Pito::NotificationsFeedPanelComponent — home-screen in-app notifications
  # feed panel. Shows a table of notifications (unread first, then read,
  # ordered by created_at DESC within each group) with bulk mark-read /
  # mark-unread action chips above the table.
  #
  # ## Kwargs
  #
  # @param notifications [ActiveRecord::Relation<Notification>] pre-sorted
  #   relation (unread first + created_at DESC), limited to 20 rows.
  # @param filter [String] "unread" or "all" — current active filter, derived
  #   from the `?notifications_feed_filter=` URL query param.
  # @param unread_count [Integer] total unread count for badge / label.
  #
  # ## Columns
  #
  # checkbox | kind chip | title (tweet) | relative time
  #
  # ## Sort
  #
  # Server-side: unread first (CASE WHEN in_app_read_at IS NULL THEN 0 ELSE 1),
  # then created_at DESC within each group. No client-side sort toggle needed
  # for the feed — recency is the canonical order.
  #
  # ## Filter
  #
  # ONE `[ ] unread` checkbox above the table. Checked → ?notifications_feed_filter=unread.
  # Unchecked → all. URL query param, no localStorage, server-rendered.
  #
  # ## Bulk actions
  #
  # `[read]` and `[un-read]` chips above the table. POST to
  # `/notifications_feed/bulk_read` and `/notifications_feed/bulk_unread`
  # with `ids[]` params from checked rows. Handled by
  # `NotificationsFeedController`.
  #
  # ## Cable channel
  #
  # `pito:home:notifications_feed` — subscribes to live prepend broadcasts
  # so new notifications appear without page reload.
  #
  # ## Focusables
  #
  # ordered list (prepended by sync indicator key):
  # - `notifications_feed_sync` — sync indicator
  # - `select_all` (style: :row) — bulk-select header checkbox
  # - `row_<id>` (style: :row) — each notification row
  #
  # ## TUI parity
  #
  # The Ratatui sibling reads the same `data-tui-panel-*` attrs emitted via
  # `panel_root_data` to derive its focusables list + cable subscription.
  #
  # ## NOT the delivery-channel configuration panel
  #
  # That lives in `Pito::NotificationsPanelComponent`.
  class NotificationsFeedPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :notifications_feed
    FRAME_ID   = "notifications_feed_panel".freeze
    LIMIT      = 20

    # Notification kind → chip variant mapping.
    # channel-related kinds → videos accent (danger/red)
    # game-related kinds    → games accent (custom nf-kind--game)
    # manual                → amber / dracula-orange (warn)
    # system / default      → home accent / purple (custom nf-kind--system)
    KIND_CHIP_VARIANT = {
      "video_published"              => :danger,
      "video_pre_publish_check_missed" => :danger,
      "video_diff_detected"          => :danger,
      "youtube_reauth_needed"        => :danger,
      "import_job_completed"         => :danger,
      "game_release_today"           => :nf_game,
      "game_release_upcoming"        => :nf_game,
      "milestone_reached"            => :nf_system,
      "calendar_entry_firing"        => :nf_system,
      "sync_error"                   => :nf_system
    }.freeze

    # Human-readable chip labels per kind group.
    KIND_CHIP_LABEL = {
      "video_published"              => "video",
      "video_pre_publish_check_missed" => "video",
      "video_diff_detected"          => "video",
      "youtube_reauth_needed"        => "youtube",
      "import_job_completed"         => "import",
      "game_release_today"           => "game",
      "game_release_upcoming"        => "game",
      "milestone_reached"            => "system",
      "calendar_entry_firing"        => "system",
      "sync_error"                   => "system"
    }.freeze

    def initialize(notifications: nil, filter: "all", unread_count: 0)
      @notifications = notifications
      @filter        = filter.to_s == "unread" ? "unread" : "all"
      @unread_count  = unread_count.to_i
    end

    attr_reader :filter, :unread_count

    def notifications
      @notifications ||= fetch_notifications
    end

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    # Chip variant for a given notification kind string.
    # :nf_system and :nf_game are rendered via a dedicated CSS class
    # (not via Tui::ChipComponent VARIANTS — which only accepts its own
    # locked set). For those two we emit a raw span in the template.
    def kind_chip_variant(kind_str)
      KIND_CHIP_VARIANT.fetch(kind_str.to_s, :nf_system)
    end

    def kind_chip_label(kind_str)
      KIND_CHIP_LABEL.fetch(kind_str.to_s, "system")
    end

    # Maps variant symbol to CSS class suffix.
    def kind_chip_css(variant)
      case variant
      when :danger    then "nf-kind-chip--channel"
      when :nf_game   then "nf-kind-chip--game"
      when :nf_system then "nf-kind-chip--system"
      else                 "nf-kind-chip--system"
      end
    end

    def focusables
      keys = [ "notifications_feed_sync", "select_all" ]
      keys += notifications.map { |n| "row_#{n.id}" }
      keys
    end

    def keybinds
      {}
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: keybinds)
    end

    private

    def fetch_notifications
      scope = Notification.all
      scope = scope.unread if @filter == "unread"
      scope.order(
        Arel.sql("CASE WHEN in_app_read_at IS NULL THEN 0 ELSE 1 END"),
        created_at: :desc
      ).limit(LIMIT)
    end
  end
end
