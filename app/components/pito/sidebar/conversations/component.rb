# frozen_string_literal: true

module Pito
  module Sidebar
    module Conversations
      # Renders a two-section conversation list for the sidebar.
      #
      # Constructor:
      #   groups        — Hash with :recent and :older arrays, as returned by
      #                   Conversation.recency_groups. Each element must respond
      #                   to #display_name, #uuid, and #last_activity_at.
      #   current_uuid: — optional UUID string to mark the active conversation.
      #
      # Each row carries:
      #   - class "pito-conversation-row" (stable hook for JS controllers)
      #   - class "is-current" when the row matches current_uuid
      #   - data-conversation-uuid attribute set to the conversation's uuid
      class Component < ViewComponent::Base
        def initialize(groups:, current_uuid: nil)
          @recent       = groups.fetch(:recent, [])
          @older        = groups.fetch(:older,  [])
          @current_uuid = current_uuid
        end

        def render?
          @recent.any? || @older.any?
        end

        def formatted_timestamp(conversation)
          Pito::Notifications::Formatter.conversation_timestamp(
            conversation.last_activity_at
          )
        end

        def current?(conversation)
          @current_uuid.present? && conversation.uuid == @current_uuid
        end

        def show_older_section?
          @older.any?
        end

        attr_reader :recent, :older
      end
    end
  end
end
