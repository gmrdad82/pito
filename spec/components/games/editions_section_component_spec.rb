require "rails_helper"

# Phase 28 §01a — editions sub-section on the primary's show page.
RSpec.describe Games::EditionsSectionComponent, type: :component do
  let(:primary) { create(:game, title: "Pragmata") }

  describe "render?" do
    it "does not render when the game has no editions" do
      render_inline(described_class.new(game: primary))
      expect(page).to have_no_css("section#editions")
    end

    it "does not render when the game is itself an edition" do
      edition = create(:game, version_parent: primary)
      render_inline(described_class.new(game: edition))
      expect(page).to have_no_css("section#editions")
    end

    it "renders when the primary has at least one edition" do
      create(:game, version_parent: primary)
      render_inline(described_class.new(game: primary))
      expect(page).to have_css("section#editions")
    end
  end

  describe "heading" do
    it "shows the count" do
      create(:game, title: "A", version_parent: primary)
      create(:game, title: "B", version_parent: primary)
      render_inline(described_class.new(game: primary))
      expect(page).to have_text("editions (2)")
    end
  end

  describe "edition rows" do
    let!(:deluxe)   { create(:game, title: "Pragmata Deluxe", version_parent: primary, version_title: "Deluxe") }
    let!(:standard) { create(:game, title: "Pragmata Standard", version_parent: primary, version_title: "Standard") }

    before { render_inline(described_class.new(game: primary)) }

    it "renders one row per edition" do
      expect(page).to have_css("li.edition-row", count: 2)
    end

    it "links each edition title to its show page" do
      expect(page).to have_link("Pragmata Deluxe")
      expect(page).to have_link("Pragmata Standard")
    end

    it "renders the version_title in muted text" do
      expect(page).to have_text("(Deluxe)")
      expect(page).to have_text("(Standard)")
    end

    it "renders the per-edition ownership chip strip" do
      expect(page).to have_css(".owned-platforms-chip-list", count: 2)
    end

    it "orders editions by title" do
      titles = page.all("li.edition-row a").map(&:text)
      expect(titles.first).to eq("Pragmata Deluxe")
      expect(titles.last).to eq("Pragmata Standard")
    end
  end

  describe "anchor" do
    before do
      create(:game, version_parent: primary)
      render_inline(described_class.new(game: primary))
    end

    it "renders an id=editions anchor for the badge link target" do
      expect(page).to have_css("section#editions")
    end
  end

  describe "hard rules" do
    before do
      create(:game, version_parent: primary)
      render_inline(described_class.new(game: primary))
    end

    it "never emits data-turbo-confirm" do
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits window.confirm or window.alert" do
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("window.alert")
    end
  end
end
