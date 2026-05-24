require "rails_helper"

RSpec.describe Pito::Stack::PostgresSubPanelComponent, type: :component do
  let(:connected_status) do
    { connected: true, adapter: "postgresql", database: "pito_development", version: "17" }
  end
  let(:disconnected_status) do
    { connected: false, adapter: "postgresql", database: nil, version: nil }
  end
  let(:no_version_status) do
    { connected: true, adapter: "postgresql", database: "pito_development", version: nil }
  end

  describe "hint line — connected state" do
    before do
      render_inline(described_class.new(status: connected_status, table_breakdown: []))
    end

    it "renders the hint label with PostgreSQL and version" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "PostgreSQL 17")
    end

    it "renders the status word 'connected'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "connected")
    end

    it "applies is-success class when connected" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-success")
    end

    it "does not apply is-danger class when connected" do
      expect(page).not_to have_css(".pito-sub-panel__hint-status.is-danger")
    end

    it "does not render a Tui::ChipComponent in the title actions" do
      expect(page).not_to have_css(".tui-chip")
    end
  end

  describe "hint line — disconnected state" do
    before do
      render_inline(described_class.new(status: disconnected_status, table_breakdown: []))
    end

    it "renders the hint label with em-dash fallback version" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "PostgreSQL —")
    end

    it "renders the status word 'disconnected'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "disconnected")
    end

    it "applies is-danger class when disconnected" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-danger")
    end
  end

  describe "hint line — connected but version missing" do
    before do
      render_inline(described_class.new(status: no_version_status, table_breakdown: []))
    end

    it "falls back to em-dash for version" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "PostgreSQL —")
    end

    it "still shows connected status with is-success" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-success", text: "connected")
    end
  end

  describe "#postgres_version" do
    it "returns the version string when present" do
      component = described_class.new(status: connected_status, table_breakdown: [])
      expect(component.postgres_version).to eq("17")
    end

    it "returns em-dash when version is nil" do
      component = described_class.new(status: disconnected_status, table_breakdown: [])
      expect(component.postgres_version).to eq("—")
    end
  end

  describe "#status_word" do
    it "returns 'connected' when status is connected" do
      component = described_class.new(status: connected_status, table_breakdown: [])
      expect(component.status_word).to eq("connected")
    end

    it "returns 'disconnected' when status is not connected" do
      component = described_class.new(status: disconnected_status, table_breakdown: [])
      expect(component.status_word).to eq("disconnected")
    end
  end

  describe "#status_color_class" do
    it "returns 'is-success' when connected" do
      component = described_class.new(status: connected_status, table_breakdown: [])
      expect(component.status_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when disconnected" do
      component = described_class.new(status: disconnected_status, table_breakdown: [])
      expect(component.status_color_class).to eq("is-danger")
    end
  end

  describe "hint line is first element in body (before table)" do
    let(:table_breakdown) do
      [ { label: "Game", count: 100, size_bytes: 1024 } ]
    end

    before do
      render_inline(described_class.new(status: connected_status, table_breakdown: table_breakdown))
    end

    it "renders the hint paragraph" do
      expect(page).to have_css("p.pito-sub-panel__hint")
    end

    it "renders the breakdown table" do
      expect(page).to have_css("table.tui-table")
    end
  end
end
