require "rails_helper"

RSpec.describe VideoGameLink, type: :model do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel: channel) }
  let(:game)    { create(:game) }
  let(:bundle)  { create(:bundle) }

  describe "associations" do
    it { is_expected.to belong_to(:video) }
    it { is_expected.to belong_to(:game).optional }
    it { is_expected.to belong_to(:bundle).optional }
    it { is_expected.to belong_to(:created_by_user).class_name("User").optional }
  end

  describe "enum link_type" do
    it "maps game to 0 and bundle to 1" do
      expect(described_class.link_types).to eq("game" => 0, "bundle" => 1)
    end

    it "exposes prefixed predicates" do
      link = create(:video_game_link, video: video, game: game)
      expect(link.link_game?).to be(true)
      expect(link.link_bundle?).to be(false)
    end
  end

  describe "validations: exactly_one_target" do
    it "is valid for a game link with game_id and no bundle_id" do
      link = build(:video_game_link, video: video, game: game, bundle: nil, link_type: :game)
      expect(link).to be_valid
    end

    it "is valid for a bundle link with bundle_id and no game_id" do
      link = build(:video_game_link, :bundle, video: video, bundle: bundle)
      expect(link).to be_valid
    end

    it "is invalid for a game link with game_id nil" do
      link = build(:video_game_link, video: video, game: nil, bundle: nil, link_type: :game)
      expect(link).not_to be_valid
    end

    it "is invalid for a game link with both ids set" do
      link = build(:video_game_link, video: video, game: game, bundle: bundle, link_type: :game)
      expect(link).not_to be_valid
    end

    it "is invalid for a bundle link with both ids set" do
      link = build(:video_game_link, :bundle, video: video, game: game, bundle: bundle)
      expect(link).not_to be_valid
    end

    it "is invalid for a bundle link with bundle_id nil" do
      link = build(:video_game_link, :bundle, video: video, bundle: nil, game: nil)
      expect(link).not_to be_valid
    end
  end

  describe "uniqueness" do
    it "rejects a duplicate (video_id, game_id) pair" do
      create(:video_game_link, video: video, game: game)
      dup = build(:video_game_link, video: video, game: game)
      expect(dup).not_to be_valid
    end

    it "allows the same game on different videos" do
      other_video = create(:video, channel: channel)
      create(:video_game_link, video: video, game: game)
      link = build(:video_game_link, video: other_video, game: game)
      expect(link).to be_valid
    end

    it "allows different games on the same video" do
      other_game = create(:game)
      create(:video_game_link, video: video, game: game)
      link = build(:video_game_link, video: video, game: other_game)
      expect(link).to be_valid
    end

    it "rejects a duplicate (video_id, bundle_id) pair" do
      create(:video_game_link, :bundle, video: video, bundle: bundle)
      dup = build(:video_game_link, :bundle, video: video, bundle: bundle)
      expect(dup).not_to be_valid
    end
  end

  describe "is_primary" do
    it "defaults to false" do
      link = create(:video_game_link, video: video, game: game)
      expect(link.is_primary).to be(false)
    end

    it "allows multiple primaries on a single video" do
      g2 = create(:game)
      create(:video_game_link, :primary, video: video, game: game)
      second = build(:video_game_link, :primary, video: video, game: g2)
      expect(second).to be_valid
    end
  end

  describe "#target" do
    it "returns the game for game links" do
      link = create(:video_game_link, video: video, game: game)
      expect(link.target).to eq(game)
    end

    it "returns the bundle for bundle links" do
      link = create(:video_game_link, :bundle, video: video, bundle: bundle)
      expect(link.target).to eq(bundle)
    end
  end

  describe "created_by_user audit column" do
    it "stamps Current.user on create" do
      user = create(:user)
      Current.user = user
      link = create(:video_game_link, video: video, game: game)
      expect(link.created_by_user_id).to eq(user.id)
    ensure
      Current.user = nil
    end

    it "leaves created_by_user_id nil when Current.user is unset" do
      Current.user = nil
      link = create(:video_game_link, video: video, game: game)
      expect(link.created_by_user_id).to be_nil
    end
  end

  describe "footage cache recompute on game links" do
    let(:video_short) { create(:video, channel: channel, duration_seconds: 600) }
    let(:video_long)  { create(:video, channel: channel, duration_seconds: 7200) }

    it "rounds 600s (~0.16h) to 0" do
      create(:video_game_link, video: video_short, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(0)
    end

    it "rounds 7200s (2h) to 2" do
      create(:video_game_link, video: video_long, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(2)
    end

    it "sums multiple linked videos: 3600 + 5400 + 1800 = 10800 → 3" do
      v1 = create(:video, channel: channel, duration_seconds: 3600)
      v2 = create(:video, channel: channel, duration_seconds: 5400)
      v3 = create(:video, channel: channel, duration_seconds: 1800)
      create(:video_game_link, video: v1, game: game)
      create(:video_game_link, video: v2, game: game)
      create(:video_game_link, video: v3, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(3)
    end

    it "decreases the cache after a link is destroyed" do
      v1 = create(:video, channel: channel, duration_seconds: 7200)
      v2 = create(:video, channel: channel, duration_seconds: 3600)
      link1 = create(:video_game_link, video: v1, game: game)
      create(:video_game_link, video: v2, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(3)

      link1.destroy!
      expect(game.reload.hours_of_footage_cached).to eq(1)
    end

    it "does not touch hours_of_footage_cached for bundle links" do
      previous = game.hours_of_footage_cached
      create(:video_game_link, :bundle, video: video, bundle: bundle)
      expect(game.reload.hours_of_footage_cached).to eq(previous)
    end
  end

  describe "DB-level integrity" do
    it "rejects raw SQL inserts that smuggle both target ids" do
      v_id = video.id
      g_id = game.id
      b_id = bundle.id
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO video_game_links
            (video_id, link_type, game_id, bundle_id, is_primary, created_at, updated_at)
          VALUES (#{v_id}, 0, #{g_id}, #{b_id}, false, NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /video_game_links_exactly_one_target/)
    end
  end

  describe "cascade-on-delete" do
    it "destroys the link when the linked game is destroyed" do
      link = create(:video_game_link, video: video, game: game)
      game.destroy!
      expect(VideoGameLink.where(id: link.id)).to be_empty
    end

    it "destroys the link when the linked bundle is destroyed" do
      link = create(:video_game_link, :bundle, video: video, bundle: bundle)
      bundle.destroy!
      expect(VideoGameLink.where(id: link.id)).to be_empty
    end

    it "destroys the link when the parent video is destroyed and recomputes footage cache" do
      v = create(:video, channel: channel, duration_seconds: 7200)
      create(:video_game_link, video: v, game: game)
      expect(game.reload.hours_of_footage_cached).to eq(2)

      v.destroy!
      expect(game.reload.hours_of_footage_cached).to eq(0)
    end
  end
end
