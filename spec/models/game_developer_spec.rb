# frozen_string_literal: true

require "rails_helper"

RSpec.describe GameDeveloper, type: :model do
  subject(:game_developer) { build(:game_developer) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:game).required }
    it { is_expected.to belong_to(:company).required }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it "requires a game" do
      game_developer.game = nil
      expect(game_developer).not_to be_valid
    end

    it "requires a company" do
      game_developer.company = nil
      expect(game_developer).not_to be_valid
    end

    it "enforces uniqueness of game_id scoped to company_id" do
      gd = create(:game_developer)
      dup = build(:game_developer, game: gd.game, company: gd.company)
      expect(dup).not_to be_valid
      expect(dup.errors[:game_id]).to be_present
    end

    it "allows same game with a different company" do
      gd = create(:game_developer)
      other = build(:game_developer, game: gd.game, company: create(:company))
      expect(other).to be_valid
    end

    it "allows same company with a different game" do
      gd = create(:game_developer)
      other = build(:game_developer, game: create(:game), company: gd.company)
      expect(other).to be_valid
    end
  end

  # ── Cascade destroy ──────────────────────────────────────────────
  describe "cascade on parent destroy" do
    it "is destroyed when the game is destroyed" do
      gd = create(:game_developer)
      expect { gd.game.destroy! }.to change(GameDeveloper, :count).by(-1)
    end

    it "is destroyed when the company is destroyed" do
      gd = create(:game_developer)
      expect { gd.company.destroy! }.to change(GameDeveloper, :count).by(-1)
    end
  end
end
