# frozen_string_literal: true

module Pito
  module Event
    class StatusFooterComponent < ViewComponent::Base
      # @param mode [String] e.g. "Build"
      # @param agent [String] e.g. "Big Pickle"
      # @param duration [String] e.g. "1m 3s"
      def initialize(mode:, agent:, duration:)
        @mode = mode
        @agent = agent
        @duration = duration
      end
    end
  end
end
