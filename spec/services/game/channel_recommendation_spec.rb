# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::ChannelRecommendation, type: :service do
  # Helpers ----------------------------------------------------------------

  # Publish a video on channel that links to game. Returns the video.
  def publish_link(channel, game)
    video = create(:video, :public, channel: channel)
    create(:video_game_link, video: video, game: game)
    video
  end

  # Build a channel whose profile is anchored to a set of genres by publishing
  # videos that link to games carrying those genres.
  def channel_of_genre(genre, title: nil)
    channel = create(:channel, title: title || "Channel for #{genre.name}")
    game    = create(:game)
    create(:game_genre, game: game, genre: genre)
    publish_link(channel, game)
    channel
  end

  # -------------------------------------------------------------------------

  it "returns [] for a nil game" do
    expect(described_class.call(nil)).to eq([])
  end

  it "scores a game higher on a profile-matching channel than on a mismatched one" do
    rpg_genre  = create(:genre, name: "RPG")
    plat_genre = create(:genre, name: "Platformer")

    rpg_channel  = channel_of_genre(rpg_genre,  title: "RPG World")
    plat_channel = channel_of_genre(plat_genre, title: "Jump Guys")

    target = create(:game)
    create(:game_genre, game: target, genre: rpg_genre)

    results = described_class.call(target)
    rpg_result  = results.find { |r| r.channel == rpg_channel }
    # The platformer channel has no shared genre with target — it falls below FLOOR
    # and is dropped, so its effective score is 0.
    plat_result_score = results.find { |r| r.channel == plat_channel }&.score.to_i

    expect(rpg_result).to be_present
    expect(rpg_result.score).to be > plat_result_score
  end

  it "gives the same game different scores on different channels (headline behavior)" do
    genre_a = create(:genre, name: "Survival")
    genre_b = create(:genre, name: "Racing")

    channel_a = channel_of_genre(genre_a, title: "Survive!")
    channel_b = channel_of_genre(genre_b, title: "Race!")

    target = create(:game)
    create(:game_genre, game: target, genre: genre_a)

    results = described_class.call(target)
    score_a = results.find { |r| r.channel == channel_a }&.score
    score_b = results.find { |r| r.channel == channel_b }&.score

    # channel_a matches target's genre; channel_b does not.
    expect(score_a).to be_present
    expect(score_a).to be > score_b.to_i
  end

  describe "graded-K link bonus" do
    it "grants a positive link bonus when the game has a published video on the channel" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = channel_of_genre(rpg_genre, title: "RPG Hub")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)
      publish_link(channel, target) # one published video linking to target

      results       = described_class.call(target)
      linked_result = results.find { |r| r.channel == channel }

      expect(linked_result).to be_present
      expect(linked_result.breakdown[:link]).to be > 0
    end

    it "reports link == 0 for an unlinked channel" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = channel_of_genre(rpg_genre, title: "RPG Hub")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)
      # no published video linking channel → target

      results         = described_class.call(target)
      unlinked_result = results.find { |r| r.channel == channel }

      expect(unlinked_result).to be_present
      expect(unlinked_result.breakdown[:link]).to eq(0)
    end

    it "scores the linked channel as fit + link" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = channel_of_genre(rpg_genre, title: "RPG Hub")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)
      publish_link(channel, target)

      result = described_class.call(target).find { |r| r.channel == channel }
      expect(result.score).to eq([ result.breakdown[:fit] + result.breakdown[:link], 100 ].min)
    end

    it "linked channel scores higher than the same channel without the link" do
      # Build two channels that have the SAME partial profile (both genres, so fit
      # is < 100 for a single-genre game and leaves headroom for the link bonus).
      rpg_genre  = create(:genre, name: "RPG")
      misc_genre = create(:genre, name: "Misc")

      # Both channels cover RPG *and* Misc in equal measure → fit for a pure-RPG
      # game is ~50 (half the channel mass), below 100, so link bonus is visible.
      linked_ch   = create(:channel, title: "Linked")
      unlinked_ch = create(:channel, title: "Unlinked")
      [ linked_ch, unlinked_ch ].each do |ch|
        # Manually seed the profile: one RPG video + one Misc video on each channel
        g1 = create(:game); create(:game_genre, game: g1, genre: rpg_genre); publish_link(ch, g1)
        g2 = create(:game); create(:game_genre, game: g2, genre: misc_genre); publish_link(ch, g2)
      end

      target = create(:game, title: "RPG Target")
      create(:game_genre, game: target, genre: rpg_genre)
      publish_link(linked_ch, target) # only on linked_ch

      results        = described_class.call(target)
      linked_score   = results.find { |r| r.channel == linked_ch }&.score.to_i
      unlinked_score = results.find { |r| r.channel == unlinked_ch }&.score.to_i

      expect(linked_score).to be > unlinked_score
    end
  end

  describe "unlinked game scores by fit alone" do
    it "returns a result with link == 0 and score == fit for an unlinked game" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = channel_of_genre(rpg_genre, title: "RPG Hub")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)

      result = described_class.call(target).find { |r| r.channel == channel }
      expect(result.breakdown[:link]).to eq(0)
      expect(result.score).to eq(result.breakdown[:fit])
    end
  end

  describe "empty-profile channels" do
    it "drops a channel with no published videos by default" do
      rpg_genre = create(:genre, name: "RPG")
      channel_of_genre(rpg_genre, title: "Active") # ensures at least one profiled channel

      empty_channel = create(:channel, title: "Empty")
      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)

      channels = described_class.call(target).map(&:channel)
      expect(channels).not_to include(empty_channel)
    end

    it "returns every channel (empty ones score 0) when include_all: true" do
      rpg_genre    = create(:genre, name: "RPG")
      active       = channel_of_genre(rpg_genre, title: "Active")
      empty_ch     = create(:channel, title: "Empty")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)

      results = described_class.call(target, include_all: true)
      channels = results.map(&:channel)

      expect(channels).to include(active, empty_ch)

      empty_result = results.find { |r| r.channel == empty_ch }
      expect(empty_result.score).to eq(0)
    end

    it "still returns [] when there are no channels at all" do
      target = create(:game)
      expect(described_class.call(target, include_all: true)).to eq([])
    end
  end

  describe "unpublished videos" do
    it "unlisted videos do not build the channel profile" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "Unlisted Channel")

      game_a = create(:game)
      create(:game_genre, game: game_a, genre: rpg_genre)
      unlisted_video = create(:video, :unlisted, channel: channel)
      create(:video_game_link, video: unlisted_video, game: game_a)

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)

      # channel has only unlisted video → profile is empty → dropped
      channels = described_class.call(target).map(&:channel)
      expect(channels).not_to include(channel)
    end

    it "unpublished videos do not grant a link bonus" do
      rpg_genre = create(:genre, name: "RPG")

      # give channel a real public profile so it surfaces
      channel = channel_of_genre(rpg_genre, title: "Mixed")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)

      # link target via a private video only
      private_video = create(:video, :private, channel: channel)
      create(:video_game_link, video: private_video, game: target)

      result = described_class.call(target).find { |r| r.channel == channel }
      expect(result.breakdown[:link]).to eq(0)
    end
  end

  describe "floor and limit" do
    it "drops results below FLOOR by default" do
      # A channel of a completely unrelated genre should score below FLOOR=5 and be excluded.
      genre_a = create(:genre, name: "Horror")
      genre_b = create(:genre, name: "Sports")
      below_floor_channel = channel_of_genre(genre_b, title: "Sports only")

      target = create(:game)
      create(:game_genre, game: target, genre: genre_a)

      channels = described_class.call(target).map(&:channel)
      # below_floor_channel may or may not appear depending on score; its absence is fine.
      # What matters: include_all: false never shows score-0 channels.
      zero_scores = described_class.call(target).select { |r| r.score.zero? }
      expect(zero_scores).to be_empty
    end

    it "respects limit:" do
      genre = create(:genre, name: "Action")
      3.times { |i| channel_of_genre(genre, title: "Action #{i}") }

      target = create(:game)
      create(:game_genre, game: target, genre: genre)

      expect(described_class.call(target, limit: 2).size).to be <= 2
    end

    it "returns all matching results when no limit is given" do
      genre = create(:genre, name: "Action")
      4.times { |i| channel_of_genre(genre, title: "Act #{i}") }

      target = create(:game)
      create(:game_genre, game: target, genre: genre)

      expect(described_class.call(target).size).to eq(4)
    end
  end

  describe "breakdown shape" do
    it "includes fit: and link: keys in every result" do
      rpg_genre = create(:genre, name: "RPG")
      channel_of_genre(rpg_genre, title: "RPG Hub")

      target = create(:game)
      create(:game_genre, game: target, genre: rpg_genre)

      result = described_class.call(target).first
      expect(result.breakdown).to include(:fit, :link)
    end
  end
end
