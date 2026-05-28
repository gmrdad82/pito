# frozen_string_literal: true

module Pito
  module Palette
    module CtrlP
      class SectionComponent < ViewComponent::Base
        # @param title [String] section label.
        # @param items [Array<Hash>] each with keys :name and optional :shortcut.
        # @param selected [Boolean] whether this section contains the active selection.
        # @param selected_item_index [Integer, nil] index of the selected item within this section.
        def initialize(title:, items:, selected: false, selected_item_index: nil)
          @title = title
          @items = items
          @selected = selected
          @selected_item_index = selected_item_index
        end
      end
    end
  end
end
