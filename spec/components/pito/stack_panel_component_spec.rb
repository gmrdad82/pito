require "rails_helper"

RSpec.describe Pito::StackPanelComponent, type: :component do
  let(:postgres_status) { { connected: true, version: "16.0" } }
  let(:storage_status)  { { present: true, writable: true } }
  let(:search_stats)    { {} }

  let(:component) do
    described_class.new(
      postgres_status: postgres_status,
      postgres_table_breakdown: [],
      search_healthy: true,
      search_stats: search_stats,
      search_per_index_stats: [],
      voyage_configured: true,
      storage_status: storage_status,
      assets_breakdown: []
    )
  end

  describe "PANEL_NAME" do
    it "matches the canonical Pito::PanelChannel allowlist entry" do
      expect(described_class::PANEL_NAME).to eq(:stack)
      expect(Pito::PanelChannel::ALLOWED_PANELS).to include(described_class::PANEL_NAME.to_s)
    end
  end

  it "no longer defines the legacy CABLE_CHANNEL constant (Phase 2C cleanup)" do
    expect(described_class.const_defined?(:CABLE_CHANNEL)).to be(false)
  end

  describe "#cable_channel_for" do
    it "derives the canonical pito:home:stack stream name" do
      expect(component.cable_channel_for(described_class::PANEL_NAME)).to eq("pito:home:stack")
    end
  end

  describe "#title" do
    it "resolves from the canonical home-panel i18n namespace" do
      expect(I18n.t("tui.home.panels.stack.title")).to eq("stack")
      expect(component.title).to eq("stack")
    end
  end

  describe "#panel_data (data attrs spread into the section root)" do
    # Stub focusables so we don't need to drive the live sub-panel
    # helpers chain — the contract under test here is the data-attr
    # emission shape, not the focusables computation.
    before { allow(component).to receive(:focusables).and_return([]) }

    let(:data) { component.panel_data[:data] }

    it "wires the tui-panel-cable Stimulus controller" do
      expect(data[:controller]).to eq("tui-panel-cable")
    end

    it "emits the canonical cable name + screen data values" do
      expect(data[:tui_panel_cable_name_value]).to eq("stack")
      expect(data[:tui_panel_cable_screen_value]).to eq("home")
    end

    it "registers the panel as a tui-cursor target" do
      expect(data[:tui_cursor_target]).to eq("panel")
    end

    it "emits the panel name into both cable + panel scope data values" do
      expect(data[:tui_panel_name_value]).to eq("stack")
    end

    it "JSON-encodes an empty keybinds Hash into the panel data value" do
      expect(data[:tui_panel_keybinds_value]).to eq("{}")
    end
  end

  describe "rendered output (with sub-panel focusables stubbed)" do
    before do
      # Stub the per-sub-panel focusables aggregators so the template
      # render doesn't pull in the live SettingsHelper#stack_reindex_focusables
      # — that helper is exercised by its own spec.
      allow_any_instance_of(Pito::Stack::PostgresSubPanelComponent).to receive(:focusables).and_return([])
      allow_any_instance_of(Pito::Stack::MeilisearchSubPanelComponent).to receive(:focusables).and_return([])
      allow_any_instance_of(Pito::Stack::VoyageSubPanelComponent).to receive(:focusables).and_return([])
      allow_any_instance_of(Pito::Stack::AssetsSubPanelComponent).to receive(:focusables).and_return([])
    end

    subject(:rendered) { render_inline(component) }

    let(:root) { rendered.css("section.pito-panel").first }

    it "renders the canonical pito-panel section wrapper" do
      expect(root).to be_present
      expect(root["class"]).to include("pito-panel")
      expect(root["class"]).to include("pito-panel--stack")
    end

    it "renders the title from the canonical home-panel i18n namespace" do
      title_span = rendered.css(".pito-pane__title").first
      expect(title_span).to be_present
      expect(title_span.text.strip).to eq("stack")
    end

    it "wires the tui-panel-cable Stimulus controller on the root section" do
      expect(root["data-controller"]).to include("tui-panel-cable")
    end

    it "emits the canonical cable name + screen data values on the root section" do
      expect(root["data-tui-panel-cable-name-value"]).to eq("stack")
      expect(root["data-tui-panel-cable-screen-value"]).to eq("home")
    end

    it "registers the panel as a tui-cursor target on the root section" do
      expect(root["data-tui-cursor-target"]).to eq("panel")
    end

    describe "2x2 sub-panel grid (locked 2026-05-23)" do
      it "renders the canonical .pito-stack-grid container" do
        expect(rendered.css("div.pito-stack-grid")).to be_present
      end

      it "drops the legacy vertical .stack-pane-grid container" do
        expect(rendered.css("div.stack-pane-grid")).to be_empty
      end

      it "composes all four remaining sub-panels in row-major order " \
         "(Meilisearch | Voyage AI / Postgres | Assets)" do
        sub_panel_titles = rendered.css(".pito-stack-grid .pito-sub-panel__title").map { |n| n.text.strip }
        expect(sub_panel_titles).to eq([
          I18n.t("settings.stack.meilisearch"),
          I18n.t("settings.voyage.heading"),
          I18n.t("settings.stack.postgres"),
          I18n.t("settings.stack.assets")
        ])
      end

      it "does not render the dropped Redis sub-panel" do
        sub_panel_titles = rendered.css(".pito-stack-grid .pito-sub-panel__title").map { |n| n.text.strip.downcase }
        expect(sub_panel_titles).not_to include(I18n.t("settings.stack.redis").downcase)
      end
    end
  end

  describe "#focusable_keys (FB-187 — Postgres + Assets reachable via h/l)" do
    before do
      # Stub the reindex-running check so Meilisearch + Voyage emit their
      # `[reindex]` focusables (idle state).
      allow(AppSetting).to receive(:reindex_running?).and_return(false)
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
    end

    it "aggregates the panel-level pause + sub-panel focusables in row-major declaration order" do
      keys = component.focusable_keys
      expect(keys).to eq([
        "stack_sync",
        "reindex", "meilisearch_sync",
        "reindex", "voyage_sync", "voyage_header",
        "postgres", "postgres_sync",
        "assets", "assets_sync"
      ])
    end

    it "includes both action-bearing sub-panels (meilisearch + voyage reindex)" do
      expect(component.focusable_keys.count("reindex")).to eq(2)
    end

    it "includes both action-less sub-panels (postgres + assets) so h/l can land on them" do
      expect(component.focusable_keys).to include("postgres", "assets")
    end

    it "exposes the panel-level pause control at the head of the list" do
      expect(component.focusable_keys.first).to eq("stack_sync")
    end

    it "emits a `<sub_panel>_pause` focusable for every sub-panel" do
      keys = component.focusable_keys
      %w[meilisearch_sync voyage_sync postgres_sync assets_sync].each do |k|
        expect(keys).to include(k)
      end
    end
  end

  describe "rendered sub-panel root focusables (FB-187)" do
    subject(:rendered) do
      allow(AppSetting).to receive(:reindex_running?).and_return(false)
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      render_inline(component)
    end

    it "emits data-tui-focusable on the Postgres sub-panel root" do
      sub_panel = rendered.css(".pito-sub-panel").find { |el| el["data-tui-focusable"] == "postgres" }
      expect(sub_panel).to be_present
      expect(sub_panel["data-tui-focusable-key"]).to eq("postgres")
      expect(sub_panel["data-tui-cursor-target"]).to eq("sub-panel")
    end

    it "emits data-tui-focusable on the Assets sub-panel root" do
      sub_panel = rendered.css(".pito-sub-panel").find { |el| el["data-tui-focusable"] == "assets" }
      expect(sub_panel).to be_present
      expect(sub_panel["data-tui-focusable-key"]).to eq("assets")
      expect(sub_panel["data-tui-cursor-target"]).to eq("sub-panel")
    end

    it "does NOT emit data-tui-focusable on action-bearing Meilisearch sub-panel root " \
       "(the [reindex] action carries the focusable)" do
      meili = rendered.css(".pito-sub-panel").find { |el| el.text.include?(I18n.t("settings.stack.meilisearch")) }
      expect(meili).to be_present
      expect(meili["data-tui-focusable"]).to be_nil
    end

    it "does NOT emit data-tui-focusable on action-bearing Voyage sub-panel root" do
      voyage = rendered.css(".pito-sub-panel").find { |el| el.text.include?(I18n.t("settings.voyage.heading")) }
      expect(voyage).to be_present
      expect(voyage["data-tui-focusable"]).to be_nil
    end
  end

  describe "#panel_commands (Phase 1C — section-specific palette)" do
    subject(:commands) { component.panel_commands }

    it "returns a single sync_toggle entry at the panel-aggregate level" do
      expect(commands.map { |c| c[:key] }).to eq([ "sync_toggle_stack" ])
    end

    it "wires the sync_toggle entry to the registered :sync_toggle action" do
      expect(commands.first[:action_name]).to eq(:sync_toggle)
      expect(commands.first[:args]).to eq(target: "home.stack")
      expect { Pito::ActionRegistry[:sync_toggle] }.not_to raise_error
    end

    it "serializes into the panel root's data-panel-commands attribute" do
      allow_any_instance_of(Pito::Stack::PostgresSubPanelComponent).to receive(:focusables).and_return([])
      allow_any_instance_of(Pito::Stack::MeilisearchSubPanelComponent).to receive(:focusables).and_return([])
      allow_any_instance_of(Pito::Stack::VoyageSubPanelComponent).to receive(:focusables).and_return([])
      allow_any_instance_of(Pito::Stack::AssetsSubPanelComponent).to receive(:focusables).and_return([])
      rendered = render_inline(component)
      root = rendered.css("section.pito-panel").first
      raw = root["data-panel-commands"]
      expect(raw).to be_present
      parsed = JSON.parse(raw)
      expect(parsed.length).to eq(1)
      expect(parsed.first["key"]).to eq("sync_toggle_stack")
    end
  end

  describe "constructor contract (Redis sub-panel dropped 2026-05-23)" do
    it "does not accept the legacy redis_status kwarg" do
      kwargs = described_class.instance_method(:initialize).parameters.map(&:last)
      expect(kwargs).not_to include(:redis_status)
    end

    it "does not accept the legacy sidekiq_breakdown kwarg" do
      kwargs = described_class.instance_method(:initialize).parameters.map(&:last)
      expect(kwargs).not_to include(:sidekiq_breakdown)
    end
  end

  describe "FB-188 (2026-05-23) — data-table row focusables drill INTO the sub-panel" do
    # The four stack sub-panels each render a sortable data table.
    # Body rows become flat j/k focusables alongside the sub-panel's
    # action button (`[reindex]` on Meilisearch + Voyage; nothing on
    # Postgres + Assets). Voyage's stats table is mixed — only the
    # embedded-coverage rows (`games_embedded` + `bundles_embedded`)
    # participate; the static metric KVs (model / last_indexed /
    # hnsw_indexes / last_24h) stay non-focusable.
    let(:component) do
      described_class.new(
        postgres_status: { connected: true, version: "16.0" },
        postgres_table_breakdown: [
          { label: "games",   count: 100, size_bytes: 1024 },
          { label: "bundles", count:  50, size_bytes:  512 }
        ],
        search_healthy: true,
        search_stats: {},
        search_per_index_stats: [
          { label: "games",   documents: 100, size_bytes: 2048 },
          { label: "bundles", documents:  50, size_bytes:  512, omit_size: true }
        ],
        voyage_configured: true,
        storage_status: { present: true, writable: true },
        assets_breakdown: [
          { label: "covers",     file_count: 10, size_bytes: 1024 },
          { label: "composites", file_count:  5, size_bytes:  512 }
        ]
      )
    end

    before do
      allow(AppSetting).to receive(:reindex_running?).and_return(false)
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      # Stub Voyage stats so the partial renders its embedded-coverage rows.
      allow(Voyage::Stats).to receive(:call).and_return(
        coverage_pct: 50.0,
        embedded_games_count: 50,
        total_games_count: 100,
        bundle_coverage_pct: 30.0,
        embedded_bundles_count: 3,
        total_bundles_count: 10,
        model: "voyage-3",
        last_indexed_at: nil,
        storage_kb: nil,
        embeddings_last_24h: 0
      )
    end

    subject(:rendered) { render_inline(component) }

    it "emits row-level data-tui-focusable on every Postgres breakdown <tr>" do
      postgres = rendered.css(".pito-sub-panel").find { |el| el["data-tui-focusable"] == "postgres" }
      rows = postgres.css("tbody tr.tui-table__row")
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r["data-tui-focusable"] }).to eq([ "row_games", "row_bundles" ])
      expect(rows.map { |r| r["data-tui-focusable-style"] }).to all(eq("row"))
      expect(rows.map { |r| r["data-tui-cursor-target"] }).to all(eq("row"))
    end

    it "emits row-level data-tui-focusable on every Meilisearch breakdown <tr>" do
      meili = rendered.css(".pito-sub-panel").find { |el| el.text.include?(I18n.t("settings.stack.meilisearch")) }
      rows = meili.css("tbody tr.tui-table__row")
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r["data-tui-focusable"] }).to eq([ "row_games", "row_bundles" ])
      expect(rows.map { |r| r["data-tui-focusable-style"] }).to all(eq("row"))
    end

    it "emits row-level data-tui-focusable on every Assets breakdown <tr>" do
      assets = rendered.css(".pito-sub-panel").find { |el| el["data-tui-focusable"] == "assets" }
      rows = assets.css("tbody tr.tui-table__row")
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r["data-tui-focusable"] }).to eq([ "row_covers", "row_composites" ])
      expect(rows.map { |r| r["data-tui-focusable-style"] }).to all(eq("row"))
    end

    it "emits focusables ONLY on Voyage's embedded-coverage rows (games + bundles); " \
       "static metric-KV rows (model / last_indexed / hnsw_indexes / last_24h) stay non-focusable" do
      voyage = rendered.css(".pito-sub-panel").find { |el| el.text.include?(I18n.t("settings.voyage.heading")) }
      focusable_rows = voyage.css("tbody tr.tui-table__row[data-tui-focusable]")
      keys = focusable_rows.map { |r| r["data-tui-focusable"] }
      expect(keys).to eq([ "row_games_embedded", "row_bundles_embedded" ])
      # Confirm the model row exists in the rendered DOM but is NOT focusable.
      model_row = voyage.css("tbody tr.tui-table__row").find { |r| r.text.include?("voyage-3") }
      expect(model_row).to be_present
      expect(model_row["data-tui-focusable"]).to be_nil
    end
  end
end
