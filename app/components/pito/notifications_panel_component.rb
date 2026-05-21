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
  # `pito:home:notifications` — broadcasts toggle changes + webhook URL updates
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
  class NotificationsPanelComponent < ViewComponent::Base
    CABLE_CHANNEL = "pito:home:notifications".freeze

    def initialize(discord_webhook:, slack_webhook:)
      @discord_webhook = discord_webhook
      @slack_webhook = slack_webhook
    end

    attr_reader :discord_webhook, :slack_webhook

    def focusables
      [
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
  end
end
