module Pito
  module Stack
    # Pito::Stack::PostgresSubPanelComponent
    #
    # PostgreSQL sub-panel inside the stack panel on Home.
    #
    # Shows: a hint line (`PostgreSQL <version> connected`) at the top of
    # the body, followed by a per-table breakdown (rows + size) for the
    # canonical domain tables (games, bundles). The title-row status chip
    # was removed (Phase 1D); status is now conveyed via the hint line.
    #
    # ## Kwargs
    #
    # @param status [Hash] connection probe — keys: `:connected`,
    #   `:adapter`, `:database`, `:version`. Falsy `:connected` skips
    #   the breakdown table entirely (only the hint line renders).
    # @param table_breakdown [Array<Hash>] per-table rows. Each row:
    #   `:label`, `:count` (nil → em-dash), `:size_bytes` (nil →
    #   em-dash).
    #
    # ## Cable channel
    #
    # `pito:home:stack:postgres` — broadcasts table-stats updates.
    #
    # ## Focusables
    #
    # - `postgres` (style: :inert) — a single inert focusable on the
    #   sub-panel root so the cursor can LAND on the Postgres sub-panel
    #   during h/l traversal of the Stack panel. No action fires on
    #   Enter/Space; the focusable just gives the cursor a stop in
    #   the flat focusables list so `syncSubPanelFromFocusable` snaps
    #   the visible sub-panel border accent to Postgres. Without this
    #   stop, h/l would skip Postgres entirely (it has no reindex /
    #   action to focus). FB-187 (2026-05-23).
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
    # - `SortableHeaderComponent` (column headers — sortable)
    class PostgresSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:postgres".freeze

      def initialize(status:, table_breakdown:)
        @status = status
        @table_breakdown = table_breakdown
      end

      attr_reader :status, :table_breakdown

      # Returns a single inert focusable on the sub-panel root so the
      # cursor lands on Postgres during h/l traversal across the Stack
      # panel's 2x2 sub-panel grid. Inert = no Enter/Space action fires.
      def focusables
        [ { key: "postgres", style: :inert } ]
      end

      def state
        status[:connected] ? :connected : :disconnected
      end

      # Version label string — e.g. "17". Falls back to "—" when the
      # probe did not capture a version (disconnected or unavailable).
      def postgres_version
        status[:version].presence || "—"
      end

      # Human-readable status word for the hint line.
      def status_word
        status[:connected] ? "connected" : "disconnected"
      end

      # CSS modifier class for the hint-line status span.
      # Connected → green (is-success); disconnected → red (is-danger).
      def status_color_class
        status[:connected] ? "is-success" : "is-danger"
      end
    end
  end
end
