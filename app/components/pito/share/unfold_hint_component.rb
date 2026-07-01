# frozen_string_literal: true

module Pito
  module Share
    # The public share-page chatbox hint affordance (owner 2026-07-01): swaps
    # between "c to chat" (unfocused) and "Enter to unfold" (focused), driven by
    # the pito--share-unfold controller. The "Enter" is an ACTION-shimmer LINK
    # (pito-blue↔purple) carrying the conversation URL, so unfold works even
    # without JS. Rendered into the reduced chatbox's hint slot.
    class UnfoldHintComponent < ViewComponent::Base
      # @param conversation_url [String] the full-conversation URL the Enter link opens
      def initialize(conversation_url:)
        @conversation_url = conversation_url.to_s
      end

      attr_reader :conversation_url

      def to_chat   = Pito::Copy.render("pito.copy.start_chatting")
      def to_unfold = Pito::Copy.render("pito.copy.share.to_unfold")
    end
  end
end
