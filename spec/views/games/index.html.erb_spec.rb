require "rails_helper"

# Phase 27 v2 spec 05 — `/games` index view structure.
#
# Asserts the top-level rendering order: page title → filter row →
# bundles (when present) → recently-played (when present) → hairline
# → genres outer shelf (when populated) → hairline → collections
# outer shelf (when populated) → hairline → letter shelves (when
# populated). Empty branches drop out cleanly.
RSpec.describe "games/index.html.erb", type: :view do
  before do
    # Minimum controller-assigned instance variables. The view reads
    # them directly; nil defaults short-circuit empty branches.
    assign(:bundles_shelf, Bundle.none)
    assign(:recently_played, Game.none)
    assign(:genres_for_shelf, Genre.none)
    assign(:collections_for_shelf, Collection.none)
    assign(:genres_shelf_batch, Games::GenreShelfBatch.new(genres: Genre.none))
    assign(:filter_tokens, [])
    assign(:dropped_filter_tokens, [])
    assign(:filter_contradiction, false)
    assign(:letter_buckets, [])
  end

  describe "happy: empty install (no games, no shelves)" do
    it "renders the empty-state copy" do
      render
      expect(rendered).to include("no games yet.")
    end

    it "renders the page title and [+] add link" do
      render
      expect(rendered).to include("<h1>games</h1>")
      expect(rendered).to match(/\[<span class="bl">\+<\/span>\]/)
    end

    it "always renders the filter row even when the install is empty" do
      render
      expect(rendered).to include('class="games-filter-row')
    end

    it "does NOT render any letter shelves wrapper" do
      render
      expect(rendered).not_to include('class="all-games-shelves-by-letter')
    end

    it "does NOT render the bundles shelf when no bundles exist" do
      render
      expect(rendered).not_to include(">bundles<")
    end

    it "does NOT render the genres outer shelf when no genres own games" do
      render
      expect(rendered).not_to include('data-shelf="outer-genres"')
    end
  end

  describe "happy: full library with games across multiple letters" do
    let!(:alpha) do
      create(:game, :synced, title: "Alpha Game",
             igdb_id: 5_001, igdb_slug: "alpha-index-view")
    end
    let!(:mango) do
      create(:game, :synced, title: "Mango Quest",
             igdb_id: 5_002, igdb_slug: "mango-index-view")
    end
    let!(:digit) do
      create(:game, :synced, title: "7 Days to Die",
             igdb_id: 5_003, igdb_slug: "seven-days-index-view")
    end

    before do
      assign(:letter_buckets, [
        [ "A", [ alpha ] ],
        [ "M", [ mango ] ],
        [ "#", [ digit ] ]
      ])
    end

    it "renders the letter shelves wrapper" do
      render
      expect(rendered).to include('class="all-games-shelves-by-letter')
    end

    it "renders exactly three letter shelves (A, M, #)" do
      render
      expect(rendered.scan('data-shelf="letter"').length).to eq(3)
    end

    it "places the page title BEFORE the filter row" do
      render
      title_pos  = rendered.index("<h1>games</h1>")
      filter_pos = rendered.index('class="games-filter-row')
      expect(title_pos).not_to be_nil
      expect(filter_pos).not_to be_nil
      expect(title_pos).to be < filter_pos
    end

    it "places the filter row BEFORE the letter shelves wrapper" do
      render
      filter_pos  = rendered.index('class="games-filter-row')
      letters_pos = rendered.index('class="all-games-shelves-by-letter')
      expect(filter_pos).not_to be_nil
      expect(letters_pos).not_to be_nil
      expect(filter_pos).to be < letters_pos
    end

    it "does NOT render the legacy `<h2>all</h2>` heading anywhere" do
      render
      expect(rendered).not_to match(%r{<h2[^>]*>\s*all\s*</h2>})
    end

    it "does NOT render any `data-display-mode=` attribute" do
      render
      expect(rendered).not_to include("data-display-mode=")
    end

    it "does NOT render the display-mode switcher" do
      render
      expect(rendered).not_to include('class="display-mode-switcher"')
    end
  end

  describe "happy: bundles + recently-played shelves above the genres" do
    let!(:bundle)        { create(:bundle, name: "Soulslikes") }
    let!(:recent_game)   { create(:game, :synced, title: "Recent Game", igdb_id: 5_101, igdb_slug: "recent-idx", played_at: 1.day.ago) }

    before do
      assign(:bundles_shelf,   Bundle.where(id: bundle.id))
      assign(:recently_played, Game.where(id: recent_game.id))
    end

    it "renders the bundles shelf" do
      render
      expect(rendered).to include(">bundles<")
    end

    it "renders the recently-played shelf" do
      render
      expect(rendered).to include(">recently played<")
    end

    it "places bundles BEFORE recently-played in document order" do
      render
      b_pos = rendered.index(">bundles<")
      r_pos = rendered.index(">recently played<")
      expect(b_pos).to be < r_pos
    end
  end
end
