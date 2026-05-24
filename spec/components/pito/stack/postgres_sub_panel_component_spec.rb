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

    it "renders a single hint paragraph (not two spans)" do
      expect(page).to have_css("p.pito-sub-panel__hint", count: 1)
      expect(page).not_to have_css(".pito-sub-panel__hint-label")
      expect(page).not_to have_css(".pito-sub-panel__hint-status")
    end

    it "renders the full i18n hint text when connected" do
      expected = I18n.t("tui.stack.hint.postgres",
        version: "17",
        status: I18n.t("tui.stack.status.connected"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-success class when connected" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-success")
    end

    it "does not apply is-danger class when connected" do
      expect(page).not_to have_css("p.pito-sub-panel__hint.is-danger")
    end

    it "does not render a Tui::ChipComponent in the title actions" do
      expect(page).not_to have_css(".tui-chip")
    end
  end

  describe "hint line — disconnected state" do
    before do
      render_inline(described_class.new(status: disconnected_status, table_breakdown: []))
    end

    it "renders the full i18n hint text when disconnected (em-dash fallback version)" do
      expected = I18n.t("tui.stack.hint.postgres",
        version: "—",
        status: I18n.t("tui.stack.status.disconnected"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-danger class when disconnected" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-danger")
    end
  end

  describe "hint line — connected but version missing" do
    before do
      render_inline(described_class.new(status: no_version_status, table_breakdown: []))
    end

    it "falls back to em-dash for version in hint text" do
      expected = I18n.t("tui.stack.hint.postgres",
        version: "—",
        status: I18n.t("tui.stack.status.connected"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-success class when connected (regardless of missing version)" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-success")
    end
  end

  describe "#hint_text" do
    it "returns i18n'd hint with version and status when connected" do
      component = described_class.new(status: connected_status, table_breakdown: [])
      expected = I18n.t("tui.stack.hint.postgres",
        version: "17",
        status: I18n.t("tui.stack.status.connected"))
      expect(component.hint_text).to eq(expected)
    end

    it "returns i18n'd hint with em-dash version when disconnected" do
      component = described_class.new(status: disconnected_status, table_breakdown: [])
      expected = I18n.t("tui.stack.hint.postgres",
        version: "—",
        status: I18n.t("tui.stack.status.disconnected"))
      expect(component.hint_text).to eq(expected)
    end
  end

  describe "#hint_color_class" do
    it "returns 'is-success' when connected" do
      component = described_class.new(status: connected_status, table_breakdown: [])
      expect(component.hint_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when disconnected" do
      component = described_class.new(status: disconnected_status, table_breakdown: [])
      expect(component.hint_color_class).to eq("is-danger")
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

  describe "#panel_commands (Phase 1C — section-specific palette)" do
    subject(:commands) { described_class.new(status: connected_status, table_breakdown: []).panel_commands }

    it "returns the locked 3-column sort + sync_toggle command set (no reindex)" do
      keys = commands.map { |c| c[:key] }
      expect(keys).to contain_exactly(
        "sort_postgres_model",
        "sort_postgres_rows",
        "sort_postgres_size",
        "sync_toggle_postgres"
      )
    end

    it "annotates sort commands with table id + numeric column index" do
      sort_cmd = commands.find { |c| c[:key] == "sort_postgres_rows" }
      expect(sort_cmd[:action_name]).to eq(:sort_table)
      expect(sort_cmd[:args]).to eq(table: "stack-postgres", column: 1)
    end

    it "wires every action_name to a registered ActionRegistry entry" do
      commands.each do |c|
        expect { Pito::ActionRegistry[c[:action_name]] }.not_to raise_error
      end
    end
  end
end
