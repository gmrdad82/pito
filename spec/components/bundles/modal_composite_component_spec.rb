require "rails_helper"

# Bundles::ModalCompositeComponent — CSS composite cover grid for
# the bundle modal. Mirrors `Composite::CellMap` pixel-for-pixel:
# each cell anchor carries inline percentage `left/top/width/height`
# matching `Composite::CellMap.for(n)[i]` exactly.
RSpec.describe Bundles::ModalCompositeComponent, type: :component do
  # `bundle.games.first(9)` is called by the component. We stub the
  # games association so cell-count cases are deterministic without
  # touching the DB. `build_stubbed_list` avoids DB writes and gives
  # us real Game instances (so `game_path` / `cover_master_url` work).
  def stub_bundle_with(game_count)
    bundle = build_stubbed(:bundle)
    games = build_stubbed_list(:game, game_count, cover_image_id: "abc123")
    allow(bundle).to receive(:games).and_return(games)
    bundle
  end

  describe "happy: cell count matches Composite::CellMap.for(n)" do
    [ 1, 2, 3, 5, 9 ].each do |n|
      it "renders #{n} cells for an #{n}-game bundle" do
        render_inline(described_class.new(bundle: stub_bundle_with(n)))
        expected_count = Composite::CellMap.for(n).length
        expect(page).to have_css("a.bundle-modal-cell", count: expected_count)
      end
    end
  end

  describe "happy: per-cell inline percentages match CellMap output" do
    [ 1, 2, 3, 5, 9 ].each do |n|
      it "writes left/top/width/height percentages from CellMap for n=#{n}" do
        render_inline(described_class.new(bundle: stub_bundle_with(n)))
        cells = Composite::CellMap.for(n)
        anchors = page.all("a.bundle-modal-cell")

        cells.each_with_index do |cell, i|
          style = anchors[i]["style"]
          expect(style).to include("left: #{cell[:x] * 100}%")
          expect(style).to include("top: #{cell[:y] * 100}%")
          expect(style).to include("width: #{cell[:w] * 100}%")
          expect(style).to include("height: #{cell[:h] * 100}%")
        end
      end
    end
  end

  describe "happy: composite wrapper" do
    it "renders the .bundle-modal-composite wrapper with the 3:4 canvas" do
      render_inline(described_class.new(bundle: stub_bundle_with(1)))
      wrapper = page.find("div.bundle-modal-composite")
      expect(wrapper["style"]).to include("width: 100%")
      expect(wrapper["style"]).to include("aspect-ratio: 3 / 4")
    end

    it "marks each cell with data-turbo-frame=_top so navigation escapes the frame" do
      render_inline(described_class.new(bundle: stub_bundle_with(3)))
      expect(page).to have_css('a.bundle-modal-cell[data-turbo-frame="_top"]', count: 3)
    end

    it "uses the game title as the cell anchor title attribute" do
      bundle = build_stubbed(:bundle)
      game = build_stubbed(:game, title: "Halo Infinite", cover_image_id: "abc")
      allow(bundle).to receive(:games).and_return([ game ])
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css('a.bundle-modal-cell[title="Halo Infinite"]', count: 1)
    end
  end

  describe "happy: cover image rendering" do
    it "renders an <img> when the game has a cover" do
      render_inline(described_class.new(bundle: stub_bundle_with(1)))
      expect(page).to have_css("a.bundle-modal-cell img", count: 1)
    end

    it "omits the <img> when the game is truly coverless" do
      bundle = build_stubbed(:bundle)
      naked = build_stubbed(:game, cover_image_id: nil)
      allow(bundle).to receive(:games).and_return([ naked ])
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_css("a.bundle-modal-cell", count: 1)
      expect(page).to have_no_css("a.bundle-modal-cell img")
    end
  end

  describe "edge: empty bundle renders nothing" do
    it "renders no composite wrapper when the bundle has zero member games" do
      bundle = build_stubbed(:bundle)
      allow(bundle).to receive(:games).and_return([])
      render_inline(described_class.new(bundle: bundle))
      expect(page).to have_no_css("div.bundle-modal-composite")
      expect(page).to have_no_css("a.bundle-modal-cell")
    end

    it "render? returns false so the parent template can branch to the empty placeholder" do
      bundle = build_stubbed(:bundle)
      allow(bundle).to receive(:games).and_return([])
      component = described_class.new(bundle: bundle)
      expect(component.render?).to eq(false)
    end
  end
end
