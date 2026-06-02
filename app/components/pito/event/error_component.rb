# frozen_string_literal: true

module Pito
  module Event
    class ErrorComponent < ViewComponent::Base
      # Payload shapes accepted:
      #   { text: "friendly message", detail: "raw error (optional)" }
      #   { message_key: "pito.some.key", message_args: {} }  — legacy, resolved via I18n
      def initialize(payload: {})
        @text        = payload[:text].presence ||
                       I18n.t(payload[:message_key].to_s, **payload.fetch(:message_args, {}))
        @detail      = payload[:detail].presence
        raw_creds    = payload[:credentials]
        @credentials = raw_creds.present? ? raw_creds.with_indifferent_access : nil
      end

      def credential_rows
        return [] unless @credentials

        [
          { label: "client_id",     present: @credentials[:client_id],
            value: @credentials[:client_id] ? "present" : "not set" },
          { label: "client_secret", present: @credentials[:client_secret],
            value: @credentials[:client_secret] ? "present" : "not set" },
          { label: "redirect_uri",  present: @credentials[:redirect_uri].present?,
            value: @credentials[:redirect_uri].presence || "not set" }
        ]
      end
    end
  end
end
