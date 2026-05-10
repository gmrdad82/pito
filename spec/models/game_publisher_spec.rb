require "rails_helper"

RSpec.describe GamePublisher, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:game) }
    it { is_expected.to belong_to(:company) }
  end

  describe "uniqueness" do
    it "is unique on (game_id, company_id)" do
      g = create(:game)
      c = create(:company)
      create(:game_publisher, game: g, company: c)
      expect(build(:game_publisher, game: g, company: c)).not_to be_valid
    end
  end

  describe "cascade" do
    it "is destroyed when its game is destroyed" do
      gp = create(:game_publisher)
      expect { gp.game.destroy! }.to change { GamePublisher.count }.by(-1)
    end

    it "is destroyed when its company is destroyed" do
      gp = create(:game_publisher)
      expect { gp.company.destroy! }.to change { GamePublisher.count }.by(-1)
    end
  end
end
