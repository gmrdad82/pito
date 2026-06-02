# frozen_string_literal: true

module Pito
  module Event
    class ErrorComponent < ViewComponent::Base
      # Payload shapes accepted:
      #   { text: "friendly message", detail: "raw error (optional)" }
      #   { message_key: "pito.some.key", message_args: {} }  — legacy, resolved via I18n
      def initialize(payload: {})
        @text   = payload[:text].presence ||
                  I18n.t(payload[:message_key].to_s, **payload.fetch(:message_args, {}))
        @detail = payload[:detail].presence
      end
    end
  end
end
