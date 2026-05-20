module Tui
  # Beta 4 — Phase F2. TUI table primitive. Renders a simple
  # `<table>` with hairline row separators, lowercase muted header
  # text, and tabular-numeric alignment for right/center columns.
  # Per-column alignment is driven by an `align:` array of symbols
  # (`:left` / `:right` / `:center`); omitted entries default to
  # `:left`.
  #
  # Per ADR 0016 (TUI design system), tables are the default
  # presentation for tabular data — sessions, channels, video lists,
  # snapshots. The grammar is deliberately minimal: no zebra
  # striping, no row hover, no sortable headers. Sorting / filtering
  # / selection happen at the view layer above, composing this
  # primitive with `Tui::CheckboxComponent` / `Tui::ChipComponent`
  # as the cell content.
  #
  # Headers and rows are arrays — header strings render as-is (the
  # caller decides the case); cells render as-is (the caller is
  # responsible for HTML-safety when injecting components).
  class TableComponent < ViewComponent::Base
    def initialize(headers:, rows:, align: nil)
      @headers = headers.to_a
      @rows = rows.to_a
      @align = align || []
    end

    attr_reader :headers, :rows, :align

    def col_align(idx)
      align[idx] || :left
    end
  end
end
