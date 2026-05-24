module Pito
  module Stack
    # Pito::Stack::VoyageSubPanelComponent
    #
    # Voyage AI sub-panel inside the stack panel on Home.
    #
    # Shows: a hint line (`Voyage AI configured and ready`) at the top of
    # the body, followed by `[reindex]` action + TWO stacked stats tables
    # + running-state strip:
    #
    #   1. EMBEDS table (sortable) — `collection | embedded`. Rows:
    #      games, bundles (when present). The `embedded` cell carries a
    #      raw integer `data-sort-value` so the numeric sort orders by
    #      coverage count.
    #   2. INFO table (NON-sortable) — pure key/value: model,
    #      last_indexed, HNSW indexes, last 24h. No `<thead>`, no
    #      `sortable-table` controller; visually separated from the
    #      embeds table by a small top margin (no border).
    #
    # The title-row status chip was removed (Phase 1D); status is now
    # conveyed via the hint line.
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
    # title-in-border chrome (`[reindex]`) stays put in the
    # sub-panel template above so per-broadcast repaints do not
    # clobber it.
    #
    # ## Kwargs
    #
    # @param configured [Boolean] Voyage credentials present?
    #   (`AppSetting.voyage_configured?`). Drives hint-line status word
    #   (`configured and ready` vs `not configured`).
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
    # - `voyage_header` (style: :inert) — header row focusable on the
    #   embeds table so j/k can land ON the sortable header. The stop
    #   gives `s` / `S` a sub-panel-scoped focus context. Always
    #   emitted (the embeds table is always rendered with at least the
    #   games row).
    #
    # ## Composes
    #
    # - `Tui::SubPanelComponent` (chrome with title + actions slot)
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
        list = []
        list << { key: "reindex", style: :action } unless reindex_running?
        list << { key: "voyage_sync", style: :action }
        list << { key: "voyage_header", style: :inert }
        list
      end

      def state
        AppSetting.voyage_configured? ? :configured : :not_configured
      end

      # Full i18n'd hint line string for the sub-panel body top.
      # E.g. "Voyage AI configured and ready" or "Voyage AI not configured".
      # Sourced from `tui.stack.hint.voyage_ai` + `tui.stack.status.*`
      # so the future Rust TUI client reads the same YAML.
      def hint_text
        I18n.t(
          "tui.stack.hint.voyage_ai",
          status: I18n.t("tui.stack.status.#{state}"),
        )
      end

      # CSS modifier class for the ENTIRE hint line.
      # Configured → green (is-success); not configured → red (is-danger).
      def hint_color_class
        AppSetting.voyage_configured? ? "is-success" : "is-danger"
      end

      # Phase 1C (2026-05-24) — `:` palette commands for this sub-panel.
      # Surfaces reindex + per-column embed-table sort + sync toggle. See
      # `Pito::CommandPalette::Collector` for the merge contract.
      def panel_commands
        [
          { key: "reindex_voyage",
            name: I18n.t("tui.commands.reindex_voyage.name"),
            hint: I18n.t("tui.commands.reindex_voyage.hint"),
            action_name: :reindex_voyage },
          { key: "sort_voyage_collection",
            name: I18n.t("tui.commands.sort_table_collection.name"),
            hint: I18n.t("tui.commands.sort_table_collection.hint"),
            action_name: :sort_table,
            args: { table: "stack-voyage", column: 0 } },
          { key: "sort_voyage_embedded",
            name: I18n.t("tui.commands.sort_table_embedded.name"),
            hint: I18n.t("tui.commands.sort_table_embedded.hint"),
            action_name: :sort_table,
            args: { table: "stack-voyage", column: 1 } },
          { key: "sync_toggle_voyage",
            name: I18n.t("tui.commands.sync_toggle.name", label: "voyage"),
            hint: I18n.t("tui.commands.sync_toggle.hint", label: "voyage"),
            action_name: :sync_toggle,
            args: { target: "home.stack.voyage" } }
        ]
      end
    end
  end
end
