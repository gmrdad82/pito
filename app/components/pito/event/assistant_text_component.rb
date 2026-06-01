# frozen_string_literal: true

module Pito
  module Event
    class AssistantTextComponent < ViewComponent::Base
      # @param payload [Hash] event payload.
      #   When `payload[:text]` is present it is rendered directly.
      #   When `payload[:message_key]` is present the text is resolved via i18n.
      # @param body [String, nil] optional plain text body (legacy, replaced by payload).
      # @param payload [Hash] event payload with optional `segment_style`:
      #   `"plain"`      — no accent, no background (first result, default)
      #   `"subsequent"` — blue accent, no background (2nd+ result in same turn)
      #   `"follow_up"`  — blue accent + surface background (upgraded by follow-up)
      def initialize(payload: {}, body: nil)
        payload = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload = payload
        @body = body || resolve_text(payload)
      end

      def accent
        case @payload[:segment_style]
        when "subsequent", "follow_up" then :blue
        else nil
        end
      end

      def background
        case @payload[:segment_style]
        when "follow_up" then "var(--bg-surface)"
        else nil
        end
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
