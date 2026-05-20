require "rails_helper"

# Beta-3 Lane B (B1) — Games::DetailCoverComponent.
#
# Pins down the chip-overlay business rule (which platform chips light
# up on the /games/:id cover) and the stable DOM id contract
# (`game_detail_cover_<id>`) the planned ownership-toggle Turbo
# Stream broadcast will replace.
RSpec.describe Games::DetailCoverComponent, type: :component do
  let(:game) { build_stubbed(:game, :synced, id: 4242, title: "Test Game") }

  # The component reads slug truth from `PlatformChipsHelper` via
  # `helpers.game_detail_chip_slugs(@game)` /
  # `helpers.game_index_tile_chip_slug(@game)`. Stubbing those two
  # helpers on the ApplicationController's helper module (which the
  # ViewComponent test harness exposes through `helpers`) lets us
  # control which chip slugs apply without hitting the DB.
  before do
    allow_any_instance_of(PlatformChipsHelper).to receive(:game_detail_chip_slugs).and_return(detail_slugs)
    allow_any_instance_of(PlatformChipsHelper).to receive(:game_index_tile_chip_slug).and_return(tile_slug)
  end

  let(:detail_slugs) { [] }
  let(:tile_slug)    { nil }

  describe "wrapper DOM id" do
    it "carries id=game_detail_cover_<id> on the outer wrapper" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div#game_detail_cover_4242.game-cover-detail")
    end
  end

  describe "edge: no chip slugs match — overlay suppressed" do
    let(:detail_slugs) { [] }
    let(:tile_slug)    { nil }

    it "does NOT render the chip overlay div" do
      render_inline(described_class.new(game: game))
      expect(page).to have_no_css("div.tile-cover-chip-overlay")
    end
  end

  describe "happy: one chip slug matches" do
    let(:detail_slugs) { [ "ps" ] }
    let(:tile_slug)    { "ps" }

    it "renders exactly one Platforms::ChipComponent inside the overlay" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.tile-cover-chip-overlay .platform-chip", count: 1)
    end
  end

  describe "happy: all three chip slugs match — render in KNOWN_CHIPS order" do
    let(:detail_slugs) { [ "ps", "switch", "steam" ] }
    let(:tile_slug)    { "ps" }

    it "renders exactly three chips" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.tile-cover-chip-overlay .platform-chip", count: 3)
    end

    it "renders them in KNOWN_CHIPS declaration order (ps, switch, steam)" do
      render_inline(described_class.new(game: game))
      labels = page.all("div.tile-cover-chip-overlay .platform-chip").map { |chip| chip.text.strip }
      expect(labels).to eq([ "PS", "Switch", "Steam" ])
    end
  end
end
