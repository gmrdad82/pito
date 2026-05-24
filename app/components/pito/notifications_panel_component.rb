module Pito
  # Pito::NotificationsPanelComponent
  #
  # The notifications panel on Home (/). Manages Discord + Slack webhook
  # delivery channels for notification dispatching (per-channel webhook
  # URLs + "send all"/"daily digest" toggles).
  #
  # ## Kwargs
  #
  # @param discord_webhook [NotificationDeliveryChannel, nil]
  #   The Discord delivery channel record (may be nil if not configured).
  # @param slack_webhook [NotificationDeliveryChannel, nil]
  #   The Slack delivery channel record (may be nil if not configured).
  #
  # ## Cable channel
  #
  # `pito:home:notifications` — derived via `cable_channel_for(PANEL_NAME)`
  # from the `Tui::PanelBase` mixin. Broadcasts toggle changes + webhook
  # URL updates.
  #
  # ## Focusables
  #
  # Delegated to `SettingsHelper#notifications_focusables` (locked list):
  #   all, daily, discord_webhook, discord_update, discord_help,
  #   slack_webhook, slack_update, slack_help
  #
  # ## Composes
  #
  # - Form inputs for webhook URLs
  # - Tui::CheckboxComponent for toggles
  # - BracketedLinkComponent for [update] actions
  # - BracketedMutedLinkComponent for [help] actions
  #
  # ## Phase 2C (2026-05-23)
  #
  # Wired with the canonical `Tui::PanelBase` mixin. Cable channel is now
  # derived via `cable_channel_for(PANEL_NAME)` (canonical
  # `pito:<screen>:<panel>` grammar); the legacy `CABLE_CHANNEL` constant
  # is gone. Title resolves from `tui.home.panels.notifications.title`
  # ("notifications settings", distinct from the in-app feed panel) so
  # the future Ratatui client reads the same YAML.
  class NotificationsPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :notifications

    def initialize(discord_webhook:, slack_webhook:)
      @discord_webhook = discord_webhook
      @slack_webhook = slack_webhook
    end

    attr_reader :discord_webhook, :slack_webhook

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    def focusables
      [
        { key: "notifications_sync", style: :action },
        { key: "all",             style: :checkbox_label },
        { key: "daily",           style: :checkbox_label },
        { key: "discord_webhook", style: :input },
        { key: "discord_update",  style: :action },
        { key: "discord_help",    style: :action },
        { key: "slack_webhook",   style: :input },
        { key: "slack_update",    style: :action },
        { key: "slack_help",      style: :action }
      ]
    end

    def keybinds
      {}
    end

    # Phase 2C — feed only the key strings into panel_root_data. The
    # full hash list (with :style entries) is retained for legacy
    # consumers that still need per-element CSS styling.
    def focusable_keys
      focusables.map { |f| f.is_a?(Hash) ? f[:key] : f }
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusable_keys, keybinds: keybinds)
    end
  end
end
