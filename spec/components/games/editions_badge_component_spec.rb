require "rails_helper"

# Phase 28 §01a — `+N editions` badge.
RSpec.describe Games::EditionsBadgeComponent, type: :component do
  let(:primary) { create(:game, title: "Pragmata") }

  describe "render?" do
    it "does not render when the game is an edition" do
      edition = create(:game, version_parent: primary)
      render_inline(described_class.new(game: edition))
      expect(page).to have_no_text("edition", normalize_ws: true)
    end

    it "does not render when the game has no editions" do
      render_inline(described_class.new(game: primary))
      expect(page).to have_no_text("edition", normalize_ws: true)
    end

    it "renders when the game is a primary with at least one edition" do
      create(:game, version_parent: primary)
      render_inline(described_class.new(game: primary))
      expect(page).to have_text("+1 edition")
    end
  end

  describe "label" do
    it "uses the singular noun for one edition" do
      create(:game, version_parent: primary)
      render_inline(described_class.new(game: primary))
      expect(page).to have_text("+1 edition")
      expect(page.native.to_html).not_to include("+1 editions")
    end

    it "uses the plural noun for two editions" do
      2.times { create(:game, version_parent: primary) }
      render_inline(described_class.new(game: primary))
      expect(page).to have_text("+2 editions")
    end

    it "uses the plural noun for three or more editions" do
      3.times { create(:game, version_parent: primary) }
      render_inline(described_class.new(game: primary))
      expect(page).to have_text("+3 editions")
    end
  end

  describe "link target" do
    before { create(:game, version_parent: primary) }

    it "anchors to /games/:slug#editions" do
      render_inline(described_class.new(game: primary))
      link = page.find("a")
      expect(link[:href]).to end_with("#editions")
      expect(link[:href]).to include("#{primary.to_param}")
    end
  end

  describe "bare: true variant" do
    before { create(:game, version_parent: primary) }

    it "renders the bracketed text without a nested anchor" do
      render_inline(described_class.new(game: primary, bare: true))
      expect(page).to have_text("+1 edition")
      expect(page).to have_no_css("a")
      expect(page).to have_css("span.bracketed")
    end
  end

  describe "hard rules" do
    before { create(:game, version_parent: primary) }

    it "never emits data-turbo-confirm" do
      render_inline(described_class.new(game: primary))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits window.confirm or alert" do
      render_inline(described_class.new(game: primary))
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("alert(")
    end
  end
end
