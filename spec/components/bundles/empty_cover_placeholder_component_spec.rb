require "rails_helper"

# Bundles::EmptyCoverPlaceholderComponent — netflix-3 controller-
# icon placeholder for empty bundles. Three cells (one `--main` +
# two regular) each rendering a single-dark controller-icon SVG.
# The `:modal` modifier lifts the icon size caps for the bundles
# modal cover slot.
#
# 2026-05-19 — pito is single-theme (dark). The previous dual
# light/dark image pair was collapsed to a single image per cell
# alongside the theme system removal.
RSpec.describe Bundles::EmptyCoverPlaceholderComponent, type: :component do
  describe "happy: cell + image structure" do
    it "renders exactly 3 cells (one --main + two regular)" do
      render_inline(described_class.new)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 > .cell", count: 3)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 > .cell.cell--main", count: 1)
    end

    it "renders 3 controller-icon imgs (one per cell, single-dark)" do
      render_inline(described_class.new)
      expect(page).to have_css("img.bundle-tile__nocover-icon", count: 3)
    end

    it "places exactly one img inside every cell (no theme pair)" do
      render_inline(described_class.new)
      page.all(".bundle-tile__nocover-netflix3 > .cell").each do |cell|
        expect(cell).to have_css("img.bundle-tile__nocover-icon", count: 1)
      end
    end

    it "does NOT emit data-theme attributes on the icon imgs (theme system removed)" do
      render_inline(described_class.new)
      expect(page).to have_no_css('img[data-theme="light"]')
      expect(page).to have_no_css('img[data-theme="dark"]')
    end

    it "references only the controller_icon_dark.svg asset" do
      render_inline(described_class.new)
      html = page.native.to_html
      expect(html).to match(/controller_icon_dark(-[a-f0-9]+)?\.svg/)
      expect(html).not_to match(/controller_icon_light/)
    end

    it "uses --large icons in the main cell and --small in the two side cells" do
      render_inline(described_class.new)
      expect(page).to have_css(".cell.cell--main img.bundle-tile__nocover-icon--large", count: 1)
      expect(page).to have_css(".bundle-tile__nocover-netflix3 img.bundle-tile__nocover-icon--small", count: 2)
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
