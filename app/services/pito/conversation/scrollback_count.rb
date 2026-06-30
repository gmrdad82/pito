# frozen_string_literal: true

module Pito
  module Conversation
    # Returns the count of non-thinking events strictly before / after a given
    # position within a conversation — the single source of truth for the
    # "non-thinking message" counting rule used by the share page and the
    # (future) scroll-nav component.
    #
    #   Pito::Conversation::ScrollbackCount.around(conversation:, position:)
    #   # => { before: Integer, after: Integer }
    #
    # "Non-thinking" = any Event whose kind is not "thinking". Position
    # comparisons are strict (< / >) so the event at `position` itself is
    # excluded from both counts.
    module ScrollbackCount
      THINKING_KIND = "thinking"
      private_constant :THINKING_KIND

      module_function

      def around(conversation:, position:)
        scope = ::Event.where(conversation:).where.not(kind: THINKING_KIND)
        {
          before: scope.where("position < ?", position).count,
          after:  scope.where("position > ?", position).count
        }
      end
    end
  end
end
