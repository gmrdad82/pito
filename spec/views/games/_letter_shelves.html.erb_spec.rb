require "rails_helper"

# Phase 27 v2 spec 05 — `_letter_shelves` partial.
#
# Renders one `<section class="shelf shelf--letter">` per non-empty
# letter bucket. Each bucket carries an `<h3>` heading with the
# bucket key (A..Z uppercase, or `#` for digit / symbol titles) and a
# horizontal-scroll row of `Games::CoverComponent` tiles at the
# `:shelf` cover variant. Empty buckets do NOT render. The `#` bucket
# is positioned LAST in render order per the spec's pinned decision.
#
# The partial reads buckets as `[[letter, [game, ...]], ...]` tuples
# (the controller's `build_letter_buckets` shape).
RSpec.describe "games/_letter_shelves.html.erb", type: :view do
  def render_partial(buckets)
    render partial: "games/letter_shelves", locals: { buckets: buckets }
  end

  describe "happy: single non-empty bucket" do
    let!(:game) do
      create(:game, :synced, title: "Apex Legends",
             igdb_id: 4_300_001, igdb_slug: "apex-letter")
    end

    it "renders one `<section class=\"shelf shelf--letter\">` for the bucket" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).to include('class="shelf shelf--letter"')
      expect(rendered.scan('data-shelf="letter"').length).to eq(1)
    end

    it "renders the bucket letter as the `<h3>` heading" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).to match(%r{<h3[^>]*>\s*A\s*</h3>})
    end

    it "stamps `data-letter` on the section so spec callers can target it" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).to include('data-letter="A"')
    end

    it "stamps the steam-shelf Stimulus controller on each shelf" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).to include('data-controller="steam-shelf"')
    end

    it "renders one `:shelf` cover variant tile per game" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).to include('game-cover--shelf')
      expect(rendered).to include(%(data-tile-game-id="#{game.id}"))
    end

    it "wraps the iteration in `<section class=\"all-games-shelves-by-letter\">`" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).to include('class="all-games-shelves-by-letter')
    end
  end

  describe "happy: multiple non-empty buckets in render order" do
    let!(:alpha) { create(:game, :synced, title: "Alpha",  igdb_id: 4_310_001, igdb_slug: "alpha-letter") }
    let!(:mango) { create(:game, :synced, title: "Mango",  igdb_id: 4_310_002, igdb_slug: "mango-letter") }
    let!(:zinc)  { create(:game, :synced, title: "Zinc",   igdb_id: 4_310_003, igdb_slug: "zinc-letter") }

    it "renders one shelf per bucket in the order the caller supplies" do
      render_partial([ [ "A", [ alpha ] ], [ "M", [ mango ] ], [ "Z", [ zinc ] ] ])

      a_pos = rendered.index('data-letter="A"')
      m_pos = rendered.index('data-letter="M"')
      z_pos = rendered.index('data-letter="Z"')

      expect([ a_pos, m_pos, z_pos ].compact.length).to eq(3)
      expect(a_pos).to be < m_pos
      expect(m_pos).to be < z_pos
    end
  end

  describe "happy: digit-titled game lands in `#` bucket at the end" do
    let!(:seven_days) { create(:game, :synced, title: "7 Days to Die",
                               igdb_id: 4_320_001, igdb_slug: "seven-days-letter") }
    let!(:alpha) { create(:game, :synced, title: "Alpha", igdb_id: 4_320_002, igdb_slug: "alpha-bucket") }

    it "renders the `#` heading when the bucket is non-empty" do
      render_partial([ [ "A", [ alpha ] ], [ "#", [ seven_days ] ] ])
      expect(rendered).to match(%r{<h3[^>]*>\s*\#\s*</h3>})
    end

    it "places the `#` bucket AFTER all letter buckets in render order" do
      render_partial([ [ "A", [ alpha ] ], [ "#", [ seven_days ] ] ])
      a_pos = rendered.index('data-letter="A"')
      hash_pos = rendered.index('data-letter="#"')
      expect(a_pos).not_to be_nil
      expect(hash_pos).not_to be_nil
      expect(a_pos).to be < hash_pos
    end
  end

  describe "happy: tile ordering follows caller-supplied order" do
    let!(:abzu)  { create(:game, :synced, title: "ABZU",  igdb_id: 4_330_001, igdb_slug: "abzu-letter") }
    let!(:apex)  { create(:game, :synced, title: "Apex",  igdb_id: 4_330_002, igdb_slug: "apex-second-letter") }
    let!(:atom)  { create(:game, :synced, title: "Atomic", igdb_id: 4_330_003, igdb_slug: "atom-letter") }

    it "renders tiles in the order the caller supplies (alphabetical)" do
      render_partial([ [ "A", [ abzu, apex, atom ] ] ])
      indexes = [ abzu, apex, atom ].map { |g| rendered.index("data-tile-game-id=\"#{g.id}\"") }
      expect(indexes.compact.length).to eq(3)
      expect(indexes).to eq(indexes.sort)
    end
  end

  describe "edge: empty buckets array" do
    it "renders nothing (no wrapper, no shelf)" do
      render_partial([])
      expect(rendered.strip).to be_empty
    end
  end

  describe "edge: bucket with zero games" do
    # Defensive — the controller filters empty buckets, but the
    # partial should still degrade gracefully if a caller hands it
    # an empty list.
    it "still renders the section + heading but no tiles" do
      render_partial([ [ "A", [] ] ])
      expect(rendered).to match(%r{<h3[^>]*>\s*A\s*</h3>})
      expect(rendered).not_to include('game-cover--shelf')
    end
  end

  describe "flaw: no JS confirm / alert affordances" do
    let!(:game) do
      create(:game, :synced, title: "Apex Legends",
             igdb_id: 4_340_001, igdb_slug: "apex-flaw-letter")
    end

    it "does NOT include data-turbo-confirm anywhere in the partial" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).not_to include("data-turbo-confirm")
    end

    it "does NOT include a <script> tag" do
      render_partial([ [ "A", [ game ] ] ])
      expect(rendered).not_to include("<script")
    end
  end
end
