require "rails_helper"

RSpec.describe Platform, type: :model do
  subject { build(:platform) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:igdb_id) }
    it { is_expected.to validate_presence_of(:name) }

    it "rejects duplicate igdb_id" do
      create(:platform, igdb_id: 130)
      expect(build(:platform, igdb_id: 130)).not_to be_valid
    end

    it "rejects non-positive igdb_id" do
      expect(build(:platform, igdb_id: 0)).not_to be_valid
      expect(build(:platform, igdb_id: -5)).not_to be_valid
    end

    it "accepts unicode in name" do
      expect(build(:platform, name: "プレイステーション 5")).to be_valid
    end

    it "accepts a 255-character name" do
      expect(build(:platform, name: "x" * 255)).to be_valid
    end

    it "rejects a 256-character name" do
      expect(build(:platform, name: "x" * 256)).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:game_platforms).dependent(:destroy) }
    it { is_expected.to have_many(:games).through(:game_platforms) }
    it "nullifies platform_owned_id on dependent games when destroyed" do
      platform = create(:platform)
      game = create(:game, platform_owned: platform)
      platform.destroy!
      expect(game.reload.platform_owned_id).to be_nil
    end
  end
end
