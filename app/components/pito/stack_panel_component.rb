module Pito
  # Pito::StackPanelComponent
  #
  # The stack panel on Home (/). System stack monitoring tile lattice
  # showing connection health + per-subsystem stats for the operational
  # dependencies (PostgreSQL, Meilisearch, Voyage AI, assets storage).
  #
  # Composes 4 brand sub-panels in a 2x2 grid:
  #
  #   row 1: Meilisearch | Voyage AI
  #   row 2: Postgres    | Assets
  #
  # The Redis sub-panel was dropped 2026-05-23 — the Sidekiq counters
  # surface (Sidekiq runs on Redis) was the only remaining Redis-flavored
  # signal in the panel and it has been retired here; Redis health is
  # implicit via the Sidekiq-dependent jobs and surfaces elsewhere if
  # needed.
  #
  # ## Kwargs
  #
  # @param postgres_status [Hash] connection + version probe result
  # @param postgres_table_breakdown [Array<Hash>] per-table row + size
  # @param search_healthy [Boolean] Meilisearch reachability
  # @param search_stats [Hash] aggregate Meilisearch stats (reserved)
  # @param search_per_index_stats [Array<Hash>] per-index docs + size
  # @param voyage_configured [Boolean] Voyage credentials present?
  # @param storage_status [Hash] assets root probe (present/writable)
  # @param assets_breakdown [Array<Hash>] per-category file + size
  #
  # ## Cable channel
  #
  # `pito:home:stack` — parent channel. Each sub-panel broadcasts on
  # its own scoped channel:
  #   * `pito:home:stack:postgres`
  #   * `pito:home:stack:meilisearch`
  #   * `pito:home:stack:voyage`
  #   * `pito:home:stack:assets`
  #
  # ## Focusables
  #
  # Stack panel itself has no focusables; sub-panels supply them via
  # their own `focusables` methods. The aggregate list is:
  #
  #   - `reindex` (meilisearch)  — `[reindex]` action when idle
  #   - `meilisearch_header`     — table header stop (inert, FB 2026-05-24)
  #   - `reindex` (voyage)       — `[reindex]` action when idle
  #   - `voyage_header`          — table header stop (inert, FB 2026-05-24)
  #   - `postgres` (inert)       — sub-panel root stop (FB-187)
  #   - `postgres_header`        — table header stop (inert, FB 2026-05-24)
  #   - `assets` (inert)         — sub-panel root stop (FB-187)
  #   - `assets_header`          — table header stop (inert, FB 2026-05-24)
  #
  # FB-187 (2026-05-23): PostgreSQL + Assets sub-panels each emit a
  # single inert focusable on the sub-panel root so h/l traversal
  # can land on them (sub-panel border accent via
  # `syncSubPanelFromFocusable`). Without these stops, h/l skipped
  # them entirely (only action-bearing sub-panels participated in
  # the flat focusables list).
  #
  # ## Composes
  #
  # - `Pito::Stack::MeilisearchSubPanelComponent`
  # - `Pito::Stack::VoyageSubPanelComponent`
  # - `Pito::Stack::PostgresSubPanelComponent`
  # - `Pito::Stack::AssetsSubPanelComponent`
  # - `Tui::PanelFieldsetComponent` (frame chrome)
  # - `Tui::ConfirmationDialogComponent` (reindex confirmation dialogs)
  #
  # ## Phase 2C (2026-05-23)
  #
  # Wired with the canonical `Tui::PanelBase` mixin. Cable channel is now
  # derived via `cable_channel_for(PANEL_NAME)` (canonical
  # `pito:<screen>:<panel>` grammar); the legacy `CABLE_CHANNEL` constant
  # is gone. Title resolves from `tui.home.panels.stack.title` so the
  # future Ratatui client reads the same YAML. Sub-panel cable channels
  # (`pito:home:stack:postgres` etc.) remain owned by each sub-panel VC.
  class StackPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :stack

    def initialize(
      postgres_status:,
      postgres_table_breakdown:,
      search_healthy:,
      search_stats:,
      search_per_index_stats:,
      voyage_configured:,
      storage_status:,
      assets_breakdown:
    )
      @postgres_status = postgres_status
      @postgres_table_breakdown = postgres_table_breakdown
      @search_healthy = search_healthy
      @search_stats = search_stats
      @search_per_index_stats = search_per_index_stats
      @voyage_configured = voyage_configured
      @storage_status = storage_status
      @assets_breakdown = assets_breakdown
    end

    attr_reader :postgres_status, :postgres_table_breakdown,
                :search_healthy, :search_stats, :search_per_index_stats,
                :voyage_configured, :storage_status, :assets_breakdown

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    # Aggregate focusables from each sub-panel. The stack panel itself
    # contributes nothing; the cursor traverses sub-panel focusables in
    # 2x2-grid declaration order (Meilisearch → Voyage → Postgres →
    # assets).
    def focusables
      meilisearch_sub_panel.focusables +
        voyage_sub_panel.focusables +
        postgres_sub_panel.focusables +
        assets_sub_panel.focusables
    end

    def keybinds
      {}
    end

    # Phase 2C — feed only the key strings into panel_root_data. Sub-
    # panel focusables come through as Hashes ({ key:, style: }); the
    # data attr only needs the bare key list.
    def focusable_keys
      focusables.map { |f| f.is_a?(Hash) ? f[:key] : f }
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusable_keys, keybinds: keybinds)
    end

    def postgres_sub_panel
      @postgres_sub_panel ||= Pito::Stack::PostgresSubPanelComponent.new(
        status: postgres_status,
        table_breakdown: postgres_table_breakdown
      )
    end

    def meilisearch_sub_panel
      @meilisearch_sub_panel ||= Pito::Stack::MeilisearchSubPanelComponent.new(
        healthy: search_healthy,
        stats: search_stats,
        per_index_stats: search_per_index_stats
      )
    end

    def voyage_sub_panel
      @voyage_sub_panel ||= Pito::Stack::VoyageSubPanelComponent.new(
        configured: voyage_configured
      )
    end

    def assets_sub_panel
      @assets_sub_panel ||= Pito::Stack::AssetsSubPanelComponent.new(
        storage_status: storage_status,
        breakdown: assets_breakdown
      )
    end
  end
end
