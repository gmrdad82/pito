require "rails_helper"

# Beta-3 Lane B (B4) — Games::BundlesSectionComponent.
#
# Pins down the bundles-section business rule in isolation from
# /games/:id (2026-05-18 DW slice + 2026-05-19 separator-tile slice):
#   - LEFT  = `game.bundles` ordered by `LOWER(name)`.
#   - RIGHT = `Bundles::SuggestedFor.call(game, limit: 3)` MINUS
#             any bundle the game is already a member of.
#   - Render branches:
#       * both empty   — `.shelf-empty-tile` "nothing yet" placeholder,
#                         no separator, no divider.
#       * LEFT only    — only default-mode tiles, no separator.
#       * RIGHT only   — separator tile FIRST, then suggest-mode tiles
#                         (CSS `:has(...:first-child)` zeros the row
#                         gap so the separator butts against the pane
#                         edge).
#       * BOTH         — LEFT tiles + separator tile + RIGHT tiles.
#                         The old `.bundles-section-divider` vertical
#                         hairline is gone (2026-05-19).
#   - LEFT tiles render `Games::BundleTileComponent` in default mode;
#     RIGHT tiles render the same component with
#     `mode: :suggest, target_game: game`.
#   - The "subtract member bundles from suggested" rule is the
#     silent-failure-prone invariant (a bundle the game already
#     belongs to must NOT leak into the suggested shelf).
RSpec.describe Games::BundlesSectionComponent, type: :component do
  let(:game) { build_stubbed(:game) }

  # The component calls `@game.bundles.order(Arel.sql(...)).to_a` and
  # `@game.bundle_ids` (via `Bundles::SuggestedFor`). We stub the chain
  # so no AR / pg lookups fire from the component spec.
  def stub_bundles_in(bundles)
    relation = double("bundles_relation")
    allow(game).to receive(:bundles).and_return(relation)
    allow(relation).to receive(:order).with(an_instance_of(Arel::Nodes::SqlLiteral)).and_return(relation)
    allow(relation).to receive(:to_a).and_return(bundles)
  end

  def stub_suggested(bundles, limit: 3)
    allow(Bundles::SuggestedFor).to receive(:call).with(game, limit: limit).and_return(bundles)
  end

  describe "both halves empty" do
    before do
      stub_bundles_in([])
      stub_suggested([])
    end

    it "renders the both-empty empty-tile branch (no bundle tiles, no separator, no divider)" do
      render_inline(described_class.new(game: game))

      expect(page).to have_css("section.game-bundles h2", text: "bundles")
      expect(page).to have_css(".shelf-empty-tile[aria-label='nothing yet']")
      expect(page).to have_css(".shelf-empty-tile span", text: "nothing")
      expect(page).to have_css(".shelf-empty-tile span", text: "yet")
      expect(page).not_to have_css(".bundles-suggested-separator")
      # 2026-05-19 — the old hairline divider must be gone everywhere.
      expect(page).not_to have_css(".bundles-section-divider")
    end
  end

  describe "LEFT only (2 in + 0 suggested)" do
    let(:in_bundles) { build_stubbed_list(:bundle, 2) }

    before do
      stub_bundles_in(in_bundles)
      stub_suggested([])
    end

    it "renders 2 default-mode tiles and no separator (no RIGHT half to introduce)" do
      render_inline(described_class.new(game: game))

      # Default-mode tile = `<a class="bundle-tile" title=bundle.name
      # data-bundle-id=id>`. `:suggest` mode = `<form>` carrying
      # `aria-label="add to <name>"`. Asserting on both ensures the
      # LEFT half rendered as default mode (not suggest).
      in_bundles.each do |bundle|
        expect(page).to have_css("a.bundle-tile[data-bundle-id='#{bundle.id}'][title='#{bundle.name}']")
        expect(page).not_to have_css("[aria-label='add to #{bundle.name}']")
      end
      expect(page).to have_css("a.bundle-tile", count: 2)
      expect(page).not_to have_css(".bundles-suggested-separator")
      expect(page).not_to have_css(".bundles-section-divider")
      expect(page).not_to have_css(".shelf-empty-tile")
    end
  end

  describe "RIGHT only (0 in + 3 suggested)" do
    let(:suggested_bundles) { build_stubbed_list(:bundle, 3) }

    before do
      stub_bundles_in([])
      stub_suggested(suggested_bundles)
    end

    it "renders separator FIRST, then 3 suggest-mode tiles (no in-bundles to render LEFT of it)" do
      render_inline(described_class.new(game: game))

      # `:suggest` mode renders a `button_to` with aria-label
      # "add to <bundle.name>".
      suggested_bundles.each do |bundle|
        expect(page).to have_css("[aria-label='add to #{bundle.name}']")
      end
      expect(page).to have_css(".bundles-suggested-separator", count: 1)
      expect(page).not_to have_css(".bundles-section-divider")
      expect(page).not_to have_css(".shelf-empty-tile")
    end

    it "places the separator as the FIRST child of the shelf row (CSS no-left-gap edge case)" do
      render_inline(described_class.new(game: game))

      # The CSS `.game-bundles .shelf-row:has(.bundles-suggested-separator:first-child)`
      # rule depends on the separator being the literal first child of
      # `.shelf-row`. Assert structural placement so a future template
      # tweak that moves the separator AFTER the suggested tiles (or
      # adds a stray wrapper) breaks the spec.
      first_child_selector = ".game-bundles .shelf-row > *:first-child"
      expect(page).to have_css("#{first_child_selector}.bundles-suggested-separator")
    end
  end

  describe "both halves present (2 in + 3 suggested, NO overlap)" do
    let(:in_bundles) { build_stubbed_list(:bundle, 2) }
    let(:suggested_bundles) { build_stubbed_list(:bundle, 3) }

    before do
      stub_bundles_in(in_bundles)
      stub_suggested(suggested_bundles)
    end

    it "renders 2 default tiles LEFT, separator tile, 3 suggest tiles RIGHT (hairline divider gone)" do
      render_inline(described_class.new(game: game))

      in_bundles.each do |bundle|
        expect(page).to have_css("a.bundle-tile[data-bundle-id='#{bundle.id}']")
      end
      suggested_bundles.each do |bundle|
        expect(page).to have_css("[aria-label='add to #{bundle.name}']")
      end
      expect(page).to have_css("a.bundle-tile", count: 2)
      expect(page).to have_css(".bundle-tile--suggest", count: 3)
      expect(page).to have_css(".bundles-suggested-separator", count: 1)
      # 2026-05-19 — the hairline divider is gone in every render
      # branch; the separator tile fills its role.
      expect(page).not_to have_css(".bundles-section-divider")
      expect(page).not_to have_css(".shelf-empty-tile")
    end

    it "places the separator BETWEEN the in-bundles tiles and the suggested tiles" do
      render_inline(described_class.new(game: game))

      # Pin the structural order: the separator must NOT be first
      # (in-bundles render before it) and it must appear in the DOM
      # AFTER every default-mode anchor and BEFORE every suggest-mode
      # form. Walking siblings directly is too fragile because each
      # bundle tile also emits a sibling `<turbo-cable-stream-source>`
      # for the bundle-cover live-refresh subscription, so use
      # document positions.
      first_child_selector = ".game-bundles .shelf-row > *:first-child"
      expect(page).not_to have_css("#{first_child_selector}.bundles-suggested-separator")

      shelf = page.find(".game-bundles .shelf-row")
      separator = shelf.find(".bundles-suggested-separator")
      default_anchor_positions = shelf.all("a.bundle-tile", minimum: 1).map(&:path)
      suggest_form_positions = shelf.all(".bundle-tile--suggest", minimum: 1).map(&:path)

      # XPath ordering check — the separator's path string sort key
      # carries DOM position, so we compare its first-child index.
      separator_index = shelf.all("*").map(&:path).index(separator.path)
      expect(separator_index).not_to be_nil
      default_anchor_positions.each do |path|
        expect(shelf.all("*").map(&:path).index(path)).to be < separator_index
      end
      suggest_form_positions.each do |path|
        expect(shelf.all("*").map(&:path).index(path)).to be > separator_index
      end
    end
  end

  # Silent-failure-prone invariant flagged by the catalog: a bundle
  # the game is already a member of must NEVER leak into the
  # suggested-bundles shelf.
  describe "subtraction rule (suggested - in)" do
    let(:in_bundles) { build_stubbed_list(:bundle, 2) }
    let(:overlap_bundle) { in_bundles.first }
    let(:other_suggested) { build_stubbed_list(:bundle, 2) }
    # SuggestedFor returns 3 bundles, ONE of which is already in the
    # member set. The component must drop it.
    let(:suggested_raw) { [ overlap_bundle ] + other_suggested }

    before do
      stub_bundles_in(in_bundles)
      stub_suggested(suggested_raw)
    end

    it "drops the overlapping bundle so RIGHT only renders the 2 non-member tiles" do
      render_inline(described_class.new(game: game))

      # The overlap bundle DOES appear on the LEFT (member of the game)
      # but must NOT appear on the RIGHT (no `:suggest` mode tile for it).
      expect(page).to have_css("a.bundle-tile[data-bundle-id='#{overlap_bundle.id}']")
      expect(page).not_to have_css("[aria-label='add to #{overlap_bundle.name}']")

      # The two non-overlapping suggested bundles do appear as suggest tiles.
      other_suggested.each do |bundle|
        expect(page).to have_css("[aria-label='add to #{bundle.name}']")
      end

      # Exactly two suggest tiles (the third suggestion was the
      # overlap bundle and got dropped). LEFT half remains intact at 2.
      expect(page).to have_css("a.bundle-tile", count: 2)
      expect(page).to have_css(".bundle-tile--suggest", count: 2)

      # Separator rendered because the RIGHT half is non-empty
      # post-subtraction; hairline divider gone.
      expect(page).to have_css(".bundles-suggested-separator", count: 1)
      expect(page).not_to have_css(".bundles-section-divider")
    end
  end

  describe "Bundles::SuggestedFor invocation" do
    before { stub_bundles_in([]) }

    it "invokes Bundles::SuggestedFor.call with limit: 3 (NOT 4 or any other value)" do
      expect(Bundles::SuggestedFor).to receive(:call).with(game, limit: 3).and_return([])
      render_inline(described_class.new(game: game))
    end
  end
end
