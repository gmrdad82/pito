require "rails_helper"

# Beta 4 Phase F2 — Tui::FramedPanelComponent.
#
# Hairline-bordered container with optional title header. Wraps a
# slot of content (either yielded via block or the `body` slot). The
# template prefers `content` over `body` when both are set; coverage
# below pins that contract.
RSpec.describe Tui::FramedPanelComponent, type: :component do
  describe "wrapper element" do
    it "always renders a single `<section class=\"tui-framed-panel\">` root" do
      render_inline(described_class.new) { "body" }

      expect(page).to have_css("section.tui-framed-panel", count: 1)
    end

    it "renders a `.tui-framed-panel__body` div around the content" do
      render_inline(described_class.new) { "inside" }

      expect(page).to have_css(".tui-framed-panel__body", text: "inside")
    end
  end

  describe "title rendering" do
    it "renders no `<header>` when title is not given" do
      render_inline(described_class.new) { "body" }

      expect(page).to have_no_css(".tui-framed-panel__title")
      expect(page).to have_no_css("header")
    end

    it "renders no `<header>` when title is nil explicitly" do
      render_inline(described_class.new(title: nil)) { "body" }

      expect(page).to have_no_css(".tui-framed-panel__title")
    end

    it "renders `.tui-framed-panel__title` when title is given" do
      render_inline(described_class.new(title: "details")) { "body" }

      expect(page).to have_css("header.tui-framed-panel__title", text: "details")
    end

    it "renders the title as a child of the section" do
      render_inline(described_class.new(title: "details")) { "body" }

      expect(page).to have_css("section.tui-framed-panel > header.tui-framed-panel__title")
    end
  end

  describe "content / body slot" do
    it "renders block content inside the body div" do
      render_inline(described_class.new) { "yielded block" }

      expect(page).to have_css(".tui-framed-panel__body", text: "yielded block")
    end

    it "renders the body slot when no block content is given" do
      render_inline(described_class.new) do |c|
        c.with_body { "slot content" }
      end

      expect(page).to have_css(".tui-framed-panel__body", text: "slot content")
    end

    it "prefers block content over the body slot when both are present" do
      render_inline(described_class.new) do |c|
        c.with_body { "slot content" }
        "block content"
      end

      expect(page).to have_css(".tui-framed-panel__body", text: "block content")
      expect(page).to have_no_css(".tui-framed-panel__body", text: "slot content")
    end

    it "renders an empty body div when neither content nor slot is set" do
      render_inline(described_class.new)

      expect(page).to have_css(".tui-framed-panel__body")
    end
  end

  describe "title + body composition" do
    it "renders both the title header and the body div when both are present" do
      render_inline(described_class.new(title: "stats")) { "5 items" }

      expect(page).to have_css(".tui-framed-panel__title", text: "stats")
      expect(page).to have_css(".tui-framed-panel__body", text: "5 items")
    end
  end
end
