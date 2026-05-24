require "rails_helper"

RSpec.describe Pito::Stack::VoyageSubPanelComponent, type: :component do
  before { allow(AppSetting).to receive(:reindex_running?).and_return(false) }

  describe "hint line — configured" do
    before do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      render_inline(described_class.new(configured: true))
    end

    it "renders a single hint paragraph (not two spans)" do
      expect(page).to have_css("p.pito-sub-panel__hint", count: 1)
      expect(page).not_to have_css(".pito-sub-panel__hint-label")
      expect(page).not_to have_css(".pito-sub-panel__hint-status")
    end

    it "renders the full i18n hint text when configured" do
      expected = I18n.t("tui.stack.hint.voyage_ai",
        status: I18n.t("tui.stack.status.configured"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-success class when configured" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-success")
    end

    it "does not render a Tui::ChipComponent in the title actions" do
      expect(page).not_to have_css(".tui-chip")
    end
  end

  describe "hint line — not configured" do
    before do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      render_inline(described_class.new(configured: false))
    end

    it "renders the full i18n hint text when not configured" do
      expected = I18n.t("tui.stack.hint.voyage_ai",
        status: I18n.t("tui.stack.status.not_configured"))
      expect(page).to have_css("p.pito-sub-panel__hint", text: expected)
    end

    it "applies is-danger class when not configured" do
      expect(page).to have_css("p.pito-sub-panel__hint.is-danger")
    end
  end

  describe "#hint_text" do
    it "returns i18n'd hint with configured status" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      component = described_class.new(configured: true)
      expected = I18n.t("tui.stack.hint.voyage_ai",
        status: I18n.t("tui.stack.status.configured"))
      expect(component.hint_text).to eq(expected)
    end

    it "returns i18n'd hint with not_configured status" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      component = described_class.new(configured: false)
      expected = I18n.t("tui.stack.hint.voyage_ai",
        status: I18n.t("tui.stack.status.not_configured"))
      expect(component.hint_text).to eq(expected)
    end
  end

  describe "#hint_color_class" do
    it "returns 'is-success' when configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      component = described_class.new(configured: true)
      expect(component.hint_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when not configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      component = described_class.new(configured: false)
      expect(component.hint_color_class).to eq("is-danger")
    end
  end

  describe "#panel_commands (Phase 1C — section-specific palette)" do
    before { allow(AppSetting).to receive(:voyage_configured?).and_return(true) }

    subject(:commands) { described_class.new(configured: true).panel_commands }

    it "returns the locked reindex + 2 sort + sync_toggle command set" do
      keys = commands.map { |c| c[:key] }
      expect(keys).to contain_exactly(
        "reindex_voyage",
        "sort_voyage_collection",
        "sort_voyage_embedded",
        "sync_toggle_voyage"
      )
    end

    it "annotates sort commands with table id + numeric column index" do
      sort_cmd = commands.find { |c| c[:key] == "sort_voyage_embedded" }
      expect(sort_cmd[:action_name]).to eq(:sort_table)
      expect(sort_cmd[:args]).to eq(table: "stack-voyage", column: 1)
    end

    it "wires every action_name to a registered ActionRegistry entry" do
      commands.each do |c|
        expect { Pito::ActionRegistry[c[:action_name]] }.not_to raise_error
      end
    end
  end
end
