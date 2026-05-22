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

  it "renders one intra-zone pipe separator from i18n" do
    # Phase 3 (2026-05-22) — BST switched to 3-zone grid layout
    # (left | center | right). Inter-zone pipes are gone (grid gap handles
    # separation visually). The only pipe left is INTRA-zone, between
    # Mode and Sidekiq inside the left zone.
    render_inline(component)
    expect(page).to have_css("span.bsb-pipe", count: 1)
    expect(page).to have_css("span.bsb-pipe", text: I18n.t("tui.bst.pipe"))
  end

  it "composes Tui::SidekiqStatsComponent (tui-sidekiq-stats span present)" do
    # Phase 2 (2026-05-22) — SidekiqStats moved here from the TST. The
    # VC renders a single span (no internal cells) that hosts both the
    # tui-sidekiq-stats controller and the tui-transition controller.
    render_inline(component)
    expect(page).to have_css("span.tui-sidekiq-stats", count: 1)
  end

  it "positions Tui::SidekiqStatsComponent BETWEEN the mode lozenge and the ScreensList" do
    # Lock the BST ordering: mode | Sidekiq | screens | hints. Sidekiq
    # must appear AFTER the mode lozenge and BEFORE the screens list,
    # which itself sits before the hints group.
    render_inline(component)
    html = page.native.to_html
    mode_idx    = html.index("bsb-mode")
    sidekiq_idx = html.index("tui-sidekiq-stats")
    screens_idx = html.index("bsb-sections")
    hints_idx   = html.index("bsb-hints")
    expect(mode_idx).to be < sidekiq_idx
    expect(sidekiq_idx).to be < screens_idx
    expect(screens_idx).to be < hints_idx
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
