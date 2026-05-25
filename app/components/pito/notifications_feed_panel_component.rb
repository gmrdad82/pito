module Pito
  # Pito::NotificationsFeedPanelComponent — home-screen in-app notifications
  # feed panel (clean slate, 2026-05-25).
  #
  # Renders the panel chrome with a title in the border and two bracketed
  # actions in the top-right action slot:
  #   [read]   — POST to /notifications_feed/mark_read   (marks all unread → read)
  #   [unread] — POST to /notifications_feed/mark_unread (marks all read → unread)
  #
  # Body content has been removed pending a full rebuild. The frame shell is
  # kept so Turbo redirects from the controller re-render cleanly.
  #
  # ## Kwargs
  #
  # None. All former kwargs (notifications:, filter:, unread_count:) are gone.
  #
  # ## Cable channel
  #
  # `pito:home:notifications_feed` — subscribes to live broadcasts.
  #
  # ## Focusables
  #
  # Ordered list:
  # - `mark_read`   (style: :action)
  # - `mark_unread` (style: :action)
  #
  # ## Palette commands
  #
  # `:` commands exposed:
  #   notifications_feed_mark_read   — scope: :home
  #   notifications_feed_mark_unread — scope: :home
  #
  # ## NOT the delivery-channel configuration panel
  #
  # That lives in `Pito::NotificationsPanelComponent`.
  class NotificationsFeedPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME    = :notifications_feed
    FRAME_ID      = "notifications_feed_panel".freeze
    CABLE_CHANNEL = "pito:home:notifications_feed".freeze

    def initialize; end

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    def focusables
      %w[mark_read mark_unread]
    end

    def keybinds
      {}
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: keybinds, panel_commands: panel_commands)
    end

    def panel_commands
      [
        {
          key:         "notifications_feed_mark_read",
          name:        I18n.t("tui.commands.notifications_feed_mark_read.name"),
          hint:        I18n.t("tui.commands.notifications_feed_mark_read.hint"),
          action_name: :notifications_feed_mark_read
        },
        {
          key:         "notifications_feed_mark_unread",
          name:        I18n.t("tui.commands.notifications_feed_mark_unread.name"),
          hint:        I18n.t("tui.commands.notifications_feed_mark_unread.hint"),
          action_name: :notifications_feed_mark_unread
        }
      ]
    end
  end
end
