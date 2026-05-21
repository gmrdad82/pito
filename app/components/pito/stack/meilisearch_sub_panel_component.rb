module Pito
  module Stack
    # Pito::Stack::MeilisearchSubPanelComponent
    #
    # Meilisearch sub-panel inside the stack panel on Home.
    #
    # Shows: connection status chip + `[reindex]` action +
    # per-index stats (games + bundles — doc count + size). The
    # unified `games_<env>` Meilisearch index is split into two rows
    # by `kind` (`game` / `bundle`); size is reported by Meilisearch
    # at the INDEX level only, so `omit_size` bundle row renders a
    # plain dash in the size column to avoid double-attribution.
    #
    # FB-126 (2026-05-21) — `[reindex]` opens a
    # `Tui::ConfirmationDialogComponent` (mounted by the parent
    # `Pito::StackPanelComponent`) instead of POSTing directly.
    #
    # The idle + running children sit in the same DOM, toggled via
    # `hidden` so the action slot never collapses (no width jitter
    # when the swap fires).
    #
    # ## Kwargs
    #
    # @param healthy [Boolean] Meilisearch reachability
    # @param stats [Hash] aggregate Meilisearch stats (currently
    #   unused at the sub-panel surface; reserved for future).
    # @param per_index_stats [Array<Hash>] rows — `:label`,
    #   `:documents`, `:size_bytes`, `:missing` (bool — "not yet
    #   indexed"), `:omit_size` (bool — show dash for size).
    #
    # ## Cable channel
    #
    # `pito:home:stack:meilisearch` — broadcasts reindex state +
    # per-index stats updates.
    #
    # ## Focusables
    #
    # - `reindex_meilisearch` (style: :action) — only when reindex is
    #   NOT running. Resolved via
    #   `SettingsHelper#stack_reindex_focusables(running:)` which
    #   returns `[]` while running (the indicator slot is
    #   non-interactive).
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
    # - `Tui::ChipComponent` (status chip)
    # - `Tui::ActionButtonComponent` (`[reindex]` idle action)
    # - `Tui::ReindexProgressComponent` (`[=----]` running indicator)
    # - `SortableHeaderComponent` (sortable column headers)
    class MeilisearchSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:meilisearch".freeze

      def initialize(healthy:, stats:, per_index_stats:)
        @healthy = healthy
        @stats = stats
        @per_index_stats = per_index_stats
      end

      attr_reader :healthy, :stats, :per_index_stats

      def reindex_running?
        AppSetting.reindex_running?
      end

      def focusables
        helpers.stack_reindex_focusables(running: reindex_running?)
      end

      def state
        healthy ? :connected : :disconnected
      end

      def chip
        Pito::Stack::HealthState::STATES.fetch(state)
      end
    end
  end
end
