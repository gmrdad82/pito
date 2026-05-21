module Pito
  module Stack
    # Pito::Stack::AssetsSubPanelComponent
    #
    # Assets storage sub-panel inside the stack panel on Home.
    #
    # Shows: storage status chip (`writable` / `read_only` / `absent`)
    # + per-category file count + size breakdown (cover arts +
    # composites).
    #
    # ## Kwargs
    #
    # @param storage_status [Hash] assets root probe — keys:
    #   `:path`, `:present`, `:writable`, `:size_bytes`,
    #   `:file_count`. Drives chip variant: `:writable` (writable
    #   present), `:read_only` (present but not writable), `:absent`
    #   (root directory missing).
    # @param breakdown [Array<Hash>] per-category rows — `:label`,
    #   `:file_count` (nil → em-dash), `:size_bytes` (nil → em-dash).
    #
    # ## Cable channel
    #
    # `pito:home:stack:assets` — broadcasts assets breakdown updates.
    #
    # ## Focusables
    #
    # None. Purely informational sub-panel; no `[reindex]` action.
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
    # - `Tui::ChipComponent` (status chip)
    # - `SortableHeaderComponent` (sortable column headers)
    class AssetsSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:assets".freeze

      def initialize(storage_status:, breakdown:)
        @storage_status = storage_status
        @breakdown = breakdown
      end

      attr_reader :storage_status, :breakdown

      def focusables
        []
      end

      def state
        if storage_status[:present]
          storage_status[:writable] ? :writable : :read_only
        else
          :absent
        end
      end

      def chip
        Pito::Stack::HealthState::STATES.fetch(state)
      end
    end
  end
end
