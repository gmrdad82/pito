module Pito
  # Pito::NotificationsPanelComponent
  #
  # The notifications panel on Home (/). Manages Discord + Slack webhook
  # delivery channels for notification dispatching (per-channel webhook
  # URLs + "send all"/"daily digest" toggles). Each webhook row carries a
  # distinct label ("Discord webhook:" / "Slack webhook:") — no section
  # headings or hairline separators between the two rows.
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
  #   all              — "all notifications" checkbox label
  #   daily            — "daily digest" checkbox label
  #   discord_webhook  — Discord webhook URL input
  #   discord_update   — Discord [update] submit action
  #   discord_help     — Discord [help] link (opens webhook-help-modal)
  #   slack_webhook    — Slack webhook URL input
  #   slack_update     — Slack [update] submit action
  #   slack_help       — Slack [help] link (opens webhook-help-modal)
  #
  # ## Palette commands (`:` palette)
  #
  #   toggle_all               — clicks the "all notifications" checkbox
  #   toggle_daily_digest      — clicks the "daily digest" checkbox
  #   focus_discord_webhook    — focuses the Discord webhook URL input
  #   focus_slack_webhook      — focuses the Slack webhook URL input
  #   open_discord_help_dialog — focuses + clicks the Discord [help] link
  #   open_slack_help_dialog   — focuses + clicks the Slack [help] link
  #   sync_toggle_notifications — fires the sync toggle for this panel
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
  #
  # ## Phase C6 (2026-05-25)
  #
  # Added open_discord_help_dialog + open_slack_help_dialog palette commands.
  # Both dispatch :click_focusable on the respective help link focusable
  # (discord_help / slack_help), which triggers the webhook-help-modal
  # Stimulus controller's #open handler via a synthetic click.
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
      panel_root_data(name: PANEL_NAME, focusables: focusable_keys, keybinds: keybinds, panel_commands: panel_commands)
    end

    # Phase 1C (2026-05-24) — `:` palette commands for the notifications
    # settings panel. Toggle-all + daily-digest dispatch the existing
    # checkbox focusables via `:click`. Webhook focus commands shift the
    # cursor to the corresponding input. `[help]` opens the help dialog.
    # Filter / mark-all-read verbs do NOT belong here — those are the
    # notifications FEED panel's catalog (Phase 3 territory). See
    # `Pito::CommandPalette::Collector` for the merge contract.
    def panel_commands
      [
        { key: "toggle_all",
          name: I18n.t("tui.commands.toggle_all.name"),
          hint: I18n.t("tui.commands.toggle_all.hint"),
          action_name: :click_focusable,
          args: { focusable: "all" } },
        { key: "toggle_daily_digest",
          name: I18n.t("tui.commands.toggle_daily_digest.name"),
          hint: I18n.t("tui.commands.toggle_daily_digest.hint"),
          action_name: :click_focusable,
          args: { focusable: "daily" } },
        { key: "focus_discord_webhook",
          name: I18n.t("tui.commands.focus_discord_webhook.name"),
          hint: I18n.t("tui.commands.focus_discord_webhook.hint"),
          action_name: :focus_focusable,
          args: { focusable: "discord_webhook" } },
        { key: "focus_slack_webhook",
          name: I18n.t("tui.commands.focus_slack_webhook.name"),
          hint: I18n.t("tui.commands.focus_slack_webhook.hint"),
          action_name: :focus_focusable,
          args: { focusable: "slack_webhook" } },
        { key: "open_discord_help_dialog",
          name: I18n.t("tui.commands.open_discord_help_dialog.name"),
          hint: I18n.t("tui.commands.open_discord_help_dialog.hint"),
          action_name: :click_focusable,
          args: { focusable: "discord_help" } },
        { key: "open_slack_help_dialog",
          name: I18n.t("tui.commands.open_slack_help_dialog.name"),
          hint: I18n.t("tui.commands.open_slack_help_dialog.hint"),
          action_name: :click_focusable,
          args: { focusable: "slack_help" } },
        { key: "sync_toggle_notifications",
          name: I18n.t("tui.commands.sync_toggle.name", label: "notifications"),
          hint: I18n.t("tui.commands.sync_toggle.hint", label: "notifications"),
          action_name: :sync_toggle,
          args: { target: "home.notifications" } }
      ]
    end
  end
end
