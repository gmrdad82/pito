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
        # The kv-table PALETTE without the kv key's nowrap: an AI table can't
        # be pre-fit like native ascii tables, so long cells must WRAP inside
        # their own grid track — nowrap painted over the neighbor column
        # (owner screenshot), and truncating a data cell would eat information.
        KEY_CLASS   = "text-cyan"
        VALUE_CLASS = Pito::Table::KeyValueRowComponent::DEFAULT_VALUE_CLASS

        # A cell that reads as a NUMBER for alignment purposes: digits with
        # optional grouping/decimals, a K/M/B magnitude or % suffix — the
        # shapes the model actually sends ("7,709", "2.2K", "93%").
        NUMERIC_CELL = /\A\s*[\d,.]+\s*[KMB%]?\s*\z/i

        # @param header [Array<String>] column titles (sets the column count)
        # @param rows   [Array<Array<String>>] cell rows, already width-padded
        def initialize(header:, rows:)
          @header = header
          @rows   = rows
        end

        def call
          render(Pito::Event::DataGridComponent.new(
            heading_cells:  @header.each_with_index.map { |text, i| { text:, class: "text-fg-faded#{align(i)}" } },
            rows:           @rows.map { |row| row.each_with_index.map { |text, i| { text:, class: (i.zero? ? KEY_CLASS : VALUE_CLASS) + align(i) } } },
            col_count:      [ @header.size, 2 ].max,
            fixed_leading:  0,
            fixed_trailing: 0,
            has_body:       false,
            info_lines:     []
          ))
        end

        private

        # Numbers right-align, prose left-aligns (owner: pito's own table law,
        # AI tables included) — a column counts as numeric when every
        # non-empty body cell in it reads as a number.
        def align(col)
          @numeric ||= Array.new(@header.size) do |i|
            cells = @rows.filter_map { |r| r[i].to_s.presence }
            cells.any? && cells.all? { |c| c.match?(NUMERIC_CELL) }
          end
          @numeric[col] ? " text-right" : ""
        end
      end
    end
  end
end
