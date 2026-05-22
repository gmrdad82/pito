require "rails_helper"

RSpec.describe Tui::BottomStatusBarComponent, type: :component do
  subject(:component) { described_class.new(current_section: "home") }

  it "renders without raising" do
    expect { render_inline(component) }.not_to raise_error
  end

  it "renders the footer root element with data-controller" do
    render_inline(component)
    expect(page).to have_css("footer.bsb-bar[data-controller='tui-bottom-status-bar']")
  end

  it "composes ModeLozengeComponent (mode span present)" do
    render_inline(component)
    expect(page).to have_css("span.bsb-mode")
  end

  it "composes ScreensListComponent (sections span present)" do
    render_inline(component)
    expect(page).to have_css("span.bsb-sections")
    expect(page).to have_css("a.bsb-section", count: 3)
  end

  it "composes HelpHintComponent (? glyph present)" do
    render_inline(component)
    expect(page).to have_css("span.bsb-hint-key", text: "?")
  end

  it "composes CommandHintComponent (: glyph present)" do
    render_inline(component)
    expect(page).to have_css("span.bsb-hint-key", text: ":")
  end

  it "renders pipe separators from i18n" do
    render_inline(component)
    expect(page).to have_css("span.bsb-pipe", count: 2)
    expect(page).to have_css("span.bsb-pipe", text: I18n.t("tui.bst.pipe"))
  end

  it "forwards current_section to the screens list" do
    render_inline(described_class.new(current_section: "videos"))
    expect(page).to have_css("a.bsb-section.bsb-section--current", text: I18n.t("tui.bst.screens.videos"))
  end

  it "forwards mode to the mode lozenge (renders i18n word for the mode)" do
    render_inline(described_class.new(current_section: "home", mode: :search))
    expect(page).to have_css("span.bsb-mode")
    expect(page.find("span.bsb-mode")["data-tui-transition-value-value"]).to eq(I18n.t("tui.mode.search"))
  end

  it "defaults mode to :normal" do
    render_inline(component)
    expect(page.find("span.bsb-mode")["data-tui-transition-value-value"]).to eq(I18n.t("tui.mode.normal"))
  end

  it "falls back to :normal for unrecognised mode" do
    render_inline(described_class.new(current_section: "home", mode: :bogus))
    expect(page.find("span.bsb-mode")["data-tui-transition-value-value"]).to eq(I18n.t("tui.mode.normal"))
  end

  it "does not produce translation missing strings" do
    render_inline(component)
    expect(page.text).not_to include("translation missing")
  end
end
