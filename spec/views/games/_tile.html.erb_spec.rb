require "rails_helper"

# Phase 27 — game tile partial.
#
# The tile renders two explicit caption lines below the cover art:
#
#   line 1: title, truncated with `…` if it exceeds the cover width
#   line 2: `★ <RR> · <YYYY>` — rating zero-padded, year second
#
# The :grid variant (default) and :shelf variant share the same
# layout; the only delta is caption font size. See
# `GamesHelper#game_meta_line` for the metadata composition logic.
RSpec.describe "games/_tile.html.erb", type: :view do
  let(:game) do
    create(:game, :synced,
           title: "Red Dead Redemption 2",
           release_year: 2018,
           igdb_rating: 93,
           igdb_id: 5_000_001,
           igdb_slug: "rdr2")
  end

  def render_tile(game, **locals)
    render partial: "games/tile", locals: { game: game, **locals }
  end

  # ------------------------------------------------------------
  # Happy path — both lines render at the canonical shape.
  # ------------------------------------------------------------

  describe "happy: full metadata renders the locked two-line layout" do
    before { render_tile(game) }

    it "renders the title in `.tile-caption-title`" do
      expect(rendered).to have_css(".tile-caption-title", text: "Red Dead Redemption 2")
    end

    it "renders the metadata line in `.tile-caption-meta`" do
      expect(rendered).to have_css(".tile-caption-meta", text: "★ 93 · 2018")
    end

    it "preserves the outer `.tile-caption` wrapper" do
      # System specs scope by `.tile-caption` for tile navigation;
      # keep the class so they remain green.
      expect(rendered).to have_css(".tile-caption")
    end

    it "places the rating BEFORE the year (reversed from pre-Phase-27 order)" do
      meta = Capybara.string(rendered).find(".tile-caption-meta").text
      expect(meta.index("93")).to be < meta.index("2018")
    end

    it "uses the middle-dot separator between rating and year" do
      expect(rendered).to include("·")
      meta = Capybara.string(rendered).find(".tile-caption-meta").text
      # Middle-dot lives between rating and year.
      expect(meta).to match(/93\s*·\s*2018/)
    end

    it "uses the unicode star glyph (U+2605)" do
      expect(rendered).to include("★")
    end
  end

  # ------------------------------------------------------------
  # Truncation — title gets ellipsis CSS so long titles don't wrap.
  # ------------------------------------------------------------

  describe "happy: title is single-line with ellipsis truncation" do
    it "applies `white-space: nowrap` to the title line" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("white-space: nowrap")
    end

    it "applies `overflow: hidden` to the title line" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("overflow: hidden")
    end

    it "applies `text-overflow: ellipsis` to the title line" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("text-overflow: ellipsis")
    end

    it "constrains the title `max-width` to the 150px cover width" do
      render_tile(game)
      title_node = Capybara.string(rendered).find(".tile-caption-title")
      expect(title_node[:style]).to include("max-width: 150px")
    end

    it "renders an over-long title in full markup (browser truncates via CSS, not the server)" do
      # Server emits the full string; the truncation is a CSS concern.
      long_title = "The Legend of Zelda: Tears of the Kingdom — Master Edition"
      g = create(:game, :synced,
                 title: long_title,
                 release_year: 2023,
                 igdb_rating: 96,
                 igdb_id: 5_000_002,
                 igdb_slug: "totk-master")

      render_tile(g)

      expect(rendered).to include(long_title)
    end
  end

  # ------------------------------------------------------------
  # Rating zero-padding visible in the rendered output.
  # ------------------------------------------------------------

  describe "happy: rating zero-padding is visible in the rendered string" do
    it "renders single-digit rating as two digits — 5 → 05" do
      g = create(:game, :synced,
                 title: "Indie Gem",
                 release_year: 2021,
                 igdb_rating: 5,
                 igdb_id: 5_000_003,
                 igdb_slug: "indie-gem")

      render_tile(g)

      expect(rendered).to include("★ 05 · 2021")
    end

    it "renders two-digit rating as-is — 93" do
      render_tile(game)
      expect(rendered).to include("★ 93")
    end
  end

  # ------------------------------------------------------------
  # Sad / edge — missing rating, missing year, both missing.
  # ------------------------------------------------------------

  describe "edge: rating missing" do
    let(:no_rating) do
      create(:game, :synced,
             title: "Mystery Game",
             release_year: 2020,
             igdb_rating: nil,
             igdb_id: 5_001_001,
             igdb_slug: "mystery-no-rating")
    end

    it "renders the meta line with year only" do
      render_tile(no_rating)
      expect(rendered).to have_css(".tile-caption-meta", text: "2020")
    end

    it "does NOT render the star glyph when rating is missing" do
      render_tile(no_rating)
      meta = Capybara.string(rendered).find(".tile-caption-meta").text
      expect(meta).not_to include("★")
    end

    it "does NOT leave a leading dot when rating is missing" do
      render_tile(no_rating)
      meta = Capybara.string(rendered).find(".tile-caption-meta").text
      expect(meta).not_to start_with("·")
      expect(meta).not_to include("·")
    end
  end

  describe "edge: year missing" do
    let(:no_year) do
      create(:game, :synced,
             title: "Vintage Find",
             release_year: nil,
             igdb_rating: 78,
             igdb_id: 5_001_002,
             igdb_slug: "vintage-no-year")
    end

    it "renders the meta line with `★ <RR>` only" do
      render_tile(no_year)
      expect(rendered).to have_css(".tile-caption-meta", text: "★ 78")
    end

    it "does NOT leave a trailing dot when year is missing" do
      render_tile(no_year)
      meta = Capybara.string(rendered).find(".tile-caption-meta").text
      expect(meta).not_to end_with("·")
      expect(meta).not_to include("·")
    end
  end

  describe "edge: rating and year both missing" do
    let(:naked) do
      create(:game, :synced,
             title: "Blank Slate",
             release_year: nil,
             igdb_rating: nil,
             igdb_id: 5_001_003,
             igdb_slug: "blank-slate")
    end

    it "omits the entire meta line" do
      render_tile(naked)
      expect(rendered).not_to have_css(".tile-caption-meta")
    end

    it "still renders the title line" do
      render_tile(naked)
      expect(rendered).to have_css(".tile-caption-title", text: "Blank Slate")
    end
  end

  # ------------------------------------------------------------
  # Variant defaults + shelf-variant typography.
  # ------------------------------------------------------------

  describe "variant defaults" do
    it "defaults to :grid when no variant is provided" do
      render_tile(game)
      expect(rendered).to include('data-variant="grid"')
      expect(rendered).to have_css("a.tile.tile--grid")
    end

    it "accepts variant: :shelf and stamps it on the wrapper" do
      render_tile(game, variant: :shelf)
      expect(rendered).to include('data-variant="shelf"')
      expect(rendered).to have_css("a.tile.tile--shelf")
    end
  end

  describe ":shelf variant uses smaller caption typography" do
    it "shrinks the title font size to 10px under :shelf" do
      render_tile(game, variant: :shelf)
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node[:style]).to include("font-size: 10px")
    end

    it "shrinks the meta font size to 9px under :shelf" do
      render_tile(game, variant: :shelf)
      meta_node = Capybara.string(rendered).find(".tile-caption-meta")
      expect(meta_node[:style]).to include("font-size: 9px")
    end

    it "keeps the grid variant at 11px for the caption" do
      render_tile(game, variant: :grid)
      caption_node = Capybara.string(rendered).find(".tile-caption")
      expect(caption_node[:style]).to include("font-size: 11px")
    end

    it "keeps the grid variant at 10px for the meta line" do
      render_tile(game, variant: :grid)
      meta_node = Capybara.string(rendered).find(".tile-caption-meta")
      expect(meta_node[:style]).to include("font-size: 10px")
    end
  end

  # ------------------------------------------------------------
  # Linking + keyboard wiring unchanged.
  # ------------------------------------------------------------

  describe "tile remains a single anchor wrapping cover + caption" do
    it "links to game_path(game)" do
      render_tile(game)
      anchor = Capybara.string(rendered).find("a.tile")
      expect(anchor[:href]).to eq(game_path(game))
    end

    it "stamps data-tile-game-id" do
      render_tile(game)
      expect(rendered).to include(%(data-tile-game-id="#{game.id}"))
    end

    it "opts into keyboard grid navigation via data-keyboard-tile" do
      render_tile(game)
      expect(rendered).to include("data-keyboard-tile")
    end

    it "sets the native title attribute to title + meta line" do
      render_tile(game)
      anchor = Capybara.string(rendered).find("a.tile")
      expect(anchor[:title]).to include("Red Dead Redemption 2")
      expect(anchor[:title]).to include("★ 93 · 2018")
    end
  end

  # ------------------------------------------------------------
  # Flaw assertions — no legacy single-line caption, no reversed
  # order remnants.
  # ------------------------------------------------------------

  describe "flaw: pre-Phase-27 single-line caption layout is gone" do
    before { render_tile(game) }

    it "does NOT render the legacy `(2018) ★ 93` ordering" do
      expect(rendered).not_to include("(2018) ★ 93")
    end

    it "does NOT render the year parenthesized in the visible caption" do
      meta = Capybara.string(rendered).find(".tile-caption-meta").text
      expect(meta).not_to include("(2018)")
      expect(meta).not_to include("(")
    end
  end

  # ------------------------------------------------------------
  # `item:` alias still works (collection rendering convention).
  # ------------------------------------------------------------

  describe "happy: accepts `item:` local for collection rendering" do
    it "renders the same tile when passed via `item:`" do
      render partial: "games/tile", locals: { item: game }
      expect(rendered).to have_css(".tile-caption-title", text: "Red Dead Redemption 2")
      expect(rendered).to have_css(".tile-caption-meta", text: "★ 93 · 2018")
    end
  end
end
