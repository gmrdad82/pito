# frozen_string_literal: true

module Pito
  module Stack
    # Shared request-count reads for an external-API provider module.
    # The extending module must define a `PROVIDER` string constant.
    #
    #   module Pito::Stack::Voyage
    #     PROVIDER = "voyage"
    #     extend Pito::Stack::ProviderCounts
    #   end
    #   Pito::Stack::Voyage.requests_24h   # => Integer
    module ProviderCounts
      def requests_24h
        ApiRequest.for_provider(self::PROVIDER).last_24h.count
      end

      def requests_month
        ApiRequest.for_provider(self::PROVIDER).this_month.count
      end

      def to_h
        { requests_24h: requests_24h, requests_month: requests_month }
      end
    end
  end
end
