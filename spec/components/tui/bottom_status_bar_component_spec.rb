require "rails_helper"

# Beta 4 — Phase F1. Locks the rendered DOM contract for the
# `Tui::BottomStatusBarComponent`. The bottom status bar is the
# sticky-bottom counterpart to the top status bar — it lays out the
# current mode lozenge, the 8-section nav row, and the `?` / `:`
# keybinding hint markers, vim/TUI status-line style.
#
# What this spec locks (drift in any of these silently breaks the bar
# layout on every authenticated page):
#
#   * the 8-section nav row (home / calendar / channels / videos /
#     projects / games / notifications / settings) with lowercase
#     labels
#   * the `.bsb-section--current` modifier on the link matching
#     `current_section:`
#   * the `.bsb-mode--<mode>` modifier on the mode lozenge
#   * the `<footer>` root with the `bsb-bar` class hook (so CSS can
#     pin the bar to the viewport bottom)
#   * the `?` / `:` hint markers on the right
RSpec.describe Tui::BottomStatusBarComponent, type: :component do
  describe "root element + sticky-bottom hook" do
    it "renders inside a <footer> element with the `.bsb-bar` class hook" do
      render_inline(described_class.new(current_section: "home"))
      expect(page).to have_css("footer.bsb-bar")
    end

    it "wires the Stimulus controller via data-controller=tui-bottom-status-bar" do
      render_inline(described_class.new(current_section: "home"))
      expect(page).to have_css('footer.bsb-bar[data-controller~="tui-bottom-status-bar"]')
    end
  end

  describe "8-section nav row" do
    # The set + order are locked by the SECTIONS constant. Any drift
    # in the visible labels or count breaks the user's muscle memory
    # for the section nav.
    let(:expected_sections) do
      %w[home calendar channels videos projects games notifications settings]
    end

    before { render_inline(described_class.new(current_section: "home")) }

    it "renders exactly 8 section links" do
      expect(page).to have_css(".bsb-section", count: 8)
    end

    it "renders every section label in lowercase" do
      expected_sections.each do |section|
        expect(page).to have_css(".bsb-section", text: section)
      end
    end

    it "preserves the canonical section order in the DOM" do
      rendered_labels = page.all(".bsb-section").map(&:text)
      expect(rendered_labels).to eq(expected_sections)
    end

    it "points each section link at its canonical path" do
      pairs = {
        "home"          => "/",
        "calendar"      => "/calendar",
        "channels"      => "/channels",
        "videos"        => "/videos",
        "projects"      => "/projects",
        "games"         => "/games",
        "notifications" => "/notifications",
        "settings"      => "/settings"
      }
      pairs.each do |label, href|
        expect(page).to have_css(%(a.bsb-section[href="#{href}"]), text: label)
      end
    end
  end

  describe "current-section highlight" do
    it "marks the matching section with `.bsb-section--current`" do
      render_inline(described_class.new(current_section: "channels"))
      expect(page).to have_css("a.bsb-section--current", text: "channels")
    end

    it "marks ONLY one section as current" do
      render_inline(described_class.new(current_section: "games"))
      expect(page).to have_css("a.bsb-section--current", count: 1)
      expect(page).to have_css("a.bsb-section--current", text: "games")
    end

    it "accepts a symbol for current_section: and matches the same way" do
      render_inline(described_class.new(current_section: :settings))
      expect(page).to have_css("a.bsb-section--current", text: "settings")
    end

    it "renders no current marker when current_section: doesn't match a known section" do
      render_inline(described_class.new(current_section: "unknown"))
      expect(page).to have_no_css(".bsb-section--current")
    end
  end

  describe "mode lozenge" do
    described_class::MODES.each do |mode|
      it "renders the `.bsb-mode--#{mode}` modifier when mode: is :#{mode}" do
        render_inline(described_class.new(current_section: "home", mode: mode))
        expect(page).to have_css(".bsb-mode.bsb-mode--#{mode}", text: mode.to_s)
      end
    end

    it "defaults to :normal when mode: is not supplied" do
      render_inline(described_class.new(current_section: "home"))
      expect(page).to have_css(".bsb-mode.bsb-mode--normal", text: "normal")
    end

    it "falls back to :normal for an unknown mode value" do
      render_inline(described_class.new(current_section: "home", mode: :who_knows))
      expect(page).to have_css(".bsb-mode.bsb-mode--normal", text: "normal")
    end

    it "renders the mode label in lowercase" do
      render_inline(described_class.new(current_section: "home", mode: :command))
      expect(page).to have_css(".bsb-mode", text: "command")
    end
  end

  describe "hint markers (? help, : command)" do
    before { render_inline(described_class.new(current_section: "home")) }

    it "renders the `?` help hint key" do
      expect(page).to have_css(".bsb-hint-key", text: "?")
    end

    it "renders the `:` command hint key" do
      expect(page).to have_css(".bsb-hint-key", text: ":")
    end

    it "renders the `help` label next to the `?` key" do
      expect(page).to have_css(".bsb-hint-label", text: /help/)
    end

    it "renders the `command` label next to the `:` key" do
      expect(page).to have_css(".bsb-hint-label", text: /command/)
    end

    it "wraps the hints in a `.bsb-hints` group" do
      expect(page).to have_css(".bsb-hints")
    end
  end

  describe "constants" do
    it "freezes the SECTIONS list" do
      expect(described_class::SECTIONS).to be_frozen
    end

    it "freezes the MODES list" do
      expect(described_class::MODES).to be_frozen
    end

    it "exposes 8 sections" do
      expect(described_class::SECTIONS.length).to eq(8)
    end

    it "exposes the three vim-style modes" do
      expect(described_class::MODES).to contain_exactly(:normal, :command, :search)
    end
  end
end
