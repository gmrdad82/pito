# frozen_string_literal: true

module Pito
  module Keybinding
    # KV-table: yellow section titles, cyan keys, muted values.
    # Keys are fixed-width so all values align vertically.
    class TableComponent < ViewComponent::Base
      def initialize(sections:)
        @sections = sections
      end
    end
  end
end
