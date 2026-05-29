# frozen_string_literal: true

module Pito
  module Palette
    module Slash
      class Component < ViewComponent::Base
        # @param commands [Array<Hash>] each with keys :verb and :description.
        # @param selected_index [Integer] index into commands for the highlighted row.
        # @param typed [String] what the user has typed so far.
        def initialize(commands:, selected_index: 0, typed: "/")
          @commands = commands
          @selected_index = selected_index
          @typed = typed
        end
      end
    end
  end
end
