require "rails_helper"

# Phase 14 §1 — Game model is now IGDB-backed.
RSpec.describe Game, type: :model do
  subject { build(:game) }

  describe "associations" do
    # Phase 27 follow-up (2026-05-17) — `belongs_to :collection` removed
    # along with the Collection model. Bundle membership is M2M through
    # `bundle_members`; covered by the bundle composite rebuild hooks
    # spec block below.
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

    # Phase 27 v2 spec 01 — single main genre per Game.
    it { is_expected.to belong_to(:primary_genre).class_name("Genre").optional }

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

  describe "Phase 27 §01b — status + on_platform scopes" do
    include ActiveSupport::Testing::TimeHelpers

    let(:now) { Time.zone.local(2026, 5, 11, 12, 0, 0) }

    around { |ex| travel_to(now) { ex.run } }

    describe ".recorded" do
      it "returns games with at least one linked Video" do
        game = create(:game)
        other = create(:game)
        create(:video_game_link, game: game)
        expect(Game.recorded).to include(game)
        expect(Game.recorded).not_to include(other)
      end

      it "returns DISTINCT rows when a game has many linked Videos" do
        game = create(:game)
        channel = create(:channel)
        2.times do
          v = create(:video, channel: channel)
          create(:video_game_link, game: game, video: v)
        end
        expect(Game.recorded.where(id: game.id).count).to eq(1)
      end
    end

    # Phase 27 v2 spec 06 — new scopes for the revamped filter row.
    describe ".played" do
      let!(:played)     { create(:game, played_at: 2.days.ago) }
      let!(:not_played) { create(:game, played_at: nil) }

      it "includes games with played_at non-null" do
        expect(Game.played).to include(played)
      end

      it "excludes games with nil played_at" do
        expect(Game.played).not_to include(not_played)
      end
    end

    describe ".wishlist" do
      let!(:platform)  { create(:platform, slug: "wishlist-spec-platform") }
      let!(:unowned)   { create(:game, title: "Wishlist Unowned") }
      let!(:owned) do
        g = create(:game, title: "Wishlist Owned")
        g.game_platform_ownerships.create!(platform: platform)
        g
      end

      it "includes games with ZERO ownership rows" do
        expect(Game.wishlist).to include(unowned)
      end

      it "excludes games with at least one ownership row" do
        expect(Game.wishlist).not_to include(owned)
      end

      it "is orthogonal to release status (scheduled-not-owned is included)" do
        future = create(:game, title: "Scheduled Wishlist", release_date: 1.year.from_now)
        expect(Game.wishlist).to include(future)
      end
    end

    describe ".released" do
      let!(:past)        { create(:game, release_date: 1.year.ago) }
      let!(:future)      { create(:game, release_date: 1.year.from_now) }
      let!(:nil_release) { create(:game, release_date: nil) }

      it "includes games with release_date <= now" do
        expect(Game.released).to include(past)
      end

      it "excludes games with release_date > now" do
        expect(Game.released).not_to include(future)
      end

      it "excludes games with nil release_date" do
        expect(Game.released).not_to include(nil_release)
      end

      it "is inclusive on today's date (boundary inclusive on past side)" do
        # `release_date` is a `date`; a release scheduled for today
        # counts as released, not scheduled.
        g = create(:game, release_date: Date.current)
        expect(Game.released).to include(g)
        expect(Game.scheduled).not_to include(g)
      end

      it "places tomorrow's release_date in scheduled" do
        g = create(:game, release_date: Date.current + 1)
        expect(Game.scheduled).to include(g)
        expect(Game.released).not_to include(g)
      end
    end

    describe ".scheduled" do
      let!(:past)        { create(:game, release_date: 1.year.ago) }
      let!(:future)      { create(:game, release_date: 1.year.from_now) }
      let!(:nil_release) { create(:game, release_date: nil) }

      it "includes only games whose release_date is in the future" do
        expect(Game.scheduled).to include(future)
        expect(Game.scheduled).not_to include(past)
      end

      it "excludes games with nil release_date" do
        expect(Game.scheduled).not_to include(nil_release)
      end
    end

    describe ".on_platform(slug)" do
      let!(:ps5)        { create(:platform, name: "PS5 onp",   slug: "ps5-onp") }
      let!(:switch2)    { create(:platform, name: "Sw2 onp",   slug: "sw2-onp") }
      let!(:on_ps5)     { create(:game) }
      let!(:on_both)    { create(:game) }
      let!(:no_platforms) { create(:game) }

      before do
        on_ps5.game_platforms.create!(platform: ps5)
        on_both.game_platforms.create!(platform: ps5)
        on_both.game_platforms.create!(platform: switch2)
      end

      it "matches games available on the named platform" do
        expect(Game.on_platform(ps5.slug)).to include(on_ps5, on_both)
      end

      it "excludes games not available on the named platform" do
        expect(Game.on_platform(ps5.slug)).not_to include(no_platforms)
      end

      it "returns DISTINCT rows when a game has multiple game_platforms join rows" do
        # Defensive distinct — the join itself is unique-per-pair, but
        # any future relaxation should not multiply this scope's rows.
        expect(Game.on_platform(ps5.slug).where(id: on_both.id).count).to eq(1)
      end

      it "returns an empty relation for an unknown slug (no error)" do
        expect(Game.on_platform("not-a-real-slug")).to be_empty
      end

      it "is safe against SQL-injection-shaped slug input (bind param)" do
        expect {
          Game.on_platform("ps5'; DROP TABLE games; --").to_a
        }.not_to raise_error
        # Table still exists.
        expect(Game.count).to be >= 0
      end
    end

    describe ".released_on(slug)" do
      let!(:ps5)        { create(:platform, name: "PS5 ron",   slug: "ps5-ron") }
      let!(:past_ps5)   { create(:game, release_date: 1.year.ago) }
      let!(:future_ps5) { create(:game, release_date: 1.year.from_now) }

      before do
        past_ps5.game_platforms.create!(platform: ps5)
        future_ps5.game_platforms.create!(platform: ps5)
      end

      it "is the intersection of released and on_platform" do
        expect(Game.released_on(ps5.slug)).to include(past_ps5)
        expect(Game.released_on(ps5.slug)).not_to include(future_ps5)
      end
    end

    describe ".scheduled_on(slug)" do
      let!(:ps5)        { create(:platform, name: "PS5 son",   slug: "ps5-son") }
      let!(:past_ps5)   { create(:game, release_date: 1.year.ago) }
      let!(:future_ps5) { create(:game, release_date: 1.year.from_now) }

      before do
        past_ps5.game_platforms.create!(platform: ps5)
        future_ps5.game_platforms.create!(platform: ps5)
      end

      it "is the intersection of scheduled and on_platform" do
        expect(Game.scheduled_on(ps5.slug)).to include(future_ps5)
        expect(Game.scheduled_on(ps5.slug)).not_to include(past_ps5)
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
      # Phase 27 follow-up (2026-05-17) — Bundle simplification dropped
      # `bundle_type` along with the :custom / :series / :collection /
      # :genre traits. A bundle is just a `name` now.
      bundle = create(:bundle)
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

  # Phase 27 follow-up (2026-05-17) — bundle composite rebuild hooks.
  #
  # Two hooks cover the trigger surfaces this model owns; each routes
  # through the orchestrator (`Bundles::CompositeRebuildQueue`) which
  # sorts alphabetically by `Bundle.name` and enqueues a sequential
  # chain. The add/remove surface is owned by `BundleMember`'s own
  # `after_commit` (single-bundle rebuilds) — covered in the
  # `BundleMember` spec instead.
  describe "bundle composite rebuild hooks (Phase 27 follow-up 2026-05-17)" do
    let!(:game) { create(:game, :synced, title: "g") }
    let(:b1)    { create(:bundle, name: "B1") }
    let(:b2)    { create(:bundle, name: "B2") }
    let(:queue) { instance_double(Bundles::CompositeRebuildQueue) }

    before do
      allow(Bundles::CompositeRebuildQueue).to receive(:new).and_return(queue)
      allow(queue).to receive(:enqueue_for_bundles).and_return([])
      allow(queue).to receive(:enqueue_for_game_resync).and_return([])
      allow(queue).to receive(:enqueue_for_game_destroy).and_return([])
    end

    describe "after_save_commit :rebuild_bundle_composites_on_resync" do
      it "enqueues a resync chain when igdb_synced_at is bumped" do
        b1.bundle_members.create!(game: game)
        game.update!(igdb_synced_at: Time.current + 1.day)
        expect(queue).to have_received(:enqueue_for_game_resync).with(game)
      end

      it "still calls the orchestrator when the game is in zero bundles (orchestrator no-ops on empty)" do
        game.update!(igdb_synced_at: Time.current + 1.day)
        expect(queue).to have_received(:enqueue_for_game_resync).with(game)
      end

      it "does NOT enqueue a resync chain when igdb_synced_at is unchanged" do
        b1.bundle_members.create!(game: game)
        game.update!(notes: "touch")
        expect(queue).not_to have_received(:enqueue_for_game_resync)
      end
    end

    describe "after_destroy_commit :rebuild_bundle_composites_on_destroy" do
      it "captures the pre-destroy bundles and enqueues a destroy chain" do
        b1.bundle_members.create!(game: game)
        b2.bundle_members.create!(game: game)
        game.reload
        # Prime the `bundles` association cache BEFORE destroy. The
        # `has_many :bundle_members, dependent: :destroy` declaration
        # (line ~189 in `app/models/game.rb`) is registered BEFORE the
        # explicit `before_destroy :capture_pre_destroy_bundles` (line
        # ~223), so the cascade clears the join rows BEFORE capture
        # runs. Calling `bundles.to_a` here populates the AR association
        # cache; `capture_pre_destroy_bundles` then reuses that cache
        # instead of re-querying the now-empty DB. The sanity-check
        # assertion doubles as the prime — `contain_exactly` because
        # `bundle_members` orders by `position` so ascending insertion
        # gives us [b1, b2], but we don't want the test to break if
        # Rails ever reorders the through-load.
        expect(game.bundles.to_a).to contain_exactly(b1, b2)
        game.destroy!
        expect(queue).to have_received(:enqueue_for_game_destroy)
          .with(game, hash_including(was_in: contain_exactly(b1, b2)))
      end

      it "does NOT enqueue a destroy chain when the game had no bundles" do
        game.destroy!
        expect(queue).not_to have_received(:enqueue_for_game_destroy)
      end
    end
  end

  # Phase 27 v2 spec 01 — Single main genre per Game.
  describe "Phase 27 v2 spec 01 — primary_genre management" do
    describe "before_save :assign_primary_genre_if_blank" do
      it "fires on save when primary_genre_id is blank and the game has linked genres" do
        adventure = create(:genre, name: "Adventure", igdb_id: 8_001)
        game      = create(:game, title: "v2 spec 01 — callback fire")
        # Wire two linked genres without going through `<<` (which has
        # its own GameGenre callback) — use create! on the join so the
        # picker has stable input.
        GameGenre.create!(game: game, genre: adventure)
        # Force the pointer back to nil to set up the assertion.
        game.update_column(:primary_genre_id, nil)
        game.notes = "trigger any save"
        game.save!
        expect(game.reload.primary_genre_id).to eq(adventure.id)
      end

      it "is a no-op when primary_genre_id is already set (idempotent)" do
        first  = create(:genre, name: "First",  igdb_id: 8_011)
        second = create(:genre, name: "Second", igdb_id: 8_012)
        game   = create(:game, title: "v2 spec 01 — pin honored")
        GameGenre.create!(game: game, genre: first)
        GameGenre.create!(game: game, genre: second)
        # Pin to `second` even though `first` would win alphabetically.
        game.update_column(:primary_genre_id, second.id)
        game.update!(notes: "save again")
        expect(game.reload.primary_genre_id).to eq(second.id)
      end

      it "picks the alphabetical-first genre for a multi-genre game" do
        rpg       = create(:genre, name: "RPG",       igdb_id: 8_021)
        adventure = create(:genre, name: "Adventure", igdb_id: 8_022)
        shooter   = create(:genre, name: "Shooter",   igdb_id: 8_023)
        game      = create(:game, title: "v2 spec 01 — multi pick")
        GameGenre.create!(game: game, genre: rpg)
        GameGenre.create!(game: game, genre: adventure)
        GameGenre.create!(game: game, genre: shooter)
        game.update_column(:primary_genre_id, nil)
        game.update!(notes: "trigger")
        expect(game.reload.primary_genre).to eq(adventure)
      end

      it "leaves primary_genre_id nil and does not raise when no genres are linked" do
        game = create(:game, title: "v2 spec 01 — zero genres")
        # Force the pointer to nil (the factory might leave it nil
        # anyway; this is the guard).
        game.update_column(:primary_genre_id, nil)
        expect { game.update!(notes: "trigger") }.not_to raise_error
        expect(game.reload.primary_genre_id).to be_nil
      end

      it "writes nil cleanly when the picker returns nil (no genres after sync)" do
        # The hook only fires when `primary_genre_id` is currently
        # blank, so a sync that nulled the pointer then saves with no
        # linked genres should leave nil in place (not write garbage).
        game = create(:game, title: "v2 spec 01 — picker-nil write")
        game.update_column(:primary_genre_id, nil)
        game.update!(notes: "trigger")
        expect(game.reload.primary_genre_id).to be_nil
      end
    end

    describe "FK on_delete: :nullify" do
      it "nullifies primary_genre_id when the pinned Genre is deleted" do
        genre = create(:genre, name: "DeleteMe", igdb_id: 8_031)
        game  = create(:game, title: "v2 spec 01 — FK nullify")
        GameGenre.create!(game: game, genre: genre)
        game.update_column(:primary_genre_id, genre.id)

        genre.destroy!
        expect { game.reload }.not_to raise_error
        expect(game.primary_genre_id).to be_nil
      end
    end
  end

  # Phase 28 §01a — Multi-version game grouping.
  describe "Phase 28 §01a — multi-version grouping" do
    describe "associations" do
      it { is_expected.to belong_to(:version_parent).class_name("Game").optional }
      it "has_many :editions with dependent: :nullify" do
        primary = create(:game, title: "Pragmata")
        edition = create(:game, title: "Pragmata Deluxe Edition", version_parent: primary)
        expect(primary.editions).to include(edition)
        primary.destroy!
        expect(edition.reload.version_parent_id).to be_nil
      end
    end

    describe "predicates" do
      let(:primary) { create(:game, title: "Pragmata") }
      let(:edition) { create(:game, title: "Pragmata Deluxe", version_parent: primary) }

      it "primary? returns true for a primary" do
        expect(primary.primary?).to be true
        expect(primary.edition?).to be false
      end

      it "edition? returns true for an edition" do
        expect(edition.edition?).to be true
        expect(edition.primary?).to be false
      end
    end

    describe "scopes" do
      let!(:primary)  { create(:game, title: "Pragmata") }
      let!(:edition)  { create(:game, title: "Pragmata Deluxe", version_parent: primary) }
      let!(:other)    { create(:game, title: "Halo 3") }

      describe ".primaries" do
        it "excludes editions" do
          expect(Game.primaries).to include(primary, other)
          expect(Game.primaries).not_to include(edition)
        end
      end

      describe ".editions_of(game)" do
        it "returns the given game's editions" do
          expect(Game.editions_of(primary)).to contain_exactly(edition)
        end

        it "returns an empty relation for nil" do
          rel = Game.editions_of(nil)
          expect(rel).to be_a(ActiveRecord::Relation)
          expect(rel).to be_empty
        end

        it "returns an empty relation for a primary with no editions" do
          expect(Game.editions_of(other)).to be_empty
        end
      end

      describe ".with_editions" do
        it "returns only primaries that have at least one edition" do
          expect(Game.with_editions).to contain_exactly(primary)
        end
      end

      describe ".owned_rollup" do
        let(:platform) { create(:platform, slug: "rollup-platform") }

        it "includes a primary whose own ownership is set" do
          create(:game_platform_ownership, game: primary, platform: platform)
          expect(Game.owned_rollup).to include(primary)
        end

        it "includes a primary that owns nothing itself but has an edition with ownership" do
          create(:game_platform_ownership, game: edition, platform: platform)
          expect(Game.owned_rollup).to include(primary)
        end

        it "includes the owned edition itself" do
          create(:game_platform_ownership, game: edition, platform: platform)
          expect(Game.owned_rollup).to include(edition)
        end

        it "excludes a primary with no own ownership and no owned editions" do
          expect(Game.owned_rollup).not_to include(primary)
          expect(Game.owned_rollup).not_to include(other)
        end

        it "is composable with where chains" do
          create(:game_platform_ownership, game: primary, platform: platform)
          expect(Game.owned_rollup.where(id: primary.id)).to contain_exactly(primary)
        end
      end
    end

    describe "validations" do
      let!(:primary)  { create(:game, title: "Pragmata") }

      it "rejects pointing version_parent at an existing edition" do
        deluxe = create(:game, title: "Pragmata Deluxe", version_parent: primary)
        sibling = create(:game, title: "Pragmata Standard")
        sibling.version_parent = deluxe
        expect(sibling).not_to be_valid
        expect(sibling.errors[:version_parent_id]).to include(/must be a primary/i)
      end

      it "rejects self-reference" do
        primary.version_parent_id = primary.id
        expect(primary).not_to be_valid
        expect(primary.errors[:version_parent_id]).to include(/cannot reference itself/i)
      end

      it "rejects setting version_parent on a row that already has editions" do
        _edition = create(:game, version_parent: primary)
        sibling  = create(:game)
        primary.version_parent = sibling
        expect(primary).not_to be_valid
        expect(primary.errors[:version_parent_id]).to include(/already has editions/i)
      end

      it "allows a clean attach" do
        deluxe = build(:game, title: "Pragmata Deluxe", version_parent: primary)
        expect(deluxe).to be_valid
      end

      it "allows detach (setting version_parent_id back to nil)" do
        deluxe = create(:game, title: "Pragmata Deluxe", version_parent: primary)
        deluxe.version_parent_id = nil
        expect(deluxe).to be_valid
        deluxe.save!
        expect(deluxe.reload.primary?).to be true
      end
    end

    describe "#owned_platforms_with_editions" do
      let!(:primary)  { create(:game, title: "Pragmata") }
      let!(:edition)  { create(:game, title: "Pragmata Deluxe", version_parent: primary) }
      let!(:ps5)      { create(:platform, name: "Rollup PS5") }
      let!(:steam)    { create(:platform, name: "Rollup Steam") }

      it "unions primary + editions ownership and dedupes" do
        create(:game_platform_ownership, game: primary, platform: ps5)
        create(:game_platform_ownership, game: edition, platform: steam)
        create(:game_platform_ownership, game: edition, platform: ps5)
        expect(primary.owned_platforms_with_editions.map(&:id))
          .to contain_exactly(ps5.id, steam.id)
      end

      it "is equivalent to owned_platforms for an edition" do
        create(:game_platform_ownership, game: edition, platform: ps5)
        expect(edition.owned_platforms_with_editions.map(&:id))
          .to contain_exactly(ps5.id)
      end

      it "returns the primary's own ownerships when it has no editions" do
        lonely = create(:game, title: "Lonely")
        create(:game_platform_ownership, game: lonely, platform: steam)
        expect(lonely.owned_platforms_with_editions.map(&:id)).to contain_exactly(steam.id)
      end
    end

    describe "#owned_editions(platform)" do
      let!(:primary)  { create(:game, title: "Pragmata") }
      let!(:deluxe)   { create(:game, title: "Pragmata Deluxe", version_parent: primary) }
      let!(:standard) { create(:game, title: "Pragmata Standard", version_parent: primary) }
      let!(:ps5)      { create(:platform, name: "Owned Editions PS5") }
      let!(:steam)    { create(:platform, name: "Owned Editions Steam") }

      it "returns editions owned on the given platform" do
        create(:game_platform_ownership, game: deluxe, platform: ps5)
        expect(primary.owned_editions(ps5)).to contain_exactly(deluxe)
      end

      it "returns an empty relation for an edition" do
        expect(deluxe.owned_editions(ps5)).to be_empty
      end

      it "returns an empty relation for nil platform" do
        expect(primary.owned_editions(nil)).to be_empty
      end

      it "filters to the matching platform only" do
        create(:game_platform_ownership, game: deluxe,   platform: ps5)
        create(:game_platform_ownership, game: standard, platform: steam)
        expect(primary.owned_editions(ps5)).to contain_exactly(deluxe)
      end
    end

    describe "release_date derivation" do
      let!(:primary) { create(:game, title: "Pragmata") }

      it "derives the primary's release_date from the earliest edition when blank" do
        create(:game, title: "Pragmata Standard", version_parent: primary,
                      release_date: Date.new(2025, 3, 1))
        create(:game, title: "Pragmata Deluxe", version_parent: primary,
                      release_date: Date.new(2024, 5, 1))
        primary.update!(notes: "trigger")
        expect(primary.reload.release_date).to eq(Date.new(2024, 5, 1))
        expect(primary.release_year).to eq(2024)
      end

      it "does NOT overwrite an existing release_date on the primary" do
        primary.update!(release_date: Date.new(2020, 1, 1), release_year: 2020)
        create(:game, version_parent: primary, release_date: Date.new(2019, 6, 1))
        primary.update!(notes: "trigger")
        expect(primary.reload.release_date).to eq(Date.new(2020, 1, 1))
      end

      it "honors manual_date_override (skips derivation)" do
        primary.update!(manual_date_override: true)
        create(:game, version_parent: primary, release_date: Date.new(2024, 1, 1))
        primary.update!(notes: "trigger")
        expect(primary.reload.release_date).to be_nil
      end

      it "does not derive for editions" do
        edition = create(:game, version_parent: primary)
        edition.update!(notes: "edition save")
        expect(edition.reload.release_date).to be_nil
      end
    end
  end
end
