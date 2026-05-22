require "rails_helper"

RSpec.describe Tui::ScreensListComponent, type: :component do
  it "renders three section entries" do
    render_inline(described_class.new(current_section: "home"))
    expect(page).to have_css("a.bsb-section", count: 3)
  end

  it "marks home as current" do
    render_inline(described_class.new(current_section: "home"))
    expect(page).to have_css("a.bsb-section.bsb-section--current", text: I18n.t("tui.bst.screens.home"))
    expect(page).not_to have_css("a.bsb-section--current", text: I18n.t("tui.bst.screens.videos"))
    expect(page).not_to have_css("a.bsb-section--current", text: I18n.t("tui.bst.screens.games"))
  end

  it "marks videos as current" do
    render_inline(described_class.new(current_section: "videos"))
    expect(page).to have_css("a.bsb-section.bsb-section--current", text: I18n.t("tui.bst.screens.videos"))
    expect(page).not_to have_css("a.bsb-section--current", text: I18n.t("tui.bst.screens.home"))
  end

  it "marks games as current" do
    render_inline(described_class.new(current_section: "games"))
    expect(page).to have_css("a.bsb-section.bsb-section--current", text: I18n.t("tui.bst.screens.games"))
    expect(page).not_to have_css("a.bsb-section--current", text: I18n.t("tui.bst.screens.home"))
  end

  it "links each section to its root path" do
    render_inline(described_class.new(current_section: "home"))
    expect(page).to have_css("a[href='/']")
    expect(page).to have_css("a[href='/videos']")
    expect(page).to have_css("a[href='/games']")
  end

  it "renders labels from i18n" do
    render_inline(described_class.new(current_section: "home"))
    expect(page).to have_text(I18n.t("tui.bst.screens.home"))
    expect(page).to have_text(I18n.t("tui.bst.screens.videos"))
    expect(page).to have_text(I18n.t("tui.bst.screens.games"))
  end

  it "does not produce translation missing strings" do
    render_inline(described_class.new(current_section: "home"))
    expect(page.text).not_to include("translation missing")
  end

  it "wraps entries in .bsb-sections" do
    render_inline(described_class.new(current_section: "home"))
    expect(page).to have_css("span.bsb-sections")
  end
end
