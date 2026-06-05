# frozen_string_literal: true

module Pito
  module Sidebar
    module Notifications
      # Renders the notifications list for the sidebar overlay.
      #
      # Constructor:
      #   notifications — ActiveRecord relation or Array of Notification records,
      #                   already ordered (e.g. Notification.recent).
      #
      # Each row carries:
      #   - class "pito-notification-row" (distinct from .pito-conversation-row so
      #     resume_controller's arrow-nav does not treat notifications as conversations)
      #   - unread indicator: bright dot + bold message for unread; muted for read
      class Component < ViewComponent::Base
        def initialize(notifications:)
          @notifications = notifications.to_a
        end

        def render?
          true
        end

        def formatted_timestamp(notification)
          Pito::Formatter::CompactTimeAgo.call(notification.created_at)
        end

        attr_reader :notifications
      end
    end
  end
end
