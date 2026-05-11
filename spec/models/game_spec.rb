require "rails_helper"

# Phase 14 §1 — Game model is now IGDB-backed.
RSpec.describe Game, type: :model do
  subject { build(:game) }

  describe "associations" do
    it { is_expected.to belong_to(:collection).optional }
    it { is_expected.to have_many(:footages).dependent(:nullify) }
    it { is_expected.to have_many(:game_genres).dependent(:destroy) }
    it { is_expected.to have_many(:genres).through(:game_genres) }
    it { is_expected.to have_many(:game_platforms).dependent(:destroy) }
    it { is_expected.to have_many(:platforms_available).through(:game_platforms).source(:platform) }
    it { is_expected.to have_many(:game_developers).dependent(:destroy) }
    it { is_expected.to have_many(:developers).through(:game_developers).source(:company) }
    it { is_expected.to have_many(:game_publishers).dependent(:destroy) }
    it { is_expected.to have_many(:publishers).through(:game_publishers).source(:company) }

    # Phase 27 §1a — per-platform ownership join.
    it { is_expected.to have_many(:game_platform_ownerships).dependent(:destroy) }
    it { is_expected.to have_many(:owned_platforms).through(:game_platform_ownerships).source(:platform) }

    # Phase 14 §3 — video attribution links.
    it { is_expected.to have_many(:video_game_links).dependent(:destroy) }
    it { is_expected.to have_many(:videos).through(:video_game_links) }

    it "has_one_attached :cover_art (legacy)" do
      expect(Game.new).to respond_to(:cover_art)
    end
  end

  describe "Phase 27 §1a — ownership shape" do
    it "does not respond to the legacy platform_owned_id column" do
      expect(Game.column_names).not_to include("platform_owned_id")
    end

    it "exposes owned_platforms via the join" do
      game = create(:game)
      p1 = create(:platform, name: "PS5",   slug: "ps5-game-spec")
      p2 = create(:platform, name: "Steam", slug: "steam-game-spec")
      game.game_platform_ownerships.create!(platform: p1)
      game.game_platform_ownerships.create!(platform: p2)
      # default_scope on Platform orders by name, so PS5 comes before
      # Steam alphabetically (P < S).
      expect(game.reload.owned_platforms.map(&:name)).to eq([ "PS5", "Steam" ])
    end

    describe ".owned" do
      it "includes only games with at least one ownership row" do
        owned = create(:game)
        platform = create(:platform, slug: "owned-scope-platform")
        owned.game_platform_ownerships.create!(platform: platform)
        unowned = create(:game)
        expect(Game.owned).to include(owned)
        expect(Game.owned).not_to include(unowned)
      end

      it "returns DISTINCT games when a game owns on multiple platforms" do
        game = create(:game)
        p1 = create(:platform, slug: "distinct-1")
        p2 = create(:platform, slug: "distinct-2")
        game.game_platform_ownerships.create!(platform: p1)
        game.game_platform_ownerships.create!(platform: p2)
        expect(Game.owned.where(id: game.id).count).to eq(1)
      end
    end

    describe ".not_owned" do
      it "includes only games with zero ownership rows" do
        owned = create(:game)
        platform = create(:platform, slug: "not-owned-platform")
        owned.game_platform_ownerships.create!(platform: platform)
        unowned = create(:game)
        expect(Game.not_owned).to include(unowned)
        expect(Game.not_owned).not_to include(owned)
      end
    end

    describe ".owned_on(slug)" do
      let!(:game) { create(:game) }
      # Two platforms with stable, known names. FriendlyId derives the
      # slug from `name`; the tests match by `platform.slug` to avoid
      # hardcoding the FriendlyId output.
      let!(:ps5)   { create(:platform, name: "OwnedOnPS5") }
      let!(:steam) { create(:platform, name: "OwnedOnSteam") }

      before do
        game.game_platform_ownerships.create!(platform: ps5)
      end

      it "matches games owned on the named platform" do
        expect(Game.owned_on(ps5.slug)).to include(game)
      end

      it "excludes games owned on a different platform" do
        other = create(:game)
        other.game_platform_ownerships.create!(platform: steam)
        expect(Game.owned_on(ps5.slug)).not_to include(other)
      end

      it "returns an empty relation for an unknown slug (no error)" do
        expect(Game.owned_on("not-a-real-slug")).to be_empty
      end
    end
  end

  describe "hours_of_footage manual override precedence" do
    it "returns hours_of_footage_manual when set" do
      g = create(:game, hours_of_footage_manual: 42)
      g.update_column(:hours_of_footage_cached, 9)
      expect(g.hours_of_footage).to eq(42)
    end

    it "falls back to hours_of_footage_cached when manual is nil" do
      g = create(:game)
      g.update_column(:hours_of_footage_cached, 7)
      expect(g.hours_of_footage).to eq(7)
    end

    it "returns nil when neither is set" do
      g = create(:game)
      expect(g.hours_of_footage).to be_nil
    end
  end

  describe "hours_of_footage_cached" do
    let(:channel) { create(:channel) }
    let(:game)    { create(:game) }

    it "recomputes on game-link create" do
      v = create(:video, channel: channel, duration_seconds: 7200)
      create(:video_game_link, video: v, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(2)
    end

    it "recomputes on game-link destroy" do
      v = create(:video, channel: channel, duration_seconds: 3600)
      link = create(:video_game_link, video: v, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(1)

      link.destroy!
      expect(game.reload.hours_of_footage_cached).to eq(0)
    end
  end

  describe "validations" do
    describe "title" do
      it { is_expected.to validate_presence_of(:title) }
      it { is_expected.to validate_length_of(:title).is_at_most(255) }

      it "accepts a 255-character title" do
        expect(build(:game, title: "x" * 255)).to be_valid
      end

      it "rejects a 256-character title" do
        expect(build(:game, title: "x" * 256)).not_to be_valid
      end

      it "accepts unicode" do
        expect(build(:game, title: "ゼルダの伝説 ブレス オブ ザ ワイルド")).to be_valid
      end

      it "rejects whitespace-only title" do
        expect(build(:game, title: "   ")).not_to be_valid
      end

      it 'defaults to "Untitled game"' do
        game = Game.create!
        expect(game.title).to eq("Untitled game")
      end
    end

    describe "igdb_id" do
      it "allows nil" do
        expect(build(:game, igdb_id: nil)).to be_valid
      end

      it "rejects duplicates" do
        create(:game, igdb_id: 7346)
        dup = build(:game, igdb_id: 7346)
        expect(dup).not_to be_valid
        expect(dup.errors[:igdb_id]).to be_present
      end

      it "rejects negative ids" do
        expect(build(:game, igdb_id: -1)).not_to be_valid
      end

      it "rejects zero" do
        expect(build(:game, igdb_id: 0)).not_to be_valid
      end

      it "rejects non-integer ids" do
        expect(build(:game, igdb_id: 7.5)).not_to be_valid
      end
    end

    describe "igdb_slug" do
      it "allows nil" do
        expect(build(:game, igdb_slug: nil)).to be_valid
      end

      it "rejects duplicates when present" do
        create(:game, igdb_slug: "the-zelda")
        expect(build(:game, igdb_slug: "the-zelda")).not_to be_valid
      end
    end

    describe "hours_of_footage_manual" do
      it "allows nil" do
        expect(build(:game, hours_of_footage_manual: nil)).to be_valid
      end

      it "accepts non-negative integers" do
        expect(build(:game, hours_of_footage_manual: 0)).to be_valid
        expect(build(:game, hours_of_footage_manual: 42)).to be_valid
      end

      it "rejects negative integers" do
        expect(build(:game, hours_of_footage_manual: -1)).not_to be_valid
      end

      it "rejects non-integer values" do
        expect(build(:game, hours_of_footage_manual: 1.5)).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:never_synced) { create(:game) }
    let!(:fresh_synced) { create(:game, :synced) }
    let!(:stale_synced) { create(:game, :stale) }

    describe ".synced" do
      it "includes only rows with igdb_synced_at set" do
        expect(Game.synced).to contain_exactly(fresh_synced, stale_synced)
      end
    end

    describe ".unsynced" do
      it "is the complement" do
        expect(Game.unsynced).to contain_exactly(never_synced)
      end
    end

    describe ".stale" do
      it "includes rows with igdb_synced_at < 7.days.ago" do
        expect(Game.stale).to contain_exactly(stale_synced)
      end
    end

    describe ".synced.stale" do
      it "is the right composition (no NULL synced_at rows)" do
        expect(Game.synced.stale).to contain_exactly(stale_synced)
      end
    end

    describe ".with_steam" do
      it "includes only rows with external_steam_app_id present" do
        expect(Game.with_steam).to contain_exactly(fresh_synced, stale_synced)
      end
    end
  end

  describe "#cover_url" do
    it "returns nil when cover_image_id is blank" do
      expect(build(:game, cover_image_id: nil).cover_url).to be_nil
    end

    it "returns the well-formed URL when present (default size)" do
      g = build(:game, cover_image_id: "abc123")
      expect(g.cover_url).to eq("https://images.igdb.com/igdb/image/upload/t_cover_big/abc123.jpg")
    end

    it "honors a whitelisted size" do
      g = build(:game, cover_image_id: "abc123")
      expect(g.cover_url(size: "t_thumb")).to include("t_thumb/abc123.jpg")
    end

    it "raises ArgumentError on an unknown size" do
      g = build(:game, cover_image_id: "abc123")
      expect { g.cover_url(size: "t_unknown") }.to raise_error(ArgumentError)
    end
  end

  describe "#hours_of_footage" do
    it "prefers the manual override" do
      g = build(:game, hours_of_footage_manual: 5, hours_of_footage_cached: 99)
      expect(g.hours_of_footage).to eq(5)
    end

    it "falls back to the cache when manual is nil" do
      g = build(:game, hours_of_footage_manual: nil, hours_of_footage_cached: 7)
      expect(g.hours_of_footage).to eq(7)
    end

    it "returns nil when both are nil" do
      g = build(:game, hours_of_footage_manual: nil, hours_of_footage_cached: nil)
      expect(g.hours_of_footage).to be_nil
    end
  end

  describe "#synced?" do
    it "is true when igdb_synced_at is set" do
      expect(build(:game, :synced).synced?).to eq(true)
    end

    it "is false when igdb_synced_at is nil" do
      expect(build(:game).synced?).to eq(false)
    end
  end

  # Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
  describe "#resyncing?" do
    it "defaults to false on new rows" do
      expect(create(:game).resyncing?).to eq(false)
    end

    it "is mutable via update_column without firing validations or callbacks" do
      g = create(:game)
      g.update_column(:resyncing, true)
      expect(g.reload.resyncing?).to eq(true)
    end
  end

  # Phase 14 §2 — Bundle membership.
  describe "bundle membership" do
    it { is_expected.to have_many(:bundle_members).dependent(:destroy) }
    it { is_expected.to have_many(:bundles).through(:bundle_members) }

    it "returns the bundles it is a member of" do
      game = create(:game)
      bundle = create(:bundle, bundle_type: :custom)
      bundle.bundle_members.create!(game: game)
      expect(game.reload.bundles).to include(bundle)
    end
  end

  describe "after_update_commit :invalidate_bundle_covers_if_image_changed" do
    let!(:game) { create(:game, :synced, cover_image_id: "old123") }

    it "enqueues BundleCoverInvalidate when cover_image_id changes" do
      BundleCoverInvalidate.clear
      game.update!(cover_image_id: "new456")
      expect(BundleCoverInvalidate.jobs.size).to eq(1)
      args = BundleCoverInvalidate.jobs.last["args"]
      expect(args[0]).to eq(game.id)
      expect(args[1]).to eq("old123")
    end

    it "does NOT enqueue when other columns change" do
      BundleCoverInvalidate.clear
      game.update!(notes: "some local notes")
      expect(BundleCoverInvalidate.jobs).to be_empty
    end
  end

  # Phase 27 §01h — collection composite eviction hook.
  describe "after_update_commit :evict_collection_composite_on_collection_change" do
    let!(:game) { create(:game, :synced, title: "g") }
    let(:c1)   { create(:collection, name: "C1") }
    let(:c2)   { create(:collection, name: "C2") }

    before { CollectionCoverRebuildJob.clear }

    it "enqueues with [nil, new_id] when a game is added to a collection" do
      game.update!(collection: c1)
      jobs = CollectionCoverRebuildJob.jobs
      expect(jobs.size).to eq(1)
      expect(jobs.last["args"]).to eq([ nil, c1.id ])
    end

    it "enqueues with [old_id, new_id] when a game moves between collections" do
      game.update!(collection: c1)
      CollectionCoverRebuildJob.clear

      game.update!(collection: c2)
      jobs = CollectionCoverRebuildJob.jobs
      expect(jobs.size).to eq(1)
      expect(jobs.last["args"]).to eq([ c1.id, c2.id ])
    end

    it "enqueues with [old_id, nil] when a game is removed from its collection" do
      game.update!(collection: c1)
      CollectionCoverRebuildJob.clear

      game.update!(collection: nil)
      jobs = CollectionCoverRebuildJob.jobs
      expect(jobs.size).to eq(1)
      expect(jobs.last["args"]).to eq([ c1.id, nil ])
    end

    it "does NOT enqueue when other columns change" do
      game.update!(collection: c1)
      CollectionCoverRebuildJob.clear

      game.update!(notes: "untouched by the collection hook")
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end

    it "does NOT enqueue when cover_image_id changes (collection_id unchanged)" do
      game.update!(collection: c1)
      CollectionCoverRebuildJob.clear

      game.update!(cover_image_id: "new-cid")
      expect(CollectionCoverRebuildJob.jobs).to be_empty
    end
  end
end
