# frozen_string_literal: true

require "rails_helper"

RSpec.describe GamePlatformOwnership, type: :model do
  subject(:ownership) { build(:game_platform_ownership, platform_token: "ps") }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:game).required }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it "requires a game" do
      ownership.game = nil
      expect(ownership).not_to be_valid
    end

    it "requires platform_token to be present" do
      ownership.platform_token = nil
      expect(ownership).not_to be_valid
      expect(ownership.errors[:platform_token]).to be_present
    end

    it "accepts all valid platform tokens" do
      GamePlatformOwnership::PLATFORM_TOKENS.each do |token|
        o = build(:game_platform_ownership, platform_token: token)
        expect(o).to be_valid, "expected #{token} to be valid"
      end
    end

    it "rejects an unknown platform token" do
      ownership.platform_token = "xbox"
      expect(ownership).not_to be_valid
      expect(ownership.errors[:platform_token]).to be_present
    end

    it "enforces uniqueness of game_id scoped to platform_token" do
      game = create(:game)
      create(:game_platform_ownership, game: game, platform_token: "ps")
      dup = build(:game_platform_ownership, game: game, platform_token: "ps")
      expect(dup).not_to be_valid
      expect(dup.errors[:game_id]).to be_present
    end

    it "allows the same game to own multiple different platforms" do
      game = create(:game)
      create(:game_platform_ownership, game: game, platform_token: "ps")
      other = build(:game_platform_ownership, game: game, platform_token: "switch")
      expect(other).to be_valid
    end
  end

  # ── Cascade destroy ──────────────────────────────────────────────
  describe "cascade on game destroy" do
    it "is destroyed when the game is destroyed" do
      ownership = create(:game_platform_ownership)
      expect { ownership.game.destroy! }.to change(GamePlatformOwnership, :count).by(-1)
    end
  end

  # ── Platform token constant ───────────────────────────────────────
  describe "PLATFORM_TOKENS" do
    it "includes ps, switch, and steam" do
      expect(GamePlatformOwnership::PLATFORM_TOKENS).to contain_exactly("ps", "switch", "steam")
    end
  end
end
