require "rails_helper"

# Phase 27 v2 spec 05 / Phase 27 follow-up (2026-05-17) — `/games`
# index view structure.
#
# Asserts the top-level rendering order: page title → filter row →
# recently-played (when present) → hairline → genres outer shelf
# (when populated) → hairline → bundles outer shelf (when populated)
# → hairline → letter shelves (when populated). Empty branches drop
# out cleanly. The legacy top-of-page bundles shelf was merged into
# the bundles outer shelf in the 2026-05-17 consolidation.
RSpec.describe "games/index.html.erb", type: :view do
  before do
    # Minimum controller-assigned instance variables. The view reads
    # them directly; nil defaults short-circuit empty branches.
    assign(:recently_played, Game.none)
    assign(:genres_for_shelf, Genre.none)
    assign(:bundles_for_shelf, Bundle.none)
    assign(:genres_shelf_batch, Games::GenreShelfBatch.new(genres: Genre.none))
    # Phase 27 v2 spec 06 — view reads `@checked_tokens` (the set of
    # CHECKED chips). Nil means "every chip checked" (full list).
    assign(:checked_tokens, Games::FiltersHelper::TOKEN_UNIVERSE)
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

    it "wraps the listing partition in a turbo-frame#games_listing (Phase 27 v2 spec 06)" do
      render
      expect(rendered).to match(%r{<turbo-frame[^>]+id="games_listing"})
    end

    it "renders the filter row OUTSIDE the games_listing frame (Phase 27 v2 spec 06)" do
      render
      filter_idx = rendered.index('class="games-filter-row')
      frame_idx  = rendered.index('id="games_listing"')
      expect(filter_idx).not_to be_nil
      expect(frame_idx).not_to be_nil
      expect(filter_idx).to be < frame_idx
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

    # 2026-05-17 layout-alignment regression — the title + filter band
    # used to sit inside a `max-width: 1100px` wrapper while the
    # shelves frame broke out via `.games-shelves-fullwidth`. The
    # corrected layout drops BOTH so every row aligns with the
    # layout's chrome (`<main style="padding: 16px 12px 8px 12px;">`
    # in `application.html.erb`).
    it "does NOT clamp the title + filter band with a max-width: 1100px wrapper" do
      render
      expect(rendered).not_to include("max-width: 1100px")
    end

    it "does NOT wrap the shelves frame in a viewport-breakout container" do
      render
      expect(rendered).not_to include("games-shelves-fullwidth")
    end

    it "places the filter row INSIDE the same wrapper as the title and the shelves frame" do
      render
      title_pos  = rendered.index("<h1>games</h1>")
      filter_pos = rendered.index('class="games-filter-row')
      frame_pos  = rendered.index('id="games_listing"')
      expect(title_pos).not_to be_nil
      expect(filter_pos).not_to be_nil
      expect(frame_pos).not_to be_nil
      # All three live inside the same outer `<div>` opened just after
      # the `content_for(:title, …)` call.
      expect(title_pos).to be < filter_pos
      expect(filter_pos).to be < frame_pos
    end

    it "renders the filter row with justify-content: space-between for chrome-aligned chip groups" do
      render
      expect(rendered).to include("justify-content: space-between")
    end

    it "does NOT push the right platform-chip group with margin-left: auto (superseded by space-between)" do
      render
      # The right-side `<div>` no longer carries `margin-left: auto`.
      # The parent flex container's `justify-content: space-between`
      # owns the layout instead.
      expect(rendered).not_to match(/class="games-filter-row__right"[^>]*margin-left:\s*auto/)
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

  describe "happy: bundles outer shelf + recently-played shelf" do
    let!(:bundle)      { create(:bundle, name: "Soulslikes") }
    let!(:member)      { create(:game, :synced, title: "S", igdb_id: 5_200, igdb_slug: "s-idx") }
    let!(:recent_game) { create(:game, :synced, title: "Recent Game", igdb_id: 5_101, igdb_slug: "recent-idx", played_at: 1.day.ago) }

    before do
      bundle.bundle_members.create!(game: member)
      assign(:bundles_for_shelf, Bundle.where(id: bundle.id))
      assign(:recently_played, Game.where(id: recent_game.id))
    end

    it "renders the bundles outer shelf" do
      render
      expect(rendered).to include(">bundles<")
    end

    it "renders the recently-played shelf" do
      render
      expect(rendered).to include(">recently played<")
    end

    it "places recently-played BEFORE bundles outer shelf in document order" do
      # After the 2026-05-17 consolidation the only bundles shelf lives
      # in the bottom outer-shelf slot; recently-played stays at the
      # top of the listing partition.
      render
      r_pos = rendered.index(">recently played<")
      b_pos = rendered.index(">bundles<")
      expect(r_pos).to be < b_pos
    end
  end
end
