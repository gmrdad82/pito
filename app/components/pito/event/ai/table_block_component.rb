# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A headered table block inside an :ai message — rides the shared
      # DataGridComponent (the same grid every :system table uses).
      class TableBlockComponent < ViewComponent::Base
        # @param header [Array<String>] column titles (sets the column count)
        # @param rows   [Array<Array<String>>] cell rows, already width-padded
        def initialize(header:, rows:)
          @header = header
          @rows   = rows
        end

        def call
          render(Pito::Event::DataGridComponent.new(
            heading_cells:  @header.map { |text| { text:, class: "text-fg-dim" } },
            rows:           @rows.map { |row| row.map { |text| { text: } } },
            col_count:      [ @header.size, 2 ].max,
            fixed_leading:  0,
            fixed_trailing: 0,
            has_body:       false,
            info_lines:     []
          ))
        end
      end
    end
  end
end
