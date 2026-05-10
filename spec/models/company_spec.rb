require "rails_helper"

RSpec.describe Company, type: :model do
  subject { build(:company) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:igdb_id) }
    it { is_expected.to validate_presence_of(:name) }

    it "rejects duplicate igdb_id" do
      create(:company, igdb_id: 70)
      expect(build(:company, igdb_id: 70)).not_to be_valid
    end

    it "rejects non-positive igdb_id" do
      expect(build(:company, igdb_id: 0)).not_to be_valid
      expect(build(:company, igdb_id: -1)).not_to be_valid
    end

    it "accepts a 255-character name" do
      expect(build(:company, name: "x" * 255)).to be_valid
    end

    it "rejects a 256-character name" do
      expect(build(:company, name: "x" * 256)).not_to be_valid
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:game_developers).dependent(:destroy) }
    it { is_expected.to have_many(:game_publishers).dependent(:destroy) }
  end
end
