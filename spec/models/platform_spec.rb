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

  describe ".canonical scope" do
    # FriendlyId regenerates `slug` from `name` during the save
    # callback, so the factory pattern is to `create` then
    # `update_column(:slug, "...")` to pin the canonical slug. The
    # `.canonical` scope reads `slug` exclusively.
    def force_slug(record, slug)
      record.update_column(:slug, slug)
      record
    end

    before do
      Platform.unscoped.delete_all
      force_slug(create(:platform, name: "PlayStation 5"),    "ps5")
      force_slug(create(:platform, name: "Nintendo Switch 2"), "switch2")
      force_slug(create(:platform, name: "Steam"),            "steam")
      force_slug(create(:platform, name: "GOG"),              "gog")
      force_slug(create(:platform, name: "Epic Games Store"), "epic")
      force_slug(create(:platform, name: "Xbox"),             "xbox")
      force_slug(create(:platform, name: "PlayStation 4"),    "ps4-non-canonical")
    end

    it "returns only the six canonical platforms" do
      slugs = Platform.canonical.pluck(:slug)
      expect(slugs).to contain_exactly("ps5", "switch2", "steam", "gog", "epic", "xbox")
    end

    it "excludes non-canonical platforms" do
      expect(Platform.canonical.pluck(:slug)).not_to include("ps4-non-canonical")
    end
  end

  describe "#canonical_short_name" do
    it "returns the locked short name for a canonical slug" do
      ps5 = build_stubbed(:platform, name: "PlayStation 5", slug: "ps5", igdb_id: nil)
      expect(ps5.canonical_short_name).to eq("PS5")
    end

    it "maps a Switch 2 seed slug to 'Switch2'" do
      sw2 = build_stubbed(:platform, name: "Nintendo Switch 2", slug: "switch2", igdb_id: nil)
      expect(sw2.canonical_short_name).to eq("Switch2")
    end

    it "maps the `gog` slug to 'GoG' (mixed case)" do
      gog = build_stubbed(:platform, name: "GOG", slug: "gog", igdb_id: nil)
      expect(gog.canonical_short_name).to eq("GoG")
    end

    it "maps IGDB-imported Xbox One (id=49) to 'Xbox'" do
      xbox_one = build_stubbed(:platform, name: "Xbox One", slug: "xbox-one", igdb_id: 49)
      expect(xbox_one.canonical_short_name).to eq("Xbox")
    end

    it "maps IGDB-imported Xbox Series X|S (id=169) to 'Xbox'" do
      xsxs = build_stubbed(:platform, name: "Xbox Series X|S", slug: "series-x-s", igdb_id: 169)
      expect(xsxs.canonical_short_name).to eq("Xbox")
    end

    it "maps IGDB PlayStation 5 (id=167) to 'PS5'" do
      ps5 = build_stubbed(:platform, name: "PlayStation 5", slug: "ps5-igdb", igdb_id: 167)
      expect(ps5.canonical_short_name).to eq("PS5")
    end

    it "returns nil for a non-canonical platform" do
      ps4 = build_stubbed(:platform, name: "PlayStation 4", slug: "ps4-x", igdb_id: 48)
      expect(ps4.canonical_short_name).to be_nil
    end

    it "returns nil for PC (Microsoft Windows) — no canonical alias" do
      pc = build_stubbed(:platform, name: "PC (Microsoft Windows)", slug: "pc-win", igdb_id: 6)
      expect(pc.canonical_short_name).to be_nil
    end

    it "#canonical? mirrors canonical_short_name presence" do
      ps5 = build_stubbed(:platform, slug: "ps5", igdb_id: nil)
      ps4 = build_stubbed(:platform, slug: "ps4-x", igdb_id: 48)
      expect(ps5.canonical?).to be(true)
      expect(ps4.canonical?).to be(false)
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
