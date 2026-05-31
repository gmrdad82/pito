# frozen_string_literal: true

module Pito
  module StartScreen
    class Component < ViewComponent::Base
      # @param version [String] app version displayed in bottom-right corner.
      # @param marketing_url [String, nil] URL for the marketing link in the
      #   bottom-left. When blank the link is omitted.
      # @param logo [Object] optional logo content (slot — empty in Plan 1).
      renders_one :logo

      def initialize(version:, marketing_url: nil)
        @version = version
        @marketing_url = marketing_url
      end
    end
  end
end
