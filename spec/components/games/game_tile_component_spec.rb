require "rails_helper"

# Wave B6 VC — Games::GameTileComponent.
#
# Rich game tile, extracted from `app/views/games/_tile.html.erb` and
# now the canonical rendering surface for `/games` (grid + letter
# shelves) and `/bundles/:id` (grid). Coverage focus:
#
#   * Cover render path (IGDB `t_cover_big` when present, theme-aware
#     SVG fallback when absent).
#   * Variant typography (caption font sizes; `data-variant` data-attr).
#   * Platform chip overlay (`tile_chip_slugs` walk + slugs rendered
#     via `Platforms::ChipComponent`).
#   * Title caption (ellipsis CSS, not-released bold class, title-
#     tooltip stimulus wiring).
#   * Parent-pointer line on edition tiles + editions badge on primaries.
#   * Tile-grid / keyboard / turbo-frame data-attrs.
RSpec.describe Games::GameTileComponent, type: :component do
  let(:game) do
    build_stubbed(:game, :synced,
                  id: 7777,
                  title: "Test Game",
                  cover_image_id: "abc123",
                  release_date: Date.new(2020, 1, 1))
  end

  # ----------------------------------------------------------------
  # Variants — :grid is the default; only :grid + :shelf are legal.
  # ----------------------------------------------------------------

  describe "::VARIANTS" do
    it "lists both supported variants" do
      expect(described_class::VARIANTS).to contain_exactly(:grid, :shelf)
    end
  end

  describe "variant validation" do
    it "defaults to :grid" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css('a[data-variant="grid"]')
    end

    it "accepts :shelf explicitly" do
      render_inline(described_class.new(game: game, variant: :shelf))
      expect(page).to have_css('a[data-variant="shelf"]')
    end

    it "coerces string variants to symbols" do
      render_inline(described_class.new(game: game, variant: "shelf"))
      expect(page).to have_css('a[data-variant="shelf"]')
    end

    it "raises on unknown variant" do
      expect {
        described_class.new(game: game, variant: :ginormous)
      }.to raise_error(ArgumentError, /Unknown variant/)
    end
  end

  # ----------------------------------------------------------------
  # Anchor wrapper — href, classes, turbo + keyboard data hooks.
  # ----------------------------------------------------------------

  describe "anchor wrapper" do
    before { render_inline(described_class.new(game: game, variant: :grid)) }

    it "renders an <a> wrapping the tile" do
      expect(page).to have_css("a.tile")
    end

    it "applies a variant-suffixed CSS class" do
      expect(page).to have_css("a.tile.tile--grid")
    end

    it "links to the game show page" do
      anchor = page.find("a.tile")
      expect(anchor["href"]).to include("/games/")
      expect(anchor["href"]).to include(game.to_param)
    end

    it "sets data-tile-game-id to the game id" do
      anchor = page.find("a.tile")
      expect(anchor["data-tile-game-id"]).to eq(game.id.to_s)
    end

    it "opts into the keyboard-grid traversal" do
      anchor = page.find("a.tile")
      expect(anchor).to have_selector(:xpath, "self::*[@data-keyboard-tile]")
    end

    it "escapes the games_listing Turbo Frame with data-turbo-frame=_top" do
      anchor = page.find("a.tile")
      expect(anchor["data-turbo-frame"]).to eq("_top")
    end

    it "pins the wrapper to the 150px flex slot" do
      anchor = page.find("a.tile")
      expect(anchor["style"]).to include("width: 150px")
      expect(anchor["style"]).to include("cursor: pointer")
    end
  end

  describe "shelf variant CSS modifier" do
    it "applies tile--shelf when variant: :shelf" do
      render_inline(described_class.new(game: game, variant: :shelf))
      expect(page).to have_css("a.tile.tile--shelf")
    end
  end

  # ----------------------------------------------------------------
  # Cover rendering — IGDB url when cover_image_id, theme-aware
  # fallback otherwise.
  # ----------------------------------------------------------------

  describe "happy: game with cover_image_id" do
    before { render_inline(described_class.new(game: game, variant: :grid)) }

    it "renders the IGDB t_cover_big URL inside the cover slot" do
      img = page.find(".tile-cover img")
      expect(img["src"]).to eq("https://images.igdb.com/igdb/image/upload/t_cover_big/abc123.jpg")
    end

    it "uses the game title as alt text" do
      img = page.find(".tile-cover img")
      expect(img["alt"]).to eq("Test Game")
    end

    it "loads the cover lazily" do
      img = page.find(".tile-cover img")
      expect(img["loading"]).to eq("lazy")
    end

    it "does NOT emit the theme-aware SVG fallback" do
      expect(page).to have_no_css("img.game-cover-fallback")
    end
  end

  describe "edge: game with no cover" do
    let(:naked) do
      build_stubbed(:game, id: 9999, title: "Naked Game",
                           cover_image_id: nil, release_date: Date.new(2020, 1, 1))
    end

    before { render_inline(described_class.new(game: naked, variant: :grid)) }

    it "does NOT emit the IGDB URL" do
      expect(page.native.to_html).not_to include("images.igdb.com")
    end

    it "emits both theme-variant fallback SVGs" do
      expect(page).to have_css("img.game-cover-fallback--light", count: 1)
      expect(page).to have_css("img.game-cover-fallback--dark", count: 1)
    end

    it "tags fallback images with data-theme" do
      expect(page).to have_css('img[data-theme="light"]')
      expect(page).to have_css('img[data-theme="dark"]')
    end

    it "lazy-loads the fallback images" do
      page.all("img.game-cover-fallback").each do |img|
        expect(img["loading"]).to eq("lazy")
      end
    end
  end

  # ----------------------------------------------------------------
  # Title caption — ellipsis hooks, tooltip wiring, not-released
  # bolding.
  # ----------------------------------------------------------------

  describe "title caption" do
    before { render_inline(described_class.new(game: game, variant: :grid)) }

    it "renders the title inside .tile-caption-title" do
      expect(page).to have_css(".tile-caption-title", text: "Test Game")
    end

    it "applies the ellipsis CSS for long titles" do
      el = page.find(".tile-caption-title")
      expect(el["style"]).to include("text-overflow: ellipsis")
      expect(el["style"]).to include("white-space: nowrap")
      expect(el["style"]).to include("overflow: hidden")
      expect(el["style"]).to include("max-width: 150px")
    end

    it "wires the title-tooltip Stimulus controller" do
      el = page.find(".tile-caption-title")
      expect(el["data-controller"]).to eq("title-tooltip")
      expect(el["data-title-tooltip-full-title-value"]).to eq("Test Game")
    end
  end

  describe "title caption font sizes (variant typography)" do
    it "sizes caption at 11px in :grid" do
      render_inline(described_class.new(game: game, variant: :grid))
      expect(page.find(".tile-caption")["style"]).to include("font-size: 11px")
    end

    it "sizes caption at 10px in :shelf" do
      render_inline(described_class.new(game: game, variant: :shelf))
      expect(page.find(".tile-caption")["style"]).to include("font-size: 10px")
    end
  end

  describe "not-released bolding" do
    it "applies .not-released when release_date is in the future" do
      future = build_stubbed(:game, :synced, title: "Future Game",
                                             cover_image_id: "abc",
                                             release_date: Date.current + 90.days)
      render_inline(described_class.new(game: future))
      el = page.find(".tile-caption-title")
      expect(el[:class]).to include("not-released")
      expect(el["style"]).to include("font-weight: bold")
    end

    it "applies .not-released when release_date is nil" do
      undated = build_stubbed(:game, :synced, title: "Undated Game",
                                              cover_image_id: "abc",
                                              release_date: nil)
      render_inline(described_class.new(game: undated))
      el = page.find(".tile-caption-title")
      expect(el[:class]).to include("not-released")
    end

    it "does NOT bold a released game" do
      released = build_stubbed(:game, :synced, title: "Released",
                                               cover_image_id: "abc",
                                               release_date: Date.current - 30.days)
      render_inline(described_class.new(game: released))
      el = page.find(".tile-caption-title")
      expect(el[:class]).not_to include("not-released")
    end
  end

  # ----------------------------------------------------------------
  # Platform chip overlay — bottom-right of the cover, walked in
  # `PlatformLogosHelper::KNOWN_LOGOS` declaration order, rendered
  # via `Platforms::ChipComponent`.
  # ----------------------------------------------------------------

  describe "platform chip overlay" do
    it "does NOT render the overlay when no chips apply" do
      allow_any_instance_of(described_class).to receive(:tile_chip_slugs).and_return([])
      render_inline(described_class.new(game: game))
      expect(page).to have_no_css(".tile-cover-chip-overlay")
    end

    it "renders the overlay container when at least one chip applies" do
      allow_any_instance_of(described_class).to receive(:tile_chip_slugs).and_return([ "steam" ])
      render_inline(described_class.new(game: game))
      expect(page).to have_css(".tile-cover-chip-overlay")
    end

    it "anchors the overlay flush bottom-right" do
      allow_any_instance_of(described_class).to receive(:tile_chip_slugs).and_return([ "steam" ])
      render_inline(described_class.new(game: game))
      overlay = page.find(".tile-cover-chip-overlay")
      expect(overlay["style"]).to include("position: absolute")
      expect(overlay["style"]).to include("right: 0")
      expect(overlay["style"]).to include("bottom: 0")
    end

    it "uses the cover-border CSS token as the strip background" do
      allow_any_instance_of(described_class).to receive(:tile_chip_slugs).and_return([ "steam" ])
      render_inline(described_class.new(game: game))
      overlay = page.find(".tile-cover-chip-overlay")
      expect(overlay["style"]).to include("background-color: var(--color-cover-border)")
    end

    it "renders one platform chip per slug" do
      allow_any_instance_of(described_class).to receive(:tile_chip_slugs).and_return(%w[ps steam])
      render_inline(described_class.new(game: game))
      expect(page).to have_css(".tile-cover-chip-overlay .platform-chip", count: 2)
    end

    it "uses 2px gap between chips" do
      allow_any_instance_of(described_class).to receive(:tile_chip_slugs).and_return(%w[ps steam])
      render_inline(described_class.new(game: game))
      overlay = page.find(".tile-cover-chip-overlay")
      expect(overlay["style"]).to include("gap: 2px")
    end
  end

  describe "tile_chip_slugs ordering (KNOWN_LOGOS walk)" do
    # The component must walk `PlatformLogosHelper::KNOWN_LOGOS` in
    # declaration order so render stays deterministic across calls.
    it "walks slugs in the canonical KNOWN_LOGOS order" do
      # Stub the two helpers `tile_chip_slugs` consumes so the test
      # focuses purely on the ordering invariant.
      allow_any_instance_of(described_class).to receive(:helpers).and_wrap_original do |_orig, *_args|
        double("helpers").tap do |h|
          allow(h).to receive(:game_detail_logo_slugs).with(game).and_return(%w[steam switch ps])
          allow(h).to receive(:game_index_tile_logo_slug).with(game).and_return("ps")
          allow(h).to receive(:game_path).with(game).and_return("/games/#{game.id}")
        end
      end
      render_inline(described_class.new(game: game))
      chips = page.all(".tile-cover-chip-overlay .platform-chip").map { |el| el[:class] }
      # KNOWN_LOGOS is %w[ps switch steam] — chips must render in that order.
      expect(chips.first).to include("platform-chip--ps")
      expect(chips.last).to include("platform-chip--steam")
    end
  end

  # ----------------------------------------------------------------
  # Editions — parent-pointer on editions, +N badge on primaries.
  # ----------------------------------------------------------------

  describe "edition parent-pointer" do
    let(:primary) { build_stubbed(:game, :synced, title: "Pragmata", cover_image_id: "p1") }
    let(:edition) do
      build_stubbed(:game, :synced,
                    title: "Pragmata Deluxe",
                    cover_image_id: "p2",
                    version_parent: primary,
                    version_parent_id: primary.id,
                    version_title: "Deluxe")
    end

    it "renders the parent-pointer row on an edition tile" do
      render_inline(described_class.new(game: edition))
      expect(page).to have_css(".tile-caption-parent-pointer")
    end

    it "shows the parent title in the parent-pointer row" do
      render_inline(described_class.new(game: edition))
      expect(page.find(".tile-caption-parent-pointer")).to have_text("Pragmata")
    end

    it "does NOT render the parent-pointer on a primary tile" do
      render_inline(described_class.new(game: primary))
      expect(page).to have_no_css(".tile-caption-parent-pointer")
    end
  end

  describe "editions badge" do
    let(:primary) { create(:game, title: "Pragmata") }

    it "renders the editions badge on a primary with editions" do
      create(:game, version_parent: primary)
      render_inline(described_class.new(game: primary.reload))
      expect(page).to have_css(".tile-caption-editions-badge")
    end

    it "does NOT render the editions badge on an edition tile" do
      edition = create(:game, version_parent: primary)
      render_inline(described_class.new(game: edition))
      expect(page).to have_no_css(".tile-caption-editions-badge")
    end
  end

  # ----------------------------------------------------------------
  # DOM id wrapper for Turbo Stream — the tile must be addressable.
  # The data-tile-game-id attribute provides the stable identifier
  # Turbo Stream / Stimulus controllers use to target it.
  # ----------------------------------------------------------------

  describe "tile addressability for Turbo / keyboard controllers" do
    it "exposes the game id via data-tile-game-id" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("a.tile[data-tile-game-id='#{game.id}']")
    end
  end

  # ----------------------------------------------------------------
  # Hard rules — no JS confirm anywhere.
  # ----------------------------------------------------------------

  describe "flaw: no JS confirm" do
    it "never emits data-turbo-confirm" do
      render_inline(described_class.new(game: game))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end

    it "never emits window.confirm or alert" do
      render_inline(described_class.new(game: game))
      html = page.native.to_html
      expect(html).not_to include("window.confirm")
      expect(html).not_to include("alert(")
    end
  end
end
