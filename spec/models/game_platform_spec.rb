require "rails_helper"

RSpec.describe GamePlatform, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:game) }
    it { is_expected.to belong_to(:platform) }
  end

  describe "uniqueness" do
    it "is unique on (game_id, platform_id)" do
      g = create(:game)
      p = create(:platform)
      create(:game_platform, game: g, platform: p)
      expect(build(:game_platform, game: g, platform: p)).not_to be_valid
    end
  end

  describe "cascade" do
    it "is destroyed when its game is destroyed" do
      gp = create(:game_platform)
      expect { gp.game.destroy! }.to change { GamePlatform.count }.by(-1)
    end

    it "is destroyed when its platform is destroyed" do
      gp = create(:game_platform)
      expect { gp.platform.destroy! }.to change { GamePlatform.count }.by(-1)
    end
  end
end
