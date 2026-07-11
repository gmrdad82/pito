# frozen_string_literal: true

module Ai
  module Wire
    # Any non-2xx response, malformed body, or network/timeout failure. The
    # body excerpt is capped so a provider's HTML error page can't flood logs.
    class Error < StandardError
      BODY_EXCERPT = 500

      attr_reader :status

      def initialize(message, status: nil, body: nil)
        @status = status
        excerpt = body.to_s[0, BODY_EXCERPT]
        super([ message, excerpt.presence ].compact.join(" — body: "))
      end
    end
  end
end
