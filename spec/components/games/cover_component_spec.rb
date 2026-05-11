require "rails_helper"

# Phase 27 sub-spec 01e — Games::CoverComponent.
#
# The component is the single source-of-truth for cover-art
# rendering at two server-side variants: `:grid` (150 × 200) and
# `:shelf` (98 × 130). The shelf variant comes from a different
# IGDB CDN size token (`t_cover_small_2x`) — a different URL, a
# different cache key, NOT a CSS-scaled grid asset.
RSpec.describe Games::CoverComponent, type: :component do
  let(:game) { build_stubbed(:game, :synced, cover_image_id: "abc123", title: "Test Game") }

  # ------------------------------------------------------------
  # Happy path — both variants render with the right shape.
  # ------------------------------------------------------------

  describe "happy: variant :grid" do
    before { render_inline(described_class.new(game: game, variant: :grid)) }

    it "renders an <img> with width=150 height=200" do
      expect(page).to have_css('img[width="150"][height="200"]')
    end

    it "renders the t_cover_big IGDB URL" do
      img = page.find("img")
      expect(img["src"]).to eq("https://images.igdb.com/igdb/image/upload/t_cover_big/abc123.jpg")
    end

    it "sets data-variant=grid on the wrapper" do
      expect(page).to have_css('a[data-variant="grid"]')
    end

    it "sets data-variant=grid on the <img>" do
      expect(page).to have_css('img[data-variant="grid"]')
    end

    it "applies the .game-cover--grid CSS modifier" do
      expect(page).to have_css("a.game-cover.game-cover--grid")
    end

    it "wraps in an <a> to the game show page by default" do
      expect(page).to have_css("a[href]")
      anchor = page.find("a.game-cover")
      expect(anchor["href"]).to include("/games/")
    end

    it "sets the alt text to the game title" do
      expect(page).to have_css('img[alt="Test Game"]')
    end

    it "sets loading=lazy on the <img>" do
      expect(page).to have_css('img[loading="lazy"]')
    end
  end

  describe "happy: variant :shelf" do
    before { render_inline(described_class.new(game: game, variant: :shelf)) }

    it "renders an <img> with width=98 height=130" do
      expect(page).to have_css('img[width="98"][height="130"]')
    end

    it "renders the t_cover_small_2x IGDB URL" do
      img = page.find("img")
      expect(img["src"]).to eq("https://images.igdb.com/igdb/image/upload/t_cover_small_2x/abc123.jpg")
    end

    it "sets data-variant=shelf on the wrapper" do
      expect(page).to have_css('a[data-variant="shelf"]')
    end

    it "sets data-variant=shelf on the <img>" do
      expect(page).to have_css('img[data-variant="shelf"]')
    end

    it "applies the .game-cover--shelf CSS modifier" do
      expect(page).to have_css("a.game-cover.game-cover--shelf")
    end

    it "sets the alt text to the game title" do
      expect(page).to have_css('img[alt="Test Game"]')
    end

    it "sets loading=lazy on the <img>" do
      expect(page).to have_css('img[loading="lazy"]')
    end

    it "emits the variant inline width/height on the wrapper" do
      wrapper = page.find("a.game-cover")
      expect(wrapper["style"]).to include("width: 98px")
      expect(wrapper["style"]).to include("height: 130px")
    end

    it "renders the wrapper class as exactly 'game-cover game-cover--shelf'" do
      wrapper = page.find("a.game-cover")
      expect(wrapper[:class]).to eq("game-cover game-cover--shelf")
    end
  end

  describe "happy: variant URLs differ between :grid and :shelf (distinct cache keys)" do
    it "grid and shelf produce different src URLs" do
      render_inline(described_class.new(game: game, variant: :grid))
      grid_src = page.find("img")["src"]

      # Re-render with shelf variant in a fresh page.
      render_inline(described_class.new(game: game, variant: :shelf))
      shelf_src = page.find("img")["src"]

      expect(grid_src).not_to eq(shelf_src)
      expect(grid_src).to include("t_cover_big")
      expect(shelf_src).to include("t_cover_small_2x")
    end
  end

  # ------------------------------------------------------------
  # Defaults — :grid is the default variant.
  # ------------------------------------------------------------

  describe "happy: default variant is :grid" do
    it "defaults to :grid when variant is omitted" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("a.game-cover--grid")
      expect(page).to have_css('img[width="150"][height="200"]')
    end
  end

  # ------------------------------------------------------------
  # Sad — unknown variant raises.
  # ------------------------------------------------------------

  describe "sad: unknown variant" do
    it "raises ArgumentError" do
      expect {
        described_class.new(game: game, variant: :ginormous)
      }.to raise_error(ArgumentError, /Unknown cover variant/)
    end

    it "lists the valid variant set in the error message" do
      expect {
        described_class.new(game: game, variant: :foo)
      }.to raise_error(ArgumentError, /grid.*shelf|shelf.*grid/)
    end
  end

  # ------------------------------------------------------------
  # Edge — game with no cover renders a placeholder at the
  # variant's dimensions.
  # ------------------------------------------------------------

  describe "edge: game with no cover_image_id" do
    let(:naked_game) { build_stubbed(:game, cover_image_id: nil, title: "Naked") }

    it "renders [no cover] placeholder at :grid dimensions" do
      render_inline(described_class.new(game: naked_game, variant: :grid))
      expect(page).to have_css("span.game-cover-missing", text: "[no cover]")
      expect(page).to have_no_css("img")
    end

    it "renders [no cover] placeholder at :shelf dimensions" do
      render_inline(described_class.new(game: naked_game, variant: :shelf))
      expect(page).to have_css("span.game-cover-missing", text: "[no cover]")
      expect(page).to have_no_css("img")
    end

    it "still applies the variant CSS class to the wrapper so the slot is sized" do
      render_inline(described_class.new(game: naked_game, variant: :shelf))
      expect(page).to have_css("a.game-cover--shelf")
    end

    it "still emits the variant inline width/height on the wrapper as a belt-and-braces fallback" do
      render_inline(described_class.new(game: naked_game, variant: :shelf))
      wrapper = page.find("a.game-cover")
      expect(wrapper["style"]).to include("width: 98px")
      expect(wrapper["style"]).to include("height: 130px")
    end
  end

  # ------------------------------------------------------------
  # link_to_show — when false, renders a non-anchor wrapper.
  # ------------------------------------------------------------

  describe "happy: link_to_show: false" do
    it "renders a <div> wrapper instead of <a>" do
      render_inline(described_class.new(game: game, variant: :shelf, link_to_show: false))
      expect(page).to have_css("div.game-cover.game-cover--shelf")
      expect(page).to have_no_css("a.game-cover")
    end

    it "still sets data-variant on the wrapper" do
      render_inline(described_class.new(game: game, variant: :shelf, link_to_show: false))
      expect(page).to have_css('div[data-variant="shelf"]')
    end
  end

  # ------------------------------------------------------------
  # Flaw assertions — the spec explicitly forbids CSS scaling
  # tricks. No `transform: scale`, no `width: 65%`.
  # ------------------------------------------------------------

  describe "flaw: no CSS scaling tricks" do
    it ":shelf does not emit inline transform: scale" do
      render_inline(described_class.new(game: game, variant: :shelf))
      expect(page.native.to_html).not_to match(/transform\s*:\s*scale/i)
    end

    it ":shelf does not emit inline width:65% (or any percentage width)" do
      render_inline(described_class.new(game: game, variant: :shelf))
      wrapper = page.find("a.game-cover")
      expect(wrapper["style"]).not_to match(/width\s*:\s*\d+%/)
    end

    it ":shelf does not emit zoom: tricks" do
      render_inline(described_class.new(game: game, variant: :shelf))
      expect(page.native.to_html).not_to match(/zoom\s*:/i)
    end
  end

  # ------------------------------------------------------------
  # Friendly URL preservation — anchor href uses Game#to_param.
  # ------------------------------------------------------------

  describe "friendly URL preservation" do
    it "uses the igdb_slug in the anchor href when present" do
      slugged = build_stubbed(:game, :synced, cover_image_id: "xyz", igdb_slug: "halo-infinite")
      render_inline(described_class.new(game: slugged, variant: :grid))
      anchor = page.find("a.game-cover")
      expect(anchor["href"]).to eq("/games/halo-infinite")
    end

    it "falls back to the id when igdb_slug is blank" do
      idy = build_stubbed(:game, cover_image_id: "xyz", igdb_slug: nil, id: 42)
      render_inline(described_class.new(game: idy, variant: :grid))
      anchor = page.find("a.game-cover")
      expect(anchor["href"]).to eq("/games/42")
    end
  end

  # ------------------------------------------------------------
  # Variant introspection — public API tested directly so 01c /
  # 01d can rely on the constant for downstream sizing decisions
  # (e.g. shelf-row min-height calc).
  # ------------------------------------------------------------

  describe "::DIMENSIONS constant" do
    it "exposes :grid at 150 x 200" do
      dim = described_class::DIMENSIONS.fetch(:grid)
      expect(dim[:width]).to eq(150)
      expect(dim[:height]).to eq(200)
    end

    it "exposes :shelf at 98 x 130 (65% of grid)" do
      dim = described_class::DIMENSIONS.fetch(:shelf)
      expect(dim[:width]).to eq(98)
      expect(dim[:height]).to eq(130)
    end

    it "shelf is roughly 65% of grid in both dimensions" do
      g = described_class::DIMENSIONS.fetch(:grid)
      s = described_class::DIMENSIONS.fetch(:shelf)
      width_ratio = s[:width].to_f / g[:width]
      height_ratio = s[:height].to_f / g[:height]
      expect(width_ratio).to be_within(0.01).of(0.65)
      expect(height_ratio).to be_within(0.01).of(0.65)
    end

    it "maps :grid to the t_cover_big IGDB token" do
      expect(described_class::DIMENSIONS.fetch(:grid)[:igdb_size]).to eq("t_cover_big")
    end

    it "maps :shelf to the t_cover_small_2x IGDB token" do
      expect(described_class::DIMENSIONS.fetch(:shelf)[:igdb_size]).to eq("t_cover_small_2x")
    end
  end

  describe "::VARIANTS" do
    it "lists both supported variants" do
      expect(described_class::VARIANTS).to contain_exactly(:grid, :shelf)
    end
  end
end
