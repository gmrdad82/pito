# frozen_string_literal: true

module Pito
  module Event
    class ErrorComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ message_key:, message_args: }`.
      def initialize(payload: {})
        @message = I18n.t(payload[:message_key], **payload.fetch(:message_args, {}))
      end
    end
  end
end
