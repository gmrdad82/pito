# frozen_string_literal: true

module Pito
  module StartScreen
    class Component < ViewComponent::Base
      # @param version [String] app version displayed in bottom-right corner.
      # @param pitomd_url [String] URL for the pitomd.com link in bottom-left.
      # @param logo [Object] optional logo content (slot — empty in Plan 1).
      renders_one :logo

      def initialize(version:, pitomd_url: "https://pitomd.com")
        @version = version
        @pitomd_url = pitomd_url
      end
    end
  end
end
