module Pito
  # Pito::NotificationsFeedPanelComponent — home-screen in-app notifications
  # feed panel. Shows a table of notifications (unread first, then read,
  # ordered by created_at DESC within each group) with category filter chips
  # and bulk mark-read actions above the table.
  #
  # ## Kwargs
  #
  # @param notifications [ActiveRecord::Relation<Notification>, nil] pre-sorted
  #   relation (unread first + created_at DESC), limited to LIMIT rows. Fetched
  #   internally when nil.
  # @param filter [String] "unread" or "all" — derived from the
  #   `?notifications_feed_filter=` URL query param.
  # @param unread_count [Integer] total unread count for badge / label.
  # @param category [String, nil] active category filter: channel | game | system
  #   | manual | nil (all). Derived from `?notifications_category=` URL param.
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
  # ## Filter chips (category)
  #
  # 4 chips rendered by `Pito::Notifications::FilterChipsComponent`:
  #   [ ] channel  — Notification.category channel
  #   [ ] game     — Notification.category game
  #   [ ] system   — Notification.category system
  #   [ ] manual   — Notification.category manual
  #
  # Chips are mutually exclusive toggles. Active chip → category filter via
  # `?notifications_category=<value>`. Clicking an active chip deactivates it
  # (reverts to "all"). URL query param is the source of truth; no localStorage.
  #
  # ## Bulk actions
  #
  # `[read]` and `[un-read]` chips above the table. POST to
  # `/notifications_feed/bulk_read` and `/notifications_feed/bulk_unread`
  # with `ids[]` params from checked rows.
  # `[mark all read]` action POSTs to `/notifications_feed/mark_all_read`.
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
  #
  # ## Palette commands
  #
  # `:` commands exposed: mark_all_read_notifications_feed, filter_channel,
  # filter_game, filter_system, filter_manual — all scope: :home.
  class NotificationsFeedPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME    = :notifications_feed
    FRAME_ID      = "notifications_feed_panel".freeze
    CABLE_CHANNEL = "pito:home:notifications_feed".freeze
    LIMIT         = 20

    ALLOWED_CATEGORIES = %w[channel game system manual].freeze

    # Notification category → kind chip CSS class.
    # Maps the `category` enum string to the nf-kind-chip modifier.
    CATEGORY_CHIP_CSS = {
      "channel" => "nf-kind-chip--channel",
      "game"    => "nf-kind-chip--game",
      "system"  => "nf-kind-chip--system",
      "manual"  => "nf-kind-chip--system"
    }.freeze

    # Human-readable kind chip label (short, for the kind column).
    # Derived from category when kind-level lookup is not needed.
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

    def initialize(notifications: nil, filter: "all", unread_count: 0, category: nil)
      @notifications = notifications
      @filter        = filter.to_s == "unread" ? "unread" : "all"
      @unread_count  = unread_count.to_i
      @category      = ALLOWED_CATEGORIES.include?(category.to_s) ? category.to_s : nil
    end

    attr_reader :filter, :unread_count, :category

    def notifications
      @notifications ||= fetch_notifications
    end

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    # Chip variant for a given notification kind string.
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
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: keybinds, panel_commands: panel_commands)
    end

    # Phase C5 (2026-05-25) — `:` palette commands for the notifications feed
    # panel. Exposes mark-all-read and 4 category filter shortcuts.
    # scope: :home — notifications feed is a home-screen panel.
    def panel_commands
      [
        { key: "notifications_feed_mark_all_read",
          name: I18n.t("tui.commands.notifications_feed_mark_all_read.name"),
          hint: I18n.t("tui.commands.notifications_feed_mark_all_read.hint"),
          action_name: :mark_all_read_notifications_feed },
        { key: "notifications_feed_filter_channel",
          name: I18n.t("tui.commands.notifications_feed_filter_channel.name"),
          hint: I18n.t("tui.commands.notifications_feed_filter_channel.hint"),
          action_name: :click_focusable,
          args: { focusable: "filter_chip_channel" } },
        { key: "notifications_feed_filter_game",
          name: I18n.t("tui.commands.notifications_feed_filter_game.name"),
          hint: I18n.t("tui.commands.notifications_feed_filter_game.hint"),
          action_name: :click_focusable,
          args: { focusable: "filter_chip_game" } },
        { key: "notifications_feed_filter_system",
          name: I18n.t("tui.commands.notifications_feed_filter_system.name"),
          hint: I18n.t("tui.commands.notifications_feed_filter_system.hint"),
          action_name: :click_focusable,
          args: { focusable: "filter_chip_system" } },
        { key: "notifications_feed_filter_manual",
          name: I18n.t("tui.commands.notifications_feed_filter_manual.name"),
          hint: I18n.t("tui.commands.notifications_feed_filter_manual.hint"),
          action_name: :click_focusable,
          args: { focusable: "filter_chip_manual" } }
      ] + sync_pause_commands("home.notifications_feed", label: "notifications")
    end

    private

    def fetch_notifications
      scope = Notification.all
      scope = scope.unread if @filter == "unread"
      scope = scope.by_category(@category) if @category.present?
      scope.order(
        Arel.sql("CASE WHEN in_app_read_at IS NULL THEN 0 ELSE 1 END"),
        created_at: :desc
      ).limit(LIMIT)
    end
  end
end
