require "rails_helper"

# Phase 20 — friendly URLs. Game uses `igdb_slug` (with `game-<id>`
# fallback when IGDB hasn't synced yet).
RSpec.describe Game, type: :model do
  describe "#to_param" do
    it "returns igdb_slug when present" do
      game = build_stubbed(:game, :synced)
      expect(game.to_param).to eq(game.igdb_slug)
    end

    it "falls back to id.to_s when igdb_slug is blank" do
      game = build_stubbed(:game)
      expect(game.igdb_slug).to be_blank
      expect(game.to_param).to eq(game.id.to_s)
    end
  end

  describe "friendly.find" do
    it "resolves by igdb_slug when set" do
      game = create(:game, :synced)
      expect(Game.friendly.find(game.igdb_slug)).to eq(game)
    end

    it "resolves by integer id" do
      game = create(:game, :synced)
      expect(Game.friendly.find(game.id)).to eq(game)
    end

    it "resolves by stringified integer id" do
      game = create(:game, :synced)
      expect(Game.friendly.find(game.id.to_s)).to eq(game)
    end

    it "resolves a game without igdb_slug by integer id" do
      game = create(:game)
      expect(Game.friendly.find(game.id)).to eq(game)
    end
  end

  describe "uniqueness on igdb_slug" do
    it "rejects two synced games with the same igdb_slug" do
      create(:game, :synced, igdb_slug: "celeste")
      duplicate = build(:game, :synced, igdb_slug: "celeste", igdb_id: 99_999_999)
      expect(duplicate).not_to be_valid
    end

    it "allows multiple games with nil igdb_slug" do
      a = create(:game)
      b = create(:game)
      expect(a.igdb_slug).to be_nil
      expect(b.igdb_slug).to be_nil
      expect(a).to be_valid
      expect(b).to be_valid
    end
  end
end
