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
    # - `assets` (style: :inert) — a single inert focusable on the
    #   sub-panel root so the cursor can LAND on the Assets sub-panel
    #   during h/l traversal across the Stack panel. No action fires on
    #   Enter/Space; the focusable gives the cursor a stop in the flat
    #   focusables list so `syncSubPanelFromFocusable` snaps the visible
    #   sub-panel border accent to Assets. Without this stop, h/l would
    #   skip Assets entirely (it has no `[reindex]` / action to focus).
    #   FB-187 (2026-05-23).
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

      # Returns a single inert focusable on the sub-panel root so the
      # cursor lands on Assets during h/l traversal across the Stack
      # panel's 2x2 sub-panel grid. Inert = no Enter/Space action fires.
      def focusables
        [ { key: "assets", style: :inert } ]
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
