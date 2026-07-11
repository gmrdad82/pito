# frozen_string_literal: true

module Pito
  module Event
    # Renders the shared "data grid + info lines" block used by all three body
    # branches of SystemComponent (plain / html+ascii-fit / bare-table).
    #
    # Params:
    #   heading_cells  — Array of { text:, class: } hashes (may be empty)
    #   rows           — Array of cell-arrays (normalized_table_rows output)
    #   col_count      — Integer; final grid column count (already clamped to ≥ 2)
    #   fixed_leading  — Integer; number of pinned leading columns
    #   fixed_trailing — Integer; number of pinned trailing columns
    #   has_body       — Boolean; when true adds top-border separator on the grid
    #   info_lines     — Array of Strings; rendered with inline `code` highlighting
    class DataGridComponent < ViewComponent::Base
      def initialize(heading_cells:, rows:, col_count:, fixed_leading:, fixed_trailing:, has_body:, info_lines:)
        @heading_cells  = heading_cells
        @rows           = rows
        @col_count      = col_count
        @fixed_leading  = fixed_leading
        @fixed_trailing = fixed_trailing
        @has_body       = has_body
        @info_lines     = info_lines
      end

      attr_reader :heading_cells, :rows, :col_count, :fixed_leading, :fixed_trailing, :info_lines

      def has_body? = @has_body

      # Renders one data-grid cell <span>. Carries any per-cell `data:` (the
      # chat-prefill seam for clickable `#id` cells). HTML cells render their
      # text raw; plain cells are escaped. (Renders instantly.)
      def render_cell_span(cell)
        data    = cell[:data].present? ? cell[:data].to_h.dup : {}
        content = cell[:html] ? raw(cell[:text].to_s) : cell[:text].to_s
        tag.span(content, class: cell[:class], data: data.presence)
      end

      def render_info_line(line)
        segments = line.to_s.split(/(`[^`]+`)/)
        html = segments.map do |seg|
          if seg.start_with?("`") && seg.end_with?("`")
            content = ERB::Util.html_escape(seg[1..-2])
            %(<code class="text-fg">#{content}</code>)
          elsif seg.present?
            %(<span class="text-fg-dim">#{ERB::Util.html_escape(seg)}</span>)
          else
            ""
          end
        end.join
        html.html_safe
      end
    end
  end
end
