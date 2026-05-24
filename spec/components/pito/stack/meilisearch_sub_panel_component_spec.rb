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

    it "renders the hint label with Meilisearch and v-prefixed major.minor version" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "Meilisearch v1.10")
    end

    it "renders the status word 'connected'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "connected")
    end

    it "applies is-success class when healthy" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-success")
    end

    it "does not render a Tui::ChipComponent in the title actions" do
      expect(page).not_to have_css(".tui-chip")
    end
  end

  describe "hint line — unhealthy" do
    before do
      render_inline(described_class.new(healthy: false, stats: no_version_stats, per_index_stats: []))
    end

    it "renders the hint label with em-dash when version is nil" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "Meilisearch —")
    end

    it "renders the status word 'disconnected'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "disconnected")
    end

    it "applies is-danger class when unhealthy" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-danger")
    end
  end

  describe "hint line — healthy but no version in stats" do
    before do
      render_inline(described_class.new(healthy: true, stats: empty_stats, per_index_stats: []))
    end

    it "falls back to em-dash for version" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "Meilisearch —")
    end

    it "still shows connected status with is-success" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-success", text: "connected")
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

  describe "#status_word" do
    it "returns 'connected' when healthy" do
      component = described_class.new(healthy: true, stats: healthy_stats, per_index_stats: [])
      expect(component.status_word).to eq("connected")
    end

    it "returns 'disconnected' when not healthy" do
      component = described_class.new(healthy: false, stats: no_version_stats, per_index_stats: [])
      expect(component.status_word).to eq("disconnected")
    end
  end

  describe "#status_color_class" do
    it "returns 'is-success' when healthy" do
      component = described_class.new(healthy: true, stats: healthy_stats, per_index_stats: [])
      expect(component.status_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when not healthy" do
      component = described_class.new(healthy: false, stats: no_version_stats, per_index_stats: [])
      expect(component.status_color_class).to eq("is-danger")
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
