require "rails_helper"

# Beta-3 Lane B (B4) — Games::BundlesSectionComponent.
#
# Pins down the bundles-section business rule in isolation from
# /games/:id (2026-05-18 DW slice):
#   - LEFT  = `game.bundles` ordered by `LOWER(name)`.
#   - RIGHT = `Bundles::SuggestedFor.call(game, limit: 3)` MINUS
#             any bundle the game is already a member of.
#   - Three render branches: both-empty empty-tile / LEFT only /
#     RIGHT only / both with `.bundles-section-divider` between them.
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

    it "renders the both-empty empty-tile branch (no bundle tiles, no divider)" do
      render_inline(described_class.new(game: game))

      expect(page).to have_css("section.game-bundles h2", text: "bundles")
      expect(page).to have_css(".shelf-empty-tile[aria-label='nothing yet']")
      expect(page).to have_css(".shelf-empty-tile span", text: "nothing")
      expect(page).to have_css(".shelf-empty-tile span", text: "yet")
      expect(page).not_to have_css(".bundles-section-divider")
    end
  end

  describe "LEFT only (2 in + 0 suggested)" do
    let(:in_bundles) { build_stubbed_list(:bundle, 2) }

    before do
      stub_bundles_in(in_bundles)
      stub_suggested([])
    end

    it "renders 2 default-mode tiles and no divider" do
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

    it "renders 3 suggest-mode tiles and no divider" do
      render_inline(described_class.new(game: game))

      # `:suggest` mode renders a `button_to` with aria-label
      # "add to <bundle.name>".
      suggested_bundles.each do |bundle|
        expect(page).to have_css("[aria-label='add to #{bundle.name}']")
      end
      expect(page).not_to have_css(".bundles-section-divider")
      expect(page).not_to have_css(".shelf-empty-tile")
    end
  end

  describe "both halves present (2 in + 3 suggested, NO overlap)" do
    let(:in_bundles) { build_stubbed_list(:bundle, 2) }
    let(:suggested_bundles) { build_stubbed_list(:bundle, 3) }

    before do
      stub_bundles_in(in_bundles)
      stub_suggested(suggested_bundles)
    end

    it "renders 2 default tiles LEFT, divider, 3 suggest tiles RIGHT" do
      render_inline(described_class.new(game: game))

      in_bundles.each do |bundle|
        expect(page).to have_css("a.bundle-tile[data-bundle-id='#{bundle.id}']")
      end
      suggested_bundles.each do |bundle|
        expect(page).to have_css("[aria-label='add to #{bundle.name}']")
      end
      expect(page).to have_css("a.bundle-tile", count: 2)
      expect(page).to have_css(".bundle-tile--suggest", count: 3)
      expect(page).to have_css(".bundles-section-divider", count: 1)
      expect(page).not_to have_css(".shelf-empty-tile")
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

      # Divider rendered because both halves are non-empty post-subtraction.
      expect(page).to have_css(".bundles-section-divider", count: 1)
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
