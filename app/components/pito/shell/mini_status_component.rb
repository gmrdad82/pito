# frozen_string_literal: true

module Pito
  module Shell
    class MiniStatusComponent < ViewComponent::Base
      # @param mode [Symbol] one of :connection, :start
      # @param state [Boolean] connection state (true = connected)
      # @param notifications [Integer] notification count
      # @param show_notifications [Boolean] whether to render notification count
      def initialize(mode: :connection, state: true, notifications: 0, show_notifications: false)
        @mode = mode
        @state = state
        @notifications = notifications
        @show_notifications = show_notifications
      end

      def connection_label
        @state ? t("pito.shell.mini_status.connected") : t("pito.shell.mini_status.disconnected")
      end

      def connection_color
        @state ? "var(--accent-green)" : "var(--accent-red)"
      end
    end
  end
end
