# frozen_string_literal: true

module Pito
  module Sidebar
    module Notifications
      # Renders the notifications list for the sidebar overlay.
      #
      # Constructor:
      #   notifications — ActiveRecord relation or Array of Notification records,
      #                   the FIRST page, already in panel_ordered order.
      #   next_cursor   — opaque cursor token for the next page (nil = last page).
      #                   Drives the generic pager sentinel.
      #
      # The wrapper mounts two controllers:
      #   pito--notifications-nav — arrow/click read-state nav (domain-specific)
      #   pito--list-pager        — generic keyset infinite-scroll (domain-agnostic)
      #
      # Rows render via the shared notifications/_row partial so the initial list
      # and the paginated append (index.turbo_stream.erb) never drift. Each row
      # keeps class "pito-notification-row" (distinct from .pito-conversation-row
      # so arrow-nav controllers don't cross-claim rows).
      class Component < ViewComponent::Base
        def initialize(notifications:, next_cursor: nil)
          @notifications = notifications.to_a
          @next_cursor   = next_cursor.presence
        end

        def render?
          true
        end

        # Built here (domain-coupled) and handed to the generic sentinel as a
        # plain URL string, so the sentinel/pager stay domain-agnostic.
        def next_url
          return nil if @next_cursor.nil?

          helpers.notifications_path(after: @next_cursor)
        end

        attr_reader :notifications
      end
    end
  end
end
