require "rails_helper"

RSpec.describe Pito::Stack::VoyageSubPanelComponent, type: :component do
  before { allow(AppSetting).to receive(:reindex_running?).and_return(false) }

  describe "hint line — configured" do
    before do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      render_inline(described_class.new(configured: true))
    end

    it "renders the hint label 'Voyage AI'" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "Voyage AI")
    end

    it "renders the status word 'configured and ready'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "configured and ready")
    end

    it "applies is-success class when configured" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-success")
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

    it "renders the hint label 'Voyage AI'" do
      expect(page).to have_css(".pito-sub-panel__hint-label", text: "Voyage AI")
    end

    it "renders the status word 'not configured'" do
      expect(page).to have_css(".pito-sub-panel__hint-status", text: "not configured")
    end

    it "applies is-danger class when not configured" do
      expect(page).to have_css(".pito-sub-panel__hint-status.is-danger")
    end
  end

  describe "#status_word" do
    it "returns 'configured and ready' when voyage is configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      component = described_class.new(configured: true)
      expect(component.status_word).to eq("configured and ready")
    end

    it "returns 'not configured' when voyage is not configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      component = described_class.new(configured: false)
      expect(component.status_word).to eq("not configured")
    end
  end

  describe "#status_color_class" do
    it "returns 'is-success' when configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      component = described_class.new(configured: true)
      expect(component.status_color_class).to eq("is-success")
    end

    it "returns 'is-danger' when not configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      component = described_class.new(configured: false)
      expect(component.status_color_class).to eq("is-danger")
    end
  end
end
