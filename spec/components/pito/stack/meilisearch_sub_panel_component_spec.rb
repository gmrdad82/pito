require "rails_helper"

RSpec.describe Pito::Stack::MeilisearchSubPanelComponent, type: :component do
  let(:healthy_stats)     { { version: "1.10.3" } }
  let(:minor_version_stats) { { version: "1.10.0" } }
  let(:no_version_stats)  { { version: nil } }
  let(:empty_stats)       { {} }

  before { allow(AppSetting).to receive(:reindex_running?).and_return(false) }

  describe "hint line — healthy, version present" do
    before do
      render_inline(described_class.new(healthy: true, stats: healthy_stats, per_index_stats: []))
    end

    it "renders a single hint paragraph (not two spans)" do
      expect(page).to have_css("p.pito-sub-panel__hint", count: 1)
      expect(page).not_to have_css(".pito-sub-panel__hint-label")
      expect(page).not_to have_css(".pito-sub-panel__hint-status")
    end

    it "renders the full i18n hint text when healthy" do
      expected = I18n.t("tui.stack.hint.meilisearch",
        version: "1.10",
        status: I18n.t("tui.stack.status.connected"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-success class when healthy" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-success")
    end

    it "does not render a Tui::ChipComponent in the title actions" do
      expect(page).not_to have_css(".tui-chip")
    end
  end

  describe "hint line — unhealthy" do
    before do
      render_inline(described_class.new(healthy: false, stats: no_version_stats, per_index_stats: []))
    end

    it "renders the full i18n hint text when disconnected (em-dash version)" do
      expected = I18n.t("tui.stack.hint.meilisearch",
        version: "—",
        status: I18n.t("tui.stack.status.disconnected"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-danger class when unhealthy" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-danger")
    end
  end

  describe "hint line — healthy but no version in stats" do
    before do
      render_inline(described_class.new(healthy: true, stats: empty_stats, per_index_stats: []))
    end

    it "falls back to em-dash for version in hint text" do
      expected = I18n.t("tui.stack.hint.meilisearch",
        version: "—",
        status: I18n.t("tui.stack.status.connected"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "still applies is-success class when healthy" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-success")
    end
  end

  describe "#hint_text" do
    it "returns i18n'd hint with major.minor version and connected status" do
      component = described_class.new(healthy: true, stats: healthy_stats, per_index_stats: [])
      expected = I18n.t("tui.stack.hint.meilisearch",
        version: "1.10",
        status: I18n.t("tui.stack.status.connected"))
      expect(component.hint_text).to eq(expected)
    end

    it "returns i18n'd hint with em-dash version when disconnected" do
      component = described_class.new(healthy: false, stats: no_version_stats, per_index_stats: [])
      expected = I18n.t("tui.stack.hint.meilisearch",
        version: "—",
        status: I18n.t("tui.stack.status.disconnected"))
      expect(component.hint_text).to eq(expected)
    end
  end

  describe "#hint_color_class" do
    it "returns 'is-success' when healthy" do
      component = described_class.new(healthy: true, stats: healthy_stats, per_index_stats: [])
      expect(component.hint_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when not healthy" do
      component = described_class.new(healthy: false, stats: no_version_stats, per_index_stats: [])
      expect(component.hint_color_class).to eq("is-danger")
    end
  end

  describe "#meilisearch_version" do
    it "returns major.minor when full version present" do
      component = described_class.new(healthy: true, stats: healthy_stats, per_index_stats: [])
      expect(component.meilisearch_version).to eq("1.10")
    end

    it "returns major.minor from a two-segment version string" do
      component = described_class.new(healthy: true, stats: { version: "1.10" }, per_index_stats: [])
      expect(component.meilisearch_version).to eq("1.10")
    end

    it "returns em-dash when version is nil" do
      component = described_class.new(healthy: true, stats: no_version_stats, per_index_stats: [])
      expect(component.meilisearch_version).to eq("—")
    end

    it "returns em-dash when stats has no :version key" do
      component = described_class.new(healthy: true, stats: empty_stats, per_index_stats: [])
      expect(component.meilisearch_version).to eq("—")
    end
  end

  describe "#panel_commands (Phase 1C — section-specific palette)" do
    subject(:commands) do
      described_class.new(healthy: true, stats: healthy_stats, per_index_stats: []).panel_commands
    end

    it "returns the locked reindex + 3-column sort + sync_toggle command set" do
      keys = commands.map { |c| c[:key] }
      expect(keys).to contain_exactly(
        "reindex_meilisearch",
        "sort_meilisearch_index",
        "sort_meilisearch_docs",
        "sort_meilisearch_size",
        "sync_toggle_meilisearch"
      )
    end

    it "annotates sort commands with table id + numeric column index" do
      sort_cmd = commands.find { |c| c[:key] == "sort_meilisearch_docs" }
      expect(sort_cmd[:action_name]).to eq(:sort_table)
      expect(sort_cmd[:args]).to eq(table: "stack-meilisearch", column: 1)
    end

    it "wires every action_name to a registered ActionRegistry entry" do
      commands.each do |c|
        expect { Pito::ActionRegistry[c[:action_name]] }.not_to raise_error
      end
    end

    it "serializes into the sub-panel root's data-panel-commands attribute" do
      page_doc = render_inline(described_class.new(healthy: true, stats: healthy_stats, per_index_stats: []))
      sub_panel_root = page_doc.css(".pito-sub-panel").first
      raw = sub_panel_root["data-panel-commands"]
      expect(raw).to be_present
      parsed = JSON.parse(raw)
      expect(parsed.length).to eq(5)
      expect(parsed.map { |c| c["key"] }).to include("reindex_meilisearch", "sort_meilisearch_index")
    end
  end

  describe "hint line renders before index table" do
    let(:per_index_stats) do
      [ { label: "games", documents: 50, size_bytes: 2048, missing: false, omit_size: false } ]
    end

    before do
      render_inline(described_class.new(healthy: true, stats: healthy_stats, per_index_stats: per_index_stats))
    end

    it "renders the hint paragraph" do
      expect(page).to have_css("p.pito-sub-panel__hint")
    end

    it "renders the breakdown table" do
      expect(page).to have_css("table.tui-table")
    end
  end
end
