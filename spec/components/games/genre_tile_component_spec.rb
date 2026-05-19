require "rails_helper"

# Phase 27 sub-spec 01c — Games::GenreTileComponent.
#
# Thin wrapper around `Games::CoverComponent` at the `:shelf` variant
# used inside `_genre_sub_shelf.html.erb` (genre sub-shelves on the
# `/games` index, the "more like this" shelf on `/games/:id`, and the
# omnisearch-modal "similar to this bundle" row).
#
# The component takes a `game:` (NOT a Genre — it renders one game tile
# inside a genre-keyed shelf). Two render shapes:
#
#   * Default — bare CoverComponent with its own internal `<a>` link to
#     `/games/:slug`. No outer wrapper.
#   * `link_to: nil` + `data: { … }` — the inner cover loses its anchor
#     (`link_to_show: false`) and gets wrapped in a `<div>` with the
#     supplied data-* attributes so the caller can attach Stimulus
#     controllers / actions (e.g. the omnisearch bundle-add-trigger).
RSpec.describe Games::GenreTileComponent, type: :component do
  let(:game) do
    build_stubbed(:game, :synced,
                  id: 4242,
                  title: "Hades II",
                  igdb_slug: "hades-ii",
                  cover_image_id: "abcd1234")
  end

  # ----------------------------------------------------------------
  # Default render — bare CoverComponent at :shelf.
  # ----------------------------------------------------------------

  describe "happy: default render" do
    before { render_inline(described_class.new(game: game)) }

    it "delegates to Games::CoverComponent at the :shelf variant" do
      expect(page).to have_css("a.game-cover.game-cover--shelf")
    end

    it "uses the shelf 98x130 dimensions on the cover" do
      expect(page).to have_css('img[width="98"][height="130"]')
    end

    it "uses the IGDB t_cover_small_2x url for the shelf variant" do
      img = page.find("img")
      expect(img["src"]).to eq("https://images.igdb.com/igdb/image/upload/t_cover_small_2x/abcd1234.jpg")
    end

    it "links to /games/:slug via the CoverComponent's internal anchor" do
      anchor = page.find("a.game-cover")
      expect(anchor["href"]).to eq("/games/hades-ii")
    end

    it "does NOT add an extra outer wrapper around the CoverComponent" do
      # The component must not introduce its own <div> wrapper in
      # default mode — the partial's flex row layout depends on each
      # tile being a single bare <a>.
      expect(page).to have_no_css("div > a.game-cover")
    end
  end

  # ----------------------------------------------------------------
  # Fallback render — no cover_image_id falls through to the
  # single-dark SVG the CoverComponent emits (theme system removed
  # 2026-05-19; only the dark fallback asset is referenced).
  # ----------------------------------------------------------------

  describe "edge: game with no cover" do
    let(:naked_game) do
      build_stubbed(:game, :synced,
                    id: 5151,
                    title: "Missing Cover",
                    igdb_slug: "missing-cover",
                    cover_image_id: nil)
    end

    before { render_inline(described_class.new(game: naked_game)) }

    it "emits exactly one single-dark fallback SVG" do
      expect(page).to have_css("img.game-cover-fallback", count: 1)
    end

    it "does NOT emit the dropped theme-variant fallback classes" do
      expect(page).to have_no_css("img.game-cover-fallback--light")
      expect(page).to have_no_css("img.game-cover-fallback--dark")
    end

    it "sizes the fallback at shelf 98x130" do
      page.all("img.game-cover-fallback").each do |img|
        expect(img["width"]).to eq("98")
        expect(img["height"]).to eq("130")
      end
    end

    it "still wraps in the shelf-variant anchor so the slot is sized" do
      expect(page).to have_css("a.game-cover.game-cover--shelf")
    end
  end

  # ----------------------------------------------------------------
  # link_to: nil + data: { … } — the bundle-add / omnisearch path.
  # ----------------------------------------------------------------

  describe "happy: link_to: nil with data attrs (omnisearch bundle-add path)" do
    let(:data) do
      {
        controller: "bundle-add-trigger",
        "bundle-add-trigger-bundle-id-value": 99,
        "bundle-add-trigger-game-id-value": game.id,
        action: "click->bundle-add-trigger#add"
      }
    end

    before { render_inline(described_class.new(game: game, link_to: nil, data: data)) }

    it "wraps the cover in a non-anchor <div> click target" do
      expect(page).to have_css("div[style*='cursor: pointer']")
      expect(page).to have_no_css("a.game-cover")
    end

    it "renders the inner cover with link_to_show: false (bare <div> cover)" do
      expect(page).to have_css("div.game-cover.game-cover--shelf")
    end

    it "splats each data hash key onto the outer wrapper as data-*" do
      wrapper = page.find("div[data-controller]")
      expect(wrapper["data-controller"]).to eq("bundle-add-trigger")
      expect(wrapper["data-bundle-add-trigger-bundle-id-value"]).to eq("99")
      expect(wrapper["data-bundle-add-trigger-game-id-value"]).to eq(game.id.to_s)
      expect(wrapper["data-action"]).to eq("click->bundle-add-trigger#add")
    end

    it "dasherizes underscore keys (data: { foo_bar: 1 } → data-foo-bar)" do
      render_inline(described_class.new(
        game: game,
        link_to: nil,
        data: { foo_bar: "yes" }
      ))
      expect(page).to have_css("div[data-foo-bar='yes']")
    end

    it "still renders the IGDB shelf URL inside the data-attr wrapper" do
      img = page.find("img")
      expect(img["src"]).to include("t_cover_small_2x/abcd1234")
    end
  end

  # ----------------------------------------------------------------
  # link_to override semantics — `link_to: :default` (the default)
  # behaves identically to omitting the kwarg.
  # ----------------------------------------------------------------

  describe "link_to override semantics" do
    it ":default keeps the CoverComponent's internal anchor (link_to_show: true)" do
      render_inline(described_class.new(game: game, link_to: :default))
      expect(page).to have_css("a.game-cover")
    end

    it "nil strips the internal anchor (link_to_show: false)" do
      render_inline(described_class.new(game: game, link_to: nil))
      expect(page).to have_no_css("a.game-cover")
    end

    it "default + empty data hash still renders the bare <a> (no wrapper)" do
      render_inline(described_class.new(game: game, data: {}))
      expect(page).to have_css("a.game-cover")
      expect(page).to have_no_css("div[style*='cursor: pointer']")
    end
  end

  # ----------------------------------------------------------------
  # Flaw — no JS confirm anywhere in the tile.
  # ----------------------------------------------------------------

  describe "flaw: no JS confirm" do
    it "never emits data-turbo-confirm" do
      render_inline(described_class.new(game: game))
      expect(page.native.to_html).not_to include("data-turbo-confirm")
    end
  end
end
