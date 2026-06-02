# frozen_string_literal: true

module Pito
  module Event
    class ErrorComponent < ViewComponent::Base
      # Payload shapes accepted:
      #   { text: "friendly message", detail: "raw error (optional)" }
      #   { message_key: "pito.some.key", message_args: {} }  — legacy, resolved via I18n
      def initialize(payload: {}, event: nil)
        @text        = payload[:text].presence ||
                       I18n.t(payload[:message_key].to_s, **payload.fetch(:message_args, {}))
        @detail      = payload[:detail].presence
        raw_creds    = payload[:credentials]
        @credentials = raw_creds.present? ? raw_creds.with_indifferent_access : nil
      end

      def credential_rows
        return [] unless @credentials

        [
          { label: "Client ID",     present: @credentials[:client_id],
            display: @credentials[:client_id] ? "[set]" : "MISSING" },
          { label: "Client Secret", present: @credentials[:client_secret],
            display: @credentials[:client_secret] ? "[set]" : "MISSING" },
          { label: "Redirect URI",  present: @credentials[:redirect_uri].present?,
            display: @credentials[:redirect_uri].presence || "MISSING" },
          { label: "API Key",       present: @credentials[:api_key],
            display: @credentials[:api_key] ? "[set]" : "MISSING" }
        ]
      end
    end
  end
end
