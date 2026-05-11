require "rails_helper"

# Phase 27 §01c-v2 — Collection sub-shelf row.
#
# `<h3>` + optional `[see all]` link + horizontal scrolling row with a
# leading composite cover tile (from the 01h _collection_sub_shelf
# partial) followed by individual game tiles at the `:shelf` cover
# variant. Cap 30, alphabetical by `LOWER(games.title)`.
RSpec.describe "games/_collection_sub_shelf_row.html.erb", type: :view do
  def render_partial(collection)
    render partial: "games/collection_sub_shelf_row", locals: { collection: collection }
  end

  let!(:collection) { create(:collection, name: "My favorites") }

  describe "happy: collection with 2+ games + composite stamped" do
    let!(:abzu)  { create(:game, :synced, title: "ABZU",        cover_image_id: "img-abzu",  collection: collection) }
    let!(:tunic) { create(:game, :synced, title: "Tunic",       cover_image_id: "img-tunic", collection: collection) }
    let!(:zelda) { create(:game, :synced, title: "Zelda BotW",  cover_image_id: "img-zelda", collection: collection) }

    before do
      collection.update_columns(composite_cover_checksum: "sha-abc")
    end

    it "renders an <h3> with the collection name" do
      render_partial(collection)
      expect(rendered).to match(%r{<h3[^>]*>\s*My favorites\s*</h3>})
    end

    it "renders the leading composite cover <img> first in the row" do
      render_partial(collection)
      expect(rendered).to include("collection-cover-composite")
      expect(rendered).to include(%(src="/composites/collection-#{collection.id}.jpg?v=sha-abc"))
    end

    it "renders one shelf-variant cover tile per game" do
      render_partial(collection)
      expect(rendered.scan('game-cover--shelf').length).to eq(3)
    end

    it "orders game tiles alphabetical case-insensitive by title" do
      render_partial(collection)
      # Filter to just the game-tile region — the composite <img> uses
      # the same `img-abzu` cover id and would confuse the order check.
      tile_region = rendered.split('class="shelf-row sub-shelf-row"').last
      indexes = [ "ABZU", "Tunic", "Zelda BotW" ].map { |t| tile_region.index(t) }
      expect(indexes).to eq(indexes.compact.sort)
    end

    it "leading composite-cover anchor links to /collections/<slug>" do
      render_partial(collection)
      expect(rendered).to include(%(href="/collections/#{collection.slug}"))
    end

    it "stamps the steam-shelf Stimulus controller on the sub-shelf wrapper" do
      render_partial(collection)
      expect(rendered).to include('data-controller="steam-shelf"')
      expect(rendered).to include('data-shelf="collection-sub"')
    end

    it "does NOT render `[see all]` when under the cap" do
      render_partial(collection)
      expect(rendered).not_to include(">see all<")
    end
  end

  describe "happy: collection with 1 game (passthrough cover, no composite)" do
    let!(:solo) { create(:game, :synced, title: "Solo Game", cover_image_id: "img-solo", collection: collection) }

    it "renders the <h3>" do
      render_partial(collection)
      expect(rendered).to match(%r{<h3[^>]*>\s*My favorites\s*</h3>})
    end

    it "leading tile is a single :shelf cover (passthrough), not a composite <img>" do
      render_partial(collection)
      expect(rendered).not_to include("collection-cover-composite")
      # The single-game branch of the 01h partial emits a
      # Games::CoverComponent at :shelf variant.
      expect(rendered.scan('game-cover--shelf').length).to be >= 1
    end

    it "renders the single game as the trailing tile too (passthrough leading + tile)" do
      render_partial(collection)
      # One :shelf tile from the leading passthrough + one :shelf tile
      # in the game row = 2 occurrences.
      expect(rendered.scan('game-cover--shelf').length).to eq(2)
    end
  end

  describe "happy: collection with 0 games" do
    it "renders the <h3> heading" do
      render_partial(collection)
      expect(rendered).to match(%r{<h3[^>]*>\s*My favorites\s*</h3>})
    end

    it "leading tile renders the [empty] placeholder (composite checksum blank)" do
      render_partial(collection)
      expect(rendered).to include("[empty]")
      expect(rendered).to include("collection-cover-empty")
    end

    it "renders no game tiles" do
      render_partial(collection)
      expect(rendered).not_to include("game-cover--shelf")
    end

    it "does NOT render `[see all]`" do
      render_partial(collection)
      expect(rendered).not_to include(">see all<")
    end
  end

  describe "edge: 31 games (over cap)" do
    before do
      31.times do |i|
        create(:game, :synced, title: format("%04d game", i + 1), collection: collection)
      end
      collection.update_columns(composite_cover_checksum: "sha-cap")
    end

    it "renders exactly 30 game tiles (capped)" do
      render_partial(collection)
      # 30 game tiles + 0 from the composite branch (composite is an
      # <img> with `collection-cover-composite`, not a game-cover--shelf).
      expect(rendered.scan('game-cover--shelf').length).to eq(30)
    end

    it "renders the `[see all]` bracketed link" do
      render_partial(collection)
      expect(rendered).to include(">see all<")
    end

    it "`[see all]` href targets /games?collection=<slug>" do
      render_partial(collection)
      expect(rendered).to include(%(href="#{games_path(collection: collection.slug)}"))
    end
  end

  describe "flaw: no JS confirm / alert affordances" do
    let!(:solo) { create(:game, :synced, title: "Solo", collection: collection) }

    it "does NOT include data-turbo-confirm anywhere in the sub-shelf" do
      render_partial(collection)
      expect(rendered).not_to include("data-turbo-confirm")
    end

    it "does NOT include a <script> tag" do
      render_partial(collection)
      expect(rendered).not_to include("<script")
    end
  end
end
