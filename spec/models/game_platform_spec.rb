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

  # 2026-05-18 FN2 — `source` column. Default `"igdb"`, set to `"user"`
  # when the row is created by `Games::OwnershipTogglesController`
  # `ensure_user_added_platform_availability!`. The IGDB sync MUST NOT
  # downgrade a `"user"` row to `"igdb"` (preservation rule FN3).
  describe "source enum" do
    it "exposes the SOURCES whitelist" do
      expect(GamePlatform::SOURCES).to eq(%w[igdb user])
    end

    it "defaults to `igdb` when source is not set" do
      gp = create(:game_platform)
      expect(gp.source).to eq("igdb")
    end

    it "accepts `igdb` as a valid value" do
      gp = build(:game_platform, source: "igdb")
      expect(gp).to be_valid
    end

    it "accepts `user` as a valid value" do
      gp = build(:game_platform, source: "user")
      expect(gp).to be_valid
    end

    it "rejects any other source value" do
      gp = build(:game_platform, source: "scraper")
      expect(gp).not_to be_valid
      expect(gp.errors[:source]).to be_present
    end

    it "rejects nil source explicitly" do
      gp = build(:game_platform, source: nil)
      expect(gp).not_to be_valid
      expect(gp.errors[:source]).to be_present
    end
  end

  describe "scopes" do
    let!(:igdb_row) { create(:game_platform, source: "igdb") }
    let!(:user_row) { create(:game_platform, source: "user") }

    describe ".from_igdb" do
      it "returns only rows with source = `igdb`" do
        expect(GamePlatform.from_igdb).to contain_exactly(igdb_row)
      end
    end

    describe ".from_user" do
      it "returns only rows with source = `user`" do
        expect(GamePlatform.from_user).to contain_exactly(user_row)
      end
    end

    it "the two scopes partition the table cleanly (no overlap)" do
      expect(GamePlatform.from_igdb.pluck(:id) & GamePlatform.from_user.pluck(:id)).to eq([])
    end
  end
end
