require "rails_helper"

# Phase 27 §1a — Game ↔ Platform ownership join. Replaces the legacy
# single-valued `games.platform_owned_id` pointer.
RSpec.describe GamePlatformOwnership, type: :model do
  describe "factory" do
    it "is valid" do
      expect(build(:game_platform_ownership)).to be_valid
    end

    it "round-trips acquired_at / store / notes" do
      ts = Time.zone.local(2024, 3, 1, 12, 0, 0)
      ownership = create(:game_platform_ownership,
                         acquired_at: ts,
                         store: "Steam",
                         notes: "key from a humble bundle")
      ownership.reload
      expect(ownership.acquired_at).to be_within(1.second).of(ts)
      expect(ownership.store).to eq("Steam")
      expect(ownership.notes).to eq("key from a humble bundle")
    end

    it "allows acquired_at / store / notes to be nil" do
      ownership = create(:game_platform_ownership,
                         acquired_at: nil, store: nil, notes: nil)
      ownership.reload
      expect(ownership.acquired_at).to be_nil
      expect(ownership.store).to be_nil
      expect(ownership.notes).to be_nil
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:game) }
    it { is_expected.to belong_to(:platform) }
  end

  describe "validations" do
    # `belongs_to` is required by default — Rails 5+ adds an implicit
    # presence check that flags `game must exist` / `platform must
    # exist` on save.
    it "requires a game" do
      ownership = build(:game_platform_ownership, game: nil)
      expect(ownership).not_to be_valid
      expect(ownership.errors[:game]).to be_present
    end

    it "requires a platform" do
      ownership = build(:game_platform_ownership, platform: nil)
      expect(ownership).not_to be_valid
      expect(ownership.errors[:platform]).to be_present
    end

    it "rejects a duplicate (game_id, platform_id) pair" do
      game = create(:game)
      platform = create(:platform)
      create(:game_platform_ownership, game: game, platform: platform)
      dup = build(:game_platform_ownership, game: game, platform: platform)
      expect(dup).not_to be_valid
      expect(dup.errors[:platform_id]).to be_present
    end

    it "allows the same game on two different platforms" do
      game = create(:game)
      p1 = create(:platform, slug: "p1-distinct")
      p2 = create(:platform, slug: "p2-distinct")
      create(:game_platform_ownership, game: game, platform: p1)
      expect(build(:game_platform_ownership, game: game, platform: p2)).to be_valid
    end

    it "allows the same platform on two different games" do
      platform = create(:platform)
      g1 = create(:game)
      g2 = create(:game)
      create(:game_platform_ownership, game: g1, platform: platform)
      expect(build(:game_platform_ownership, game: g2, platform: platform)).to be_valid
    end
  end

  describe "edge — temporal flexibility" do
    it "accepts a future acquired_at without complaint" do
      ownership = build(:game_platform_ownership, acquired_at: 1.year.from_now)
      expect(ownership).to be_valid
    end
  end

  describe "cascade behavior" do
    it "is destroyed when its game is destroyed" do
      ownership = create(:game_platform_ownership)
      expect { ownership.game.destroy! }.to change(GamePlatformOwnership, :count).by(-1)
    end

    it "blocks platform destruction when the ownership exists" do
      ownership = create(:game_platform_ownership)
      expect { ownership.platform.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(GamePlatformOwnership.exists?(ownership.id)).to be(true)
    end
  end

  describe "flaw — long-string fields" do
    it "accepts a long store value without silent truncation" do
      long_store = "x" * 200
      ownership = create(:game_platform_ownership, store: long_store)
      expect(ownership.reload.store.length).to eq(200)
    end
  end
end
