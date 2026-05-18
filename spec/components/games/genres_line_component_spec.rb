require "rails_helper"

# Beta-3 Lane B (B2) — Games::GenresLineComponent.
#
# Pins down the "primary in <strong> + up-to-2 alphabetical secondaries
# + ` · ` separator + <em>—</em> empty fallback" business rule (Wave C2
# spec 08 §"Genres") in isolation from /games/:id.
RSpec.describe Games::GenresLineComponent, type: :component do
  let(:game) { build_stubbed(:game, id: 9_001, title: "Test Game") }

  # Stubs the chained `game.genres.where.not(...).order(...).limit(...)`
  # query the component runs for `secondaries`. Returns the supplied
  # array as the final relation result. `where_not_id` is what the
  # production code passes (the primary's id or nil), captured here so
  # tests can assert it when useful.
  def stub_genres_query(returned)
    relation = double("Genre::ActiveRecord_Relation")
    allow(relation).to receive(:order).with(:name).and_return(relation)
    allow(relation).to receive(:limit).with(2).and_return(returned)
    genres_assoc = double("Genre::Association")
    allow(genres_assoc).to receive(:where).with(any_args).and_return(double("not-scope", not: relation))
    # The component calls `@game.genres.where.not(id: primary&.id)` —
    # `where.not(...)` resolves through WhereChain. Easiest path: stub
    # `where.not(...)` directly via a passthrough.
    allow(genres_assoc).to receive_message_chain(:where, :not).and_return(relation)
    allow(game).to receive(:genres).and_return(genres_assoc)
  end

  describe "happy: 1 primary, no secondaries" do
    let(:primary) { build_stubbed(:genre, name: "Adventure") }

    before do
      allow(game).to receive(:primary_genre).and_return(primary)
      stub_genres_query([])
    end

    it "renders the primary in <strong> with no separator" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.game-genres strong", text: "Adventure")
      expect(page).to have_no_css("div.game-genres span")
      expect(page.text).not_to include("·")
    end
  end

  describe "happy: 1 primary + 1 secondary" do
    let(:primary)   { build_stubbed(:genre, name: "RPG") }
    let(:secondary) { build_stubbed(:genre, name: "Adventure") }

    before do
      allow(game).to receive(:primary_genre).and_return(primary)
      stub_genres_query([ secondary ])
    end

    it "renders primary in <strong>, secondary plain, separated by ` · `" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.game-genres strong", text: "RPG")
      expect(page).to have_css("div.game-genres span", text: "Adventure")
      expect(page.native.to_s).to include(" · ")
    end
  end

  describe "happy: 1 primary + 2 secondaries (alphabetical)" do
    let(:primary) { build_stubbed(:genre, name: "RPG") }
    # Factory hands back already-ordered objects since the component
    # delegates ordering to the stubbed query — we hand them back
    # alphabetical to mirror what `.order(:name)` would produce.
    let(:sec_a)   { build_stubbed(:genre, name: "Action") }
    let(:sec_b)   { build_stubbed(:genre, name: "Strategy") }

    before do
      allow(game).to receive(:primary_genre).and_return(primary)
      stub_genres_query([ sec_a, sec_b ])
    end

    it "renders 3 tokens — primary first in <strong>, then secondaries in given order" do
      render_inline(described_class.new(game: game))
      strongs = page.all("div.game-genres strong").map { |n| n.text.strip }
      spans   = page.all("div.game-genres span").map { |n| n.text.strip }
      expect(strongs).to eq([ "RPG" ])
      expect(spans).to eq([ "Action", "Strategy" ])
    end
  end

  describe "edge: cap-3 rule — limit(2) caps secondaries even when DB has more" do
    let(:primary) { build_stubbed(:genre, name: "RPG") }
    let(:sec_a)   { build_stubbed(:genre, name: "Action") }
    let(:sec_b)   { build_stubbed(:genre, name: "Strategy") }

    before do
      allow(game).to receive(:primary_genre).and_return(primary)
      # The stub's `.limit(2).and_return([sec_a, sec_b])` enforces the
      # cap — the component itself is what calls `.limit(2)`, so the
      # contract being pinned here is "secondaries calls .limit(2)".
      stub_genres_query([ sec_a, sec_b ])
    end

    it "renders exactly 1 strong + 2 spans (cap-3 total)" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.game-genres strong", count: 1)
      expect(page).to have_css("div.game-genres span", count: 2)
    end

    it "calls .limit(2) on the secondaries relation" do
      # Re-stub so we can spy on .limit explicitly.
      relation = double("rel")
      allow(relation).to receive(:order).with(:name).and_return(relation)
      allow(relation).to receive(:limit).with(2).and_return([ sec_a, sec_b ]).at_least(:once)
      genres_assoc = double("assoc")
      allow(genres_assoc).to receive_message_chain(:where, :not).and_return(relation)
      allow(game).to receive(:genres).and_return(genres_assoc)
      render_inline(described_class.new(game: game))
      expect(relation).to have_received(:limit).with(2)
    end
  end

  describe "edge: 0 genres — em-dash fallback" do
    before do
      allow(game).to receive(:primary_genre).and_return(nil)
      stub_genres_query([])
    end

    it "renders <em>—</em> and no genre tokens" do
      render_inline(described_class.new(game: game))
      expect(page).to have_css("div.game-genres em.text-muted", text: "—")
      expect(page).to have_no_css("div.game-genres strong")
      expect(page).to have_no_css("div.game-genres span")
    end
  end
end
