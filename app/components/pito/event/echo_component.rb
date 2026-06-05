# frozen_string_literal: true

module Pito
  module Event
    class EchoComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ text: }`.
      # @param event [Event, nil] the persisted event — used for timestamp.
      def initialize(payload: {}, event: nil)
        @text             = payload[:text].to_s
        @timestamp        = event&.created_at
        @authenticated    = payload.fetch(:authenticated, true)
        @triggers_logout  = payload[:triggers_logout] == true || payload[:triggers_logout] == "true"
      end

      def triggers_logout? = @triggers_logout
    end
  end
end
