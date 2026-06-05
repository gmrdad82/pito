# frozen_string_literal: true

module Pito
  module Palette
    module CtrlK
      class SectionComponent < ViewComponent::Base
        # @param title_key [String] i18n key for the section label.
        # @param items [Array<Hash>] each with keys :label_key, :insert, optional :shortcut.
        #   Selection highlight is managed by the pito--command-palette Stimulus controller.
        def initialize(title_key:, items:)
          @title_key = title_key
          @items     = items
        end
      end
    end
  end
end
