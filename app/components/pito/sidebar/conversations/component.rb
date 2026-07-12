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
        # @param next_cursor [String, nil] opaque keyset token for the next
        #   /resume page — nil renders no pager (whole list fits page 1).
        def initialize(groups:, current_uuid: nil, next_cursor: nil)
          @recent       = groups.fetch(:recent, [])
          @older        = groups.fetch(:older,  [])
          @current_uuid = current_uuid
          @next_cursor  = next_cursor
        end

        attr_reader :next_cursor

        def render?
          @recent.any? || @older.any?
        end

        def formatted_timestamp(conversation)
          Pito::Formatter::CompactTimeAgo.call(conversation.last_activity_at)
        end

        def current?(conversation)
          @current_uuid.present? && conversation.uuid == @current_uuid
        end

        def show_older_section?
          @older.any?
        end

        # Does this conversation carry AI messages? Answered for the WHOLE
        # list in one query (a per-row EXISTS would be N queries down a huge
        # /resume list) — the row partial appends the AI badge from this.
        # Keyed on uuid: it is part of this component's documented element
        # contract (rows may be lightweight stubs, not AR records).
        def ai_thread?(conversation)
          ai_conversation_uuids.include?(conversation.uuid)
        end

        private

        def ai_conversation_uuids
          @ai_conversation_uuids ||= ::Conversation
            .joins(:events)
            .where(uuid: (@recent + @older).map(&:uuid), events: { kind: "ai" })
            .distinct.pluck(:uuid).to_set
        end

        attr_reader :recent, :older
      end
    end
  end
end
