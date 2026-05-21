module Pito
  module Stack
    # Pito::Stack::PostgresSubPanelComponent
    #
    # PostgreSQL sub-panel inside the stack panel on Home.
    #
    # Shows: connection status chip + per-table breakdown (rows + size)
    # for the canonical domain tables (games, bundles). Rows expose
    # `data-stack-stats-live-target` cells so the panel-level polling
    # controller can patch counts + sizes in place every ~3 s without a
    # full-page reload.
    #
    # ## Kwargs
    #
    # @param status [Hash] connection probe — keys: `:connected`,
    #   `:adapter`, `:database`, `:version`. Falsy `:connected` skips
    #   the breakdown table entirely (only the chip renders).
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
    # None. The sub-panel is purely informational; no `[reindex]` /
    # action element to focus.
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + chip actions slot)
    # - `Tui::ChipComponent` (status chip)
    # - `SortableHeaderComponent` (column headers — sortable)
    class PostgresSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:postgres".freeze

      def initialize(status:, table_breakdown:)
        @status = status
        @table_breakdown = table_breakdown
      end

      attr_reader :status, :table_breakdown

      def focusables
        []
      end

      def state
        status[:connected] ? :connected : :disconnected
      end

      def chip
        Pito::Stack::HealthState::STATES.fetch(state)
      end
    end
  end
end
