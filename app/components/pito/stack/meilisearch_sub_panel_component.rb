module Pito
  module Stack
    # Pito::Stack::MeilisearchSubPanelComponent
    #
    # Meilisearch sub-panel inside the stack panel on Home.
    #
    # Shows: a hint line (`Meilisearch v<version> connected`) at the top
    # of the body, followed by `[reindex]` action + per-index stats
    # (games + bundles — doc count + size). The unified `games_<env>`
    # Meilisearch index is split into two rows by `kind` (`game` /
    # `bundle`); size is reported by Meilisearch at the INDEX level only,
    # so `omit_size` bundle row renders a plain dash in the size column.
    # The title-row status chip was removed (Phase 1D); status is now
    # conveyed via the hint line.
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
    # @param stats [Hash] aggregate Meilisearch stats — keys include
    #   `:version` (String or nil, from `MeilisearchEngine#version`).
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

      # FB-167 (2026-05-23) — inlined from `SettingsHelper#stack_reindex_focusables`
      # to remove the `helpers.*` call. ViewComponent raises
      # `HelpersCalledBeforeRenderError` when a parent component calls
      # `focusables` on a sub-panel that has NOT been rendered through
      # `render(...)` yet (the sub-panel is instantiated in Ruby for
      # focusable aggregation in `Pito::StackPanelComponent#focusable_keys`).
      # The original helper was pure logic — `running ? [] : [{...}]` —
      # so inlining is safe and matches the canonical-source rule.
      def focusables
        return [] if reindex_running?

        [ { key: "reindex", style: :action } ]
      end

      def state
        healthy ? :connected : :disconnected
      end

      # Version label string — e.g. "1.10.3". Falls back to "—" when the
      # engine is unreachable or the version probe returned nil.
      # Meilisearch convention uses a `v` prefix in user-facing copy
      # (e.g. "Meilisearch v1.10 connected"), so callers prepend "v"
      # in the template when the version is not "—".
      def meilisearch_version
        v = stats[:version].presence
        return "—" unless v

        # Trim to major.minor only (e.g. "1.10.3" → "1.10").
        parts = v.split(".")
        parts.first(2).join(".")
      end

      # Human-readable status word for the hint line.
      def status_word
        healthy ? "connected" : "disconnected"
      end

      # CSS modifier class for the hint-line status span.
      # Connected → green (is-success); disconnected → red (is-danger).
      def status_color_class
        healthy ? "is-success" : "is-danger"
      end
    end
  end
end
