# frozen_string_literal: true

module Pito
  module Event
    class EchoComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ text: }`.
      # @param event [Event, nil] the persisted event — used for timestamp.
      def initialize(payload: {}, event: nil)
        @text          = payload[:text].to_s
        @timestamp     = event&.created_at
        @authenticated = payload.fetch(:authenticated, true)
      end

      def timestamp_line
        time = @timestamp ? @timestamp.strftime("%-l:%M %p") : ""
        channel = t("pito.shell.chatbox.default_channel")
        "#{time} · #{channel}"
      end
    end
  end
end
