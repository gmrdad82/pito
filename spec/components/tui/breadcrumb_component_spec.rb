# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::BreadcrumbComponent, type: :component do
  describe "screen only" do
    subject(:component) { described_class.new(screen: "home") }

    it "renders without raising" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "renders the screen label in the sb-section span" do
      render_inline(component)
      expect(page).to have_css("span.sb-section", text: "home")
    end

    it "does not render the legacy 4-span structure (dropped in Phase 2D)" do
      render_inline(component)
      expect(page).not_to have_css(".sb-section__panel")
      expect(page).not_to have_css(".sb-section__sub-panel")
      expect(page).not_to have_css(".sb-section__sub-panel-paren")
    end

    it "carries data-tui-status-bar-target=section" do
      render_inline(component)
      expect(page).to have_css("[data-tui-status-bar-target='section']")
    end

    it "carries both tui-breadcrumb and tui-transition controllers" do
      render_inline(component)
      controller_attr = page.find("span.sb-section")["data-controller"]
      expect(controller_attr).to include("tui-breadcrumb")
      expect(controller_attr).to include("tui-transition")
    end

    it "sets data-tui-transition-value-value to the formatted string" do
      render_inline(component)
      expect(page).to have_css('[data-tui-transition-value-value="home"]')
    end

    it "sets data-tui-transition-color-value to muted (no panel focused)" do
      render_inline(component)
      expect(page).to have_css('[data-tui-transition-color-value="muted"]')
    end

    it "exposes data-tui-breadcrumb-screen-value" do
      render_inline(component)
      expect(page).to have_css('[data-tui-breadcrumb-screen-value="home"]')
    end

    it "wires the tui-transition outlet to .sb-section" do
      render_inline(component)
      expect(page).to have_css('[data-tui-breadcrumb-tui-transition-outlet=".sb-section"]')
    end
  end

  describe "screen + panel" do
    subject(:component) { described_class.new(screen: "home", panel: "security") }

    it "renders 'screen panel' as a single line of text" do
      render_inline(component)
      expect(page).to have_css("span.sb-section", text: "home security")
    end

    it "sets data-tui-transition-value-value to the joined string" do
      render_inline(component)
      expect(page).to have_css('[data-tui-transition-value-value="home security"]')
    end

    it "sets data-tui-transition-color-value to accent (panel focused)" do
      render_inline(component)
      expect(page).to have_css('[data-tui-transition-color-value="accent"]')
    end
  end

  describe "screen + panel + sub_panel" do
    subject(:component) { described_class.new(screen: "home", panel: "security", sub_panel: "totp") }

    it "renders 'screen panel:(sub_panel)' as a single line of text" do
      render_inline(component)
      expect(page).to have_css("span.sb-section", text: "home security:(totp)")
    end

    it "sets data-tui-transition-value-value to the formatted string" do
      render_inline(component)
      expect(page).to have_css('[data-tui-transition-value-value="home security:(totp)"]')
    end

    it "still uses accent color (panel is present)" do
      render_inline(component)
      expect(page).to have_css('[data-tui-transition-color-value="accent"]')
    end
  end

  describe ".format" do
    it "returns just the screen when panel is nil" do
      expect(described_class.format("home", nil, nil)).to eq("home")
    end

    it "returns 'screen panel' when sub_panel is nil" do
      expect(described_class.format("home", "security", nil)).to eq("home security")
    end

    it "returns 'screen panel:(sub_panel)' when all three are present" do
      expect(described_class.format("home", "security", "totp")).to eq("home security:(totp)")
    end

    it "treats blank strings as absent" do
      expect(described_class.format("home", "", "")).to eq("home")
      expect(described_class.format("home", "security", "")).to eq("home security")
    end
  end

  describe "#current_value" do
    it "delegates to .format with the instance's screen/panel/sub_panel" do
      component = described_class.new(screen: "games", panel: "list", sub_panel: "detail")
      expect(component.current_value).to eq("games list:(detail)")
    end
  end
end
