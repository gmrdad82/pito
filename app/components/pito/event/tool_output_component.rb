# frozen_string_literal: true

module Pito
  module Event
    class ToolOutputComponent < ViewComponent::Base
      # @param title [String] e.g. "# Channel rollup"
      # @param command [String] e.g. "$ pito channels overview --period 7d"
      # @param output [String] pre-formatted text content.
      def initialize(title:, command:, output:)
        @title = title
        @command = command
        @output = output
      end
    end
  end
end
