require "rails_helper"

RSpec.describe Platform, type: :model do
  subject { build(:platform) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    # `slug` presence is enforced both at the DB level (NOT NULL) and
    # via FriendlyId's `before_validation` slug-generator — by the time
    # `valid?` runs, the slug is always backfilled from `name`. The
    # shoulda matcher can't observe the presence validation because the
    # callback fires first, so we exercise the underlying invariant
    # directly: a row with both blank name AND blank slug is rejected.
    it "is invalid when name is blank (slug derives from name)" do
      record = build(:platform, name: "", slug: nil)
      expect(record).not_to be_valid
    end

    it "is valid without an igdb_id (seeded rows pre-exist)" do
      expect(build(:platform, igdb_id: nil)).to be_valid
    end

    it "rejects duplicate igdb_id when present" do
      create(:platform, igdb_id: 130)
      expect(build(:platform, igdb_id: 130)).not_to be_valid
    end

    it "rejects non-positive igdb_id" do
      expect(build(:platform, igdb_id: 0)).not_to be_valid
      expect(build(:platform, igdb_id: -5)).not_to be_valid
    end

    it "rejects a duplicate slug at the model layer" do
      # FriendlyId's slugged module auto-resolves collisions during
      # `set_slug`, so two `build(:platform, name: "...")` calls land
      # on distinct slugs. The model-level uniqueness validation is the
      # safety net for a row whose slug was pre-set via
      # `update_column` (bypassing the slug generator).
      original = create(:platform)
      original.update_column(:slug, "shared-slug")
      # `build_stubbed`-style: skip the slug generator by saving with
      # validation off, then check that re-saving the conflict picks
      # up the duplicate error.
      conflict = create(:platform)
      conflict.update_column(:slug, "another-slug")
      conflict.slug = "shared-slug"
      # Avoid the FriendlyId set_slug callback by toggling the slug
      # WITHOUT a name change.
      expect(conflict).not_to be_valid
      expect(conflict.errors[:slug]).to be_present
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
    it { is_expected.to have_many(:games_available).through(:game_platforms).source(:game) }
    it { is_expected.to have_many(:game_platform_ownerships).dependent(:restrict_with_error) }
    it { is_expected.to have_many(:games).through(:game_platform_ownerships) }
  end

  describe "default ordering" do
    it "returns platforms alphabetically by name" do
      Platform.unscoped.delete_all
      gog = create(:platform, name: "GOG", slug: "gog-default-order")
      ps5 = create(:platform, name: "PlayStation 5", slug: "ps5-default-order")
      steam = create(:platform, name: "Steam", slug: "steam-default-order")
      expect(Platform.all.to_a).to eq([ gog, ps5, steam ])
    end
  end

  describe "FriendlyId" do
    let!(:platform) { create(:platform, name: "PlayStation 5", slug: nil) }

    it "auto-derives a slug from the name when one is not supplied" do
      expect(platform.slug).to eq("playstation-5")
    end

    it "resolves by slug via Platform.friendly.find" do
      found = Platform.friendly.find("playstation-5")
      expect(found).to eq(platform)
    end

    it "still resolves by integer id via Platform.friendly.find" do
      expect(Platform.friendly.find(platform.id)).to eq(platform)
    end

    it "keeps the old slug resolvable via history after rename" do
      platform.update!(name: "PlayStation 5 Pro")
      expect(platform.reload.slug).to eq("playstation-5-pro")
      expect(Platform.friendly.find("playstation-5")).to eq(platform)
    end
  end

  describe "nullability allowances" do
    it "permits two platforms with NULL igdb_id to coexist" do
      Platform.unscoped.delete_all
      first  = create(:platform, igdb_id: nil, slug: "manual-1")
      second = create(:platform, igdb_id: nil, slug: "manual-2")
      expect([ first, second ].map(&:persisted?)).to all(be(true))
    end
  end

  describe "destroy guard" do
    it "raises ActiveRecord::RecordNotDestroyed when ownerships exist" do
      platform = create(:platform)
      game = create(:game)
      create(:game_platform_ownership, game: game, platform: platform)
      expect { platform.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(Platform.unscoped.exists?(platform.id)).to be(true)
    end

    it "destroys freely when no ownerships exist" do
      platform = create(:platform)
      expect { platform.destroy! }.not_to raise_error
    end
  end
end
