# frozen_string_literal: true

module Pito
  module Notifications
    # Maps a Notification#level to its cross-platform presentation: an emoji
    # prefix, a Slack attachment color (named or hex), and a Discord embed color
    # (integer). Unknown levels fall back to the neutral `info` style.
    module LevelStyle
      module_function

      STYLES = {
        "info"    => { emoji: "ℹ️",  slack: "#5170ff", discord: 0x5170ff },
        "success" => { emoji: "✅", slack: "good",    discord: 0x1abc9c },
        "warning" => { emoji: "⚠️", slack: "warning", discord: 0xf1c40f },
        "error"   => { emoji: "🛑", slack: "danger",  discord: 0xe74c3c }
      }.freeze

      DEFAULT = STYLES.fetch("info")

      def style_for(level)
        STYLES.fetch(level.to_s, DEFAULT)
      end

      def emoji(level)         = style_for(level)[:emoji]
      def slack_color(level)   = style_for(level)[:slack]
      def discord_color(level) = style_for(level)[:discord]
    end
  end
end
