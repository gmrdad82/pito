# frozen_string_literal: true

module Pito
  module Palette
    module CtrlK
      class Component < ViewComponent::Base
        # @param sections [Array<Hash>] each with keys :title_key and :items.
        #   Each item is a Hash with keys :label_key, :insert, and optional :shortcut.
        #   Selection state is managed entirely by the pito--command-palette Stimulus controller.
        def initialize(sections:)
          @sections = sections
        end
      end
    end
  end
end
