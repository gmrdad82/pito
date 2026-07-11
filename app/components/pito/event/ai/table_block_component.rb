# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A headered table block inside an :ai message — the shared
      # DataGridComponent grid dressed in the kv-table palette: the leading
      # column wears the KeyValueRowComponent key style (cyan), every other
      # cell its value style (dim), headers faded. Same columns-align grid,
      # same colors as a `show game` detail.
      class TableBlockComponent < ViewComponent::Base
        KEY_CLASS   = Pito::Table::KeyValueRowComponent::DEFAULT_KEY_CLASS
        VALUE_CLASS = Pito::Table::KeyValueRowComponent::DEFAULT_VALUE_CLASS

        # @param header [Array<String>] column titles (sets the column count)
        # @param rows   [Array<Array<String>>] cell rows, already width-padded
        def initialize(header:, rows:)
          @header = header
          @rows   = rows
        end

        def call
          render(Pito::Event::DataGridComponent.new(
            heading_cells:  @header.map { |text| { text:, class: "text-fg-faded" } },
            rows:           @rows.map { |row| row.each_with_index.map { |text, i| { text:, class: i.zero? ? KEY_CLASS : VALUE_CLASS } } },
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
