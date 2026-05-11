require "rails_helper"

# Phase 27 §01h — Collection sub-shelf cover.
#
# Three branches: empty / single (passthrough) / composite. Each branch
# locks fixed-pixel sizing (98 × 130) and forbids the legacy
# `transform: scale` / `width: 100%` patterns. Cursor affordance lives
# on the sub-shelf wrapper, not the image itself.
RSpec.describe "games/_collection_sub_shelf.html.erb", type: :view do
  def render_partial(collection)
    render partial: "games/collection_sub_shelf", locals: { collection: collection }
  end

  describe "0-game collection" do
    let(:collection) { create(:collection, name: "Empty bin") }

    it "renders the [empty] placeholder span" do
      render_partial(collection)
      expect(rendered).to include("[empty]")
      expect(rendered).to include("collection-cover-empty")
    end

    it "uses inline 98 × 130 pixel dimensions on the placeholder" do
      render_partial(collection)
      expect(rendered).to include("width: 98px")
      expect(rendered).to include("height: 130px")
    end

    it "does not render a composite <img>" do
      render_partial(collection)
      expect(rendered).not_to include("collection-cover-composite")
    end
  end

  describe "1-game collection" do
    let(:collection) { create(:collection, name: "Solo") }

    before do
      create(:game, :synced, collection: collection, title: "Solo Game", cover_image_id: "img-solo")
    end

    it "renders a Games::CoverComponent at :shelf variant" do
      render_partial(collection)
      # The component emits an <img> with `game-cover--shelf` class.
      expect(rendered).to include("game-cover--shelf")
    end

    it "does not render the composite <img>" do
      render_partial(collection)
      expect(rendered).not_to include("collection-cover-composite")
    end

    it "does not render the [empty] placeholder" do
      render_partial(collection)
      expect(rendered).not_to include("[empty]")
    end
  end

  describe "2+ game collection (composite URL present)" do
    let(:collection) { create(:collection, name: "Stitched") }

    before do
      2.times do |i|
        create(:game, :synced,
               collection: collection,
               title: "Game #{i}",
               cover_image_id: "img-#{i}")
      end
      collection.update_columns(composite_cover_checksum: "sha123")
    end

    it "renders the composite <img> with the collection.cover_url src" do
      render_partial(collection)
      expect(rendered).to include("collection-cover-composite")
      expect(rendered).to include(%(src="/composites/collection-#{collection.id}.jpg?v=sha123"))
    end

    it "sets width=\"98\" and height=\"130\" as attribute pixels" do
      render_partial(collection)
      expect(rendered).to match(/width="98"/)
      expect(rendered).to match(/height="130"/)
    end

    it "sets loading=\"lazy\"" do
      render_partial(collection)
      expect(rendered).to include('loading="lazy"')
    end

    it "sets alt to the collection name" do
      render_partial(collection)
      expect(rendered).to include(%(alt="Stitched"))
    end

    it "does not render the [empty] placeholder" do
      render_partial(collection)
      expect(rendered).not_to include("[empty]")
    end

    it "does not include inline transform: scale or width: 100%" do
      render_partial(collection)
      expect(rendered).not_to include("transform: scale")
      expect(rendered).not_to include("width: 100%")
    end

    it "does not set cursor: pointer on the image itself" do
      render_partial(collection)
      img_tag = rendered[/<img[^>]*collection-cover-composite[^>]*>/]
      expect(img_tag).not_to include("cursor: pointer") if img_tag
    end
  end

  describe "2+ games but composite_cover_checksum NOT yet stamped" do
    let(:collection) { create(:collection, name: "Pending") }

    before do
      2.times do |i|
        create(:game, :synced,
               collection: collection,
               title: "Game #{i}",
               cover_image_id: "img-#{i}")
      end
      # Composer has not run yet, so cover_url returns nil. The view
      # falls through to the [empty] branch since count >= 2 but
      # composite_url is blank AND count != 1.
    end

    it "falls back to the [empty] placeholder when cover_url is blank" do
      render_partial(collection)
      expect(rendered).to include("[empty]")
      expect(rendered).not_to include("collection-cover-composite")
    end
  end
end
