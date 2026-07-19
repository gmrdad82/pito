# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # The three cell shapes that earn right-alignment on any AI block that
      # renders a grid of cells — owner decree, shared by TableBlockComponent
      # (the per-column census) and KvTableBlockComponent (the plain-value
      # check) so the two never drift, and ported VERBATIM to the Go client
      # (pito-tui) so a table reads the same rendered by either. A cell
      # SHAPES when it matches at least one of:
      #
      #   NUMERIC — digits with optional grouping/decimals, a K/M/B magnitude
      #             or % suffix: "7,709", "2.2K", "93%" (the shapes the model
      #             actually sends).
      #   ID      — a bare system id: "#38" (the shape the vid/game list
      #             #id cells already right-align server-side).
      #   DATE    — the house date/stamp (Pito::Formatter::HouseDate /
      #             SyncStamp — "2 Jan", "19 Jul 12:00", "5 Jun '25 12:00"),
      #             a bare time ("12:00"), an ISO date with an optional
      #             T|space time ("2026-07-19", "2026-07-19T12:00"), or the
      #             frozen DD-MM-YYYY shape old payloads and model-sent
      #             cells still carry ("19-07-2026", "19-07-2026 12:00").
      module CellShapes
        module_function

        NUMERIC = /\A\s*[\d,.]+\s*[KMB%]?\s*\z/i
        ID      = /\A\s*#\d+\s*\z/

        HOUSE_DATE = /\A\s*\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)(?: '\d{2})?(?: \d{2}:\d{2})?\s*\z/
        BARE_TIME  = /\A\s*\d{2}:\d{2}\s*\z/
        ISO_DATE   = /\A\s*\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2})?\s*\z/
        DMY_DATE   = /\A\s*\d{2}-\d{2}-\d{4}(?: \d{2}:\d{2})?\s*\z/
        DATE       = Regexp.union(HOUSE_DATE, BARE_TIME, ISO_DATE, DMY_DATE)

        SHAPES = [ NUMERIC, ID, DATE ].freeze

        # @param cell [String] a single non-empty cell's text
        # @return [Boolean] true when the cell matches at least one shape family
        def match?(cell)
          SHAPES.any? { |shape| cell.match?(shape) }
        end
      end
    end
  end
end
