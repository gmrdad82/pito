module Pito
  module Stack
    # Pito::Stack::VoyageSubPanelComponent
    #
    # Voyage AI sub-panel inside the stack panel on Home.
    #
    # Shows: configuration status chip + `[reindex]` action + stats
    # table (games embedded, bundles embedded, model, last indexed,
    # HNSW index size, last 24h embeddings) + running-state strip.
    #
    # FB-126 (2026-05-21) — `[reindex]` opens a
    # `Tui::ConfirmationDialogComponent` (mounted by the parent
    # `Pito::StackPanelComponent`) instead of POSTing directly.
    # Mirrors the Meilisearch sub-panel's wire contract.
    #
    # Phase 32 follow-up — Voyage section kept as a Turbo Stream
    # target so the Voyage reindex job can replace just the inner
    # stats block on broadcast. The `_voyage_section` partial is
    # still rendered from this component to preserve the
    # `<div id="voyage_section">` Turbo Stream target hook; the
    # title-in-border chrome (chip + `[reindex]`) stays put in the
    # sub-panel template above so per-broadcast repaints do not
    # clobber it.
    #
    # ## Kwargs
    #
    # @param configured [Boolean] Voyage credentials present?
    #   (`AppSetting.voyage_configured?`). Drives chip variant
    #   (`:configured` vs `:not_configured`).
    #
    # ## Cable channel
    #
    # `pito:home:stack:voyage` — broadcasts reindex state + Voyage
    # stats updates. The `reindex_status` Turbo Stream subscription
    # is mounted from inside the sub-panel template to scope the
    # broadcast targeting to this DOM subtree.
    #
    # ## Focusables
    #
    # - `reindex_voyage` (style: :action) — only when reindex is
    #   NOT running. Resolved via
    #   `SettingsHelper#stack_reindex_focusables(running:)`.
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
    # - `Tui::ChipComponent` (status chip)
    # - `Tui::ActionButtonComponent` (`[reindex]` idle action)
    # - `Tui::ReindexProgressComponent` (`[=----]` running indicator)
    # - Voyage stats partial `_voyage_section.html.erb` (Turbo Stream
    #   replace target — kept as a partial intentionally)
    class VoyageSubPanelComponent < ViewComponent::Base
      CABLE_CHANNEL = "pito:home:stack:voyage".freeze

      def initialize(configured:)
        @configured = configured
      end

      attr_reader :configured

      def reindex_running?
        AppSetting.reindex_running?
      end

      # FB-167 (2026-05-23) — inlined from `SettingsHelper#stack_reindex_focusables`
      # for the same reason as the Meilisearch sub-panel: parent
      # aggregation (`Pito::StackPanelComponent#focusable_keys`)
      # instantiates this VC in Ruby, so `helpers.*` raises
      # `HelpersCalledBeforeRenderError`. The helper was pure logic
      # (`running ? [] : [{...}]`); inlining preserves behavior.
      def focusables
        return [] if reindex_running?

        [ { key: "reindex", style: :action } ]
      end

      def state
        AppSetting.voyage_configured? ? :configured : :not_configured
      end

      def chip
        Pito::Stack::HealthState::STATES.fetch(state)
      end
    end
  end
end
