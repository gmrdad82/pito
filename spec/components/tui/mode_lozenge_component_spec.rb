require "rails_helper"

RSpec.describe Tui::ModeLozengeComponent, type: :component do
  it "renders the mode lozenge for normal mode" do
    render_inline(described_class.new(mode: :normal))
    expect(page).to have_css("span.bsb-mode.bsb-mode--normal")
    expect(page).to have_text(I18n.t("tui.bst.mode.normal"))
  end

  it "renders for command mode" do
    render_inline(described_class.new(mode: :command))
    expect(page).to have_css("span.bsb-mode.bsb-mode--command")
    expect(page).to have_text(I18n.t("tui.bst.mode.command"))
  end

  it "renders for search mode" do
    render_inline(described_class.new(mode: :search))
    expect(page).to have_css("span.bsb-mode.bsb-mode--search")
    expect(page).to have_text(I18n.t("tui.bst.mode.search"))
  end

  it "falls back to normal mode for unrecognised values" do
    render_inline(described_class.new(mode: :bogus))
    expect(page).to have_css("span.bsb-mode.bsb-mode--normal")
  end

  it "defaults to normal mode when no kwarg given" do
    render_inline(described_class.new)
    expect(page).to have_css("span.bsb-mode.bsb-mode--normal")
  end

  it "exposes the stimulus target attribute" do
    render_inline(described_class.new(mode: :normal))
    expect(page).to have_css("[data-tui-bottom-status-bar-target='mode']")
  end

  it "does not produce translation missing strings" do
    %i[normal command search].each do |m|
      render_inline(described_class.new(mode: m))
      expect(page.text).not_to include("translation missing")
    end
  end
end
