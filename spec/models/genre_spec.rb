require "rails_helper"

RSpec.describe Genre, type: :model do
  subject { build(:genre) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:igdb_id) }
    it { is_expected.to validate_presence_of(:name) }

    it "rejects duplicate igdb_id" do
      create(:genre, igdb_id: 31)
      dup = build(:genre, igdb_id: 31)
      expect(dup).not_to be_valid
    end

    it "rejects non-positive igdb_id" do
      expect(build(:genre, igdb_id: 0)).not_to be_valid
      expect(build(:genre, igdb_id: -1)).not_to be_valid
    end

    it "accepts unicode in name" do
      expect(build(:genre, name: "アドベンチャー")).to be_valid
    end

    it "accepts a 255-character name" do
      expect(build(:genre, name: "x" * 255)).to be_valid
    end

    it "rejects a 256-character name" do
      expect(build(:genre, name: "x" * 256)).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:game_genres).dependent(:destroy) }
    it { is_expected.to have_many(:games).through(:game_genres) }
  end
end
