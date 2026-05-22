# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tui::BreadcrumbComponent, type: :component do
  describe "screen only" do
    subject(:component) { described_class.new(screen: "settings") }

    it "renders without raising" do
      expect { render_inline(component) }.not_to raise_error
    end

    it "renders the screen label in the sb-section span" do
      render_inline(component)
      expect(page).to have_css("span.sb-section", text: "settings")
    end

    it "does not render sub-panel spans" do
      render_inline(component)
      expect(page).not_to have_css(".sb-section__panel")
      expect(page).not_to have_css(".sb-section__sub-panel")
    end

    it "carries data-tui-status-bar-target=section" do
      render_inline(component)
      expect(page).to have_css("[data-tui-status-bar-target='section']")
    end
  end

  describe "screen + panel" do
    subject(:component) { described_class.new(screen: "settings", panel: "security") }

    it "renders the panel label as visible text within sb-section" do
      render_inline(component)
      # When no sub_panel is present, label renders as plain text inside the
      # sb-section span (not wrapped in sb-section__panel — that span only
      # appears when sub_panel_visible? is true).
      expect(page).to have_css("span.sb-section", text: "security")
    end

    it "does not render sub-panel spans" do
      render_inline(component)
      expect(page).not_to have_css(".sb-section__sub-panel")
    end
  end

  describe "screen + panel + sub_panel" do
    subject(:component) { described_class.new(screen: "settings", panel: "security", sub_panel: "totp") }

    it "renders the panel label" do
      render_inline(component)
      expect(page).to have_css("span.sb-section__panel", text: "security")
    end

    it "renders the sub-panel label" do
      render_inline(component)
      expect(page).to have_css("span.sb-section__sub-panel", text: "totp")
    end

    it "renders the opening paren with muted class from i18n" do
      paren_open = I18n.t("tui.tst.breadcrumb.paren_open")
      render_inline(component)
      expect(page).to have_css("span.sb-section__sub-panel-paren", text: paren_open)
    end

    it "renders the closing paren with muted class from i18n" do
      paren_close = I18n.t("tui.tst.breadcrumb.paren_close")
      render_inline(component)
      expect(page).to have_css("span.sb-section__sub-panel-paren", text: paren_close)
    end
  end

  describe "#sub_panel_visible?" do
    it "is false with screen only" do
      expect(described_class.new(screen: "games").sub_panel_visible?).to be false
    end

    it "is false with screen + panel" do
      expect(described_class.new(screen: "games", panel: "list").sub_panel_visible?).to be false
    end

    it "is true with screen + panel + sub_panel" do
      expect(described_class.new(screen: "games", panel: "list", sub_panel: "detail").sub_panel_visible?).to be true
    end
  end
end
