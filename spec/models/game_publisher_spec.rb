# frozen_string_literal: true

require "rails_helper"

RSpec.describe GamePublisher, type: :model do
  subject(:game_publisher) { build(:game_publisher) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:game).required }
    it { is_expected.to belong_to(:company).required }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it "requires a game" do
      game_publisher.game = nil
      expect(game_publisher).not_to be_valid
    end

    it "requires a company" do
      game_publisher.company = nil
      expect(game_publisher).not_to be_valid
    end

    it "enforces uniqueness of game_id scoped to company_id" do
      gp = create(:game_publisher)
      dup = build(:game_publisher, game: gp.game, company: gp.company)
      expect(dup).not_to be_valid
      expect(dup.errors[:game_id]).to be_present
    end

    it "allows same game with a different company" do
      gp = create(:game_publisher)
      other = build(:game_publisher, game: gp.game, company: create(:company))
      expect(other).to be_valid
    end

    it "allows same company with a different game" do
      gp = create(:game_publisher)
      other = build(:game_publisher, game: create(:game), company: gp.company)
      expect(other).to be_valid
    end
  end

  # ── Cascade destroy ──────────────────────────────────────────────
  describe "cascade on parent destroy" do
    it "is destroyed when the game is destroyed" do
      gp = create(:game_publisher)
      expect { gp.game.destroy! }.to change(GamePublisher, :count).by(-1)
    end

    it "is destroyed when the company is destroyed" do
      gp = create(:game_publisher)
      expect { gp.company.destroy! }.to change(GamePublisher, :count).by(-1)
    end
  end
end
