require "rails_helper"

# Bundles::EmptyCoverPlaceholderComponent — netflix-3 controller-
# icon placeholder for empty bundles. Pins the theme-pair invariant
# (each of the 3 cells stacks BOTH a light + dark image variant,
# toggled at runtime by `[data-theme]` CSS rules) and the optional
# `:modal` modifier that lifts the icon size caps for the bundles
# modal cover slot.
RSpec.describe Bundles::EmptyCoverPlaceholderComponent, type: :component do
  describe "happy: cell + image structure" do
    it "renders exactly 3 cells (one --main + two regular)" do
      render_inline(described_class.new)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 > .cell", count: 3)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 > .cell.cell--main", count: 1)
    end

    it "renders 6 controller-icon imgs (3 cells x 2 theme variants)" do
      render_inline(described_class.new)
      expect(page).to have_css("img.bundle-tile__nocover-icon", count: 6)
    end

    it "stacks a light + dark variant inside every cell" do
      render_inline(described_class.new)
      page.all(".bundle-tile__nocover-netflix3 > .cell").each do |cell|
        expect(cell).to have_css('img[data-theme="light"]', count: 1)
        expect(cell).to have_css('img[data-theme="dark"]', count: 1)
      end
    end

    it "tags exactly 3 imgs with data-theme=light" do
      render_inline(described_class.new)
      expect(page).to have_css('img[data-theme="light"]', count: 3)
    end

    it "tags exactly 3 imgs with data-theme=dark" do
      render_inline(described_class.new)
      expect(page).to have_css('img[data-theme="dark"]', count: 3)
    end

    it "uses --large icons in the main cell and --small in the two side cells" do
      render_inline(described_class.new)
      expect(page).to have_css(".cell.cell--main img.bundle-tile__nocover-icon--large", count: 2)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 img.bundle-tile__nocover-icon--small", count: 4)
    end
  end

  describe "happy: --modal modifier" do
    it "appends --modal to the wrapper when modifier: :modal" do
      render_inline(described_class.new(modifier: :modal))
      expect(page).to have_css(".bundle-tile__nocover-netflix3.bundle-tile__nocover-netflix3--modal", count: 1)
    end

    it "omits --modal from the wrapper when modifier is nil (default)" do
      render_inline(described_class.new)
      expect(page).to have_css(".bundle-tile__nocover-netflix3", count: 1)
      expect(page).to have_no_css(".bundle-tile__nocover-netflix3--modal")
    end
  end

  describe "happy: aria-label + title from optional bundle" do
    it "uses bundle.name for aria-label and title when bundle is passed" do
      bundle = build_stubbed(:bundle, name: "Backlog 2026")
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css('.bundle-tile__nocover-netflix3[aria-label="Backlog 2026"]')
      expect(page).to have_css('.bundle-tile__nocover-netflix3[title="Backlog 2026"]')
    end

    it "renders an empty aria-label/title when no bundle is passed" do
      render_inline(described_class.new)
      expect(page).to have_css('.bundle-tile__nocover-netflix3[aria-label=""]')
      expect(page).to have_css('.bundle-tile__nocover-netflix3[title=""]')
    end
  end
end
