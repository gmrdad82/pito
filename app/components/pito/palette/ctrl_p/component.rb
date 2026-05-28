# frozen_string_literal: true

module Pito
  module Palette
    module CtrlP
      class Component < ViewComponent::Base
        # @param sections [Array<Hash>] each with keys :title and :items.
        #   Each item is a Hash with keys :name and optional :shortcut.
        # @param selected_section_index [Integer] which section has the selected item.
        # @param selected_item_index [Integer] which item within that section is selected.
        def initialize(sections:, selected_section_index: 0, selected_item_index: 0)
          @sections = sections
          @selected_section_index = selected_section_index
          @selected_item_index = selected_item_index
        end
      end
    end
  end
end
