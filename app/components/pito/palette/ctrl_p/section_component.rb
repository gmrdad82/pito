# frozen_string_literal: true

module Pito
  module Palette
    module CtrlP
      class SectionComponent < ViewComponent::Base
        # @param title_key [String] i18n key for the section label.
        # @param items [Array<Hash>] each with keys :label_key and optional :shortcut.
        # @param selected [Boolean] whether this section contains the active selection.
        # @param selected_item_index [Integer, nil] index of the selected item within this section.
        def initialize(title_key:, items:, selected: false, selected_item_index: nil)
          @title_key = title_key
          @items = items
          @selected = selected
          @selected_item_index = selected_item_index
        end
      end
    end
  end
end
