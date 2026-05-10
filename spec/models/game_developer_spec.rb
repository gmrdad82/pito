require "rails_helper"

RSpec.describe GameDeveloper, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:game) }
    it { is_expected.to belong_to(:company) }
  end

  describe "uniqueness" do
    it "is unique on (game_id, company_id)" do
      g = create(:game)
      c = create(:company)
      create(:game_developer, game: g, company: c)
      expect(build(:game_developer, game: g, company: c)).not_to be_valid
    end
  end

  describe "cascade" do
    it "is destroyed when its game is destroyed" do
      gd = create(:game_developer)
      expect { gd.game.destroy! }.to change { GameDeveloper.count }.by(-1)
    end

    it "is destroyed when its company is destroyed" do
      gd = create(:game_developer)
      expect { gd.company.destroy! }.to change { GameDeveloper.count }.by(-1)
    end
  end
end
