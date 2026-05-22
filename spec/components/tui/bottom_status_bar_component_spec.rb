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

  it "renders three pipe separators from i18n" do
    # Phase 2 (2026-05-22) — pipe count rose from 2 to 3 when
    # Tui::SidekiqStatsComponent moved into the BST after ScreensList.
    # Layout: mode | screens | sidekiq | hints
    render_inline(component)
    expect(page).to have_css("span.bsb-pipe", count: 3)
    expect(page).to have_css("span.bsb-pipe", text: I18n.t("tui.bst.pipe"))
  end

  it "composes Tui::SidekiqStatsComponent (tui-sidekiq-stats span present)" do
    # Phase 2 (2026-05-22) — SidekiqStats moved here from the TST. The
    # VC renders a single span (no internal cells) that hosts both the
    # tui-sidekiq-stats controller and the tui-transition controller.
    render_inline(component)
    expect(page).to have_css("span.tui-sidekiq-stats", count: 1)
  end

  it "positions Tui::SidekiqStatsComponent AFTER the ScreensList pipe" do
    # Lock the BST ordering: mode | screens | sidekiq | hints. The
    # sidekiq span must appear after the second pipe (the one closing
    # the screens list) and before the third pipe (the one opening the
    # hints group).
    render_inline(component)
    html = page.native.to_html
    screens_idx = html.index("bsb-sections")
    sidekiq_idx = html.index("tui-sidekiq-stats")
    hints_idx   = html.index("bsb-hints")
    expect(screens_idx).to be < sidekiq_idx
    expect(sidekiq_idx).to be < hints_idx
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
