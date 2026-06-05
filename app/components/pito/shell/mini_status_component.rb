# frozen_string_literal: true

module Pito
  module Shell
    class MiniStatusComponent < ViewComponent::Base
      def initialize(mode: :connection, state: true, notifications: 0, show_notifications: false)
        @mode = mode
        @state = state
        @notifications = notifications
        @show_notifications = show_notifications
      end
    end
  end
end
