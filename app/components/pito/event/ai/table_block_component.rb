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

        # Smart per-column degrade: the leading #id-style column (0) and any
        # ALIGNING column (see #aligning_columns — numeric, #id, or date/time,
        # per Pito::Event::Ai::CellShapes) stay content-sized and NEVER
        # truncate — they're short and/or load-bearing. Every other column is
        # prose, and prose is the flexible one: it keeps today's wrapping at
        # comfortable widths but is the FIRST to tighten under real pressure
        # (a narrow container, or many columns — 4+ is the owner's example).
        # A literal, complete class name (never assembled from a variable —
        # JIT purges anything it can't see as a string) that the CSS in
        # application.css (.pito-table-cell--text, gated on data-cols>=4 or a
        # narrow @container) hooks the actual truncation to. No JS, no hover.
        TEXT_CELL_CLASS = "pito-table-cell--text"

        # @param header [Array<String>] column titles (sets the column count)
        # @param rows   [Array<Array<String>>] cell rows, already width-padded
        def initialize(header:, rows:)
          @header = header
          @rows   = rows
        end

        def call
          render(Pito::Event::DataGridComponent.new(
            heading_cells:  @header.each_with_index.map { |text, i| { text:, class: "text-fg-faded#{align(i)}#{degrade(i)}" } },
            rows:           @rows.map { |row| row.each_with_index.map { |text, i| { text:, class: (i.zero? ? KEY_CLASS : VALUE_CLASS) + align(i) + degrade(i) } } },
            col_count:      [ @header.size, 2 ].max,
            fixed_leading:  0,
            fixed_trailing: 0,
            has_body:       false,
            info_lines:     []
          ))
        end

        private

        # Numbers, ids, and dates right-align; prose left-aligns (owner:
        # pito's own table law, AI tables included) — a column counts as
        # aligning when every non-empty body cell in it matches at least one
        # CellShapes family (cells may mix families within a column).
        def align(col)
          aligning_columns[col] ? " text-right" : ""
        end

        # The leading id-style column and ALIGNING columns are exempt from
        # the degrade-first treatment — everything else is prose and gets
        # marked.
        def degrade(col)
          return "" if col.zero? || aligning_columns[col]

          " #{TEXT_CELL_CLASS}"
        end

        def aligning_columns
          @aligning_columns ||= Array.new(@header.size) do |i|
            cells = @rows.filter_map { |r| r[i].to_s.presence }
            cells.any? && cells.all? { |c| Pito::Event::Ai::CellShapes.match?(c) }
          end
        end
      end
    end
  end
end
