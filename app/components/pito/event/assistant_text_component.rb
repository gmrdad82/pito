# frozen_string_literal: true

module Pito
  module Event
    class AssistantTextComponent < ViewComponent::Base
      # @param payload [Hash] event payload.
      #   When `payload[:text]` is present it is rendered directly.
      #   When `payload[:message_key]` is present the text is resolved via i18n.
      # @param body [String, nil] optional plain text body (legacy, replaced by payload).
      def initialize(payload: {}, body: nil)
        @payload = payload
        @body = body || resolve_text(payload)
      end

      private

      def resolve_text(payload)
        if payload[:message_key]
          I18n.t(payload[:message_key], **payload.fetch(:message_args, {}))
        elsif payload[:text]
          payload[:text]
        end
      end
    end
  end
end
