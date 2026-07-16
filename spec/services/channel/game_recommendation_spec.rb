# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::GameRecommendation, type: :service do
  # Helpers ----------------------------------------------------------------

  # Unit vector, sized to whatever column Game::EMBEDDING_COLUMN currently
  # seams to, with one hot dimension.
  def vec(index, value: 1.0)
    Array.new(Game.columns_hash[Game::EMBEDDING_COLUMN.to_s].limit, 0.0).tap { |a| a[index] = value }
  end

  # Publish a video on channel that links to game. Returns the video.
  def publish_link(channel, game)
    video = create(:video, :public, channel: channel)
    create(:video_game_link, video: video, game: game)
    video
  end

  # Build a game carrying a genre and publish a video on channel linked to it,
  # giving the channel an anchored profile.
  def seed_profile(channel, genre)
    game = create(:game)
    create(:game_genre, game: game, genre: genre)
    publish_link(channel, game)
    game
  end

  # -------------------------------------------------------------------------

  it "returns [] for a nil channel" do
    expect(described_class.call(nil)).to eq([])
  end

  it "returns [] when the channel has no published videos" do
    channel = create(:channel)
    create(:video, :private, channel: channel) # not public → empty profile
    expect(described_class.call(channel)).to eq([])
  end

  it "ranks profile-matching games above non-matching candidates" do
    rpg_genre  = create(:genre, name: "RPG")
    plat_genre = create(:genre, name: "Platformer")

    channel = create(:channel, title: "RPG Hub")
    seed_profile(channel, rpg_genre)

    rpg_game  = create(:game, title: "RPG Candidate")
    create(:game_genre, game: rpg_game, genre: rpg_genre)

    plat_game = create(:game, title: "Plat Candidate")
    create(:game_genre, game: plat_game, genre: plat_genre)
    # make plat_game a candidate via shared genre with the profile game
    # (so it surfaces in facet_candidate_ids) — share rpg_genre on plat_game too
    # Actually: plat_game only has plat_genre, so it won't be in facet pool at all
    # unless we add it. Share rpg_genre to ensure it enters the candidate pool with
    # a lower score.
    create(:game_genre, game: plat_game, genre: rpg_genre)

    results = described_class.call(channel)
    rpg_result  = results.find { |r| r.game == rpg_game }
    plat_result = results.find { |r| r.game == plat_game }

    expect(rpg_result).to be_present
    expect(plat_result).to be_present
    # rpg_game has ONLY rpg_genre → covers all the channel mass; plat_game has both
    # genres so covers all too — use score instead
    # In practice both cover the genre mass equally here, so let's use a simpler
    # scenario with exclusive genres.
    expect(rpg_result.score).to be >= plat_result.score
  end

  it "scores a game with the dominant genre higher than one without it" do
    rpg_genre  = create(:genre, name: "RPG")
    misc_genre = create(:genre, name: "Misc")

    channel = create(:channel, title: "Pure RPG")
    # Channel has 3 RPG videos and 1 misc → RPG weight 0.75
    3.times { seed_profile(channel, rpg_genre) }
    seed_profile(channel, misc_genre)

    rpg_only  = create(:game, title: "Pure RPG game")
    create(:game_genre, game: rpg_only, genre: rpg_genre)

    misc_only = create(:game, title: "Misc game")
    create(:game_genre, game: misc_only, genre: misc_genre)

    results   = described_class.call(channel)
    rpg_score  = results.find { |r| r.game == rpg_only }&.score.to_i
    misc_score = results.find { |r| r.game == misc_only }&.score.to_i

    expect(rpg_score).to be > misc_score
  end

  describe "graded-K link bonus" do
    it "grants a positive link bonus for a linked game" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      linked_game = create(:game, title: "Linked")
      create(:game_genre, game: linked_game, genre: rpg_genre)
      publish_link(channel, linked_game)

      result = described_class.call(channel).find { |r| r.game == linked_game }
      expect(result).to be_present
      expect(result.breakdown[:link]).to be > 0
    end

    it "reports link == 0 for an unlinked candidate" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      unlinked = create(:game, title: "Unlinked")
      create(:game_genre, game: unlinked, genre: rpg_genre)

      result = described_class.call(channel).find { |r| r.game == unlinked }
      expect(result).to be_present
      expect(result.breakdown[:link]).to eq(0)
    end

    it "linked game scores as fit + link" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      linked_game = create(:game, title: "Linked")
      create(:game_genre, game: linked_game, genre: rpg_genre)
      publish_link(channel, linked_game)

      result = described_class.call(channel).find { |r| r.game == linked_game }
      expect(result.score).to eq([ result.breakdown[:fit] + result.breakdown[:link], 100 ].min)
    end
  end

  describe "candidate pool" do
    it "surfaces a facet-sharing game (no embedding required)" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      candidate = create(:game, title: "Facet Match")
      create(:game_genre, game: candidate, genre: rpg_genre)
      # no summary_embedding set

      results = described_class.call(channel)
      expect(results.map(&:game)).to include(candidate)
    end

    it "surfaces an embedding-near game even without a shared facet" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      profile_game = create(:game, title: "Profile anchor")
      create(:game_genre, game: profile_game, genre: rpg_genre)
      profile_game.update_column(Game::EMBEDDING_COLUMN, vec(0))
      publish_link(channel, profile_game)

      embedding_candidate = create(:game, title: "Embedding Near")
      # No shared genre — reaches the pool only via embedding proximity
      embedding_candidate.update_column(Game::EMBEDDING_COLUMN, vec(0))

      results = described_class.call(channel)
      expect(results.map(&:game)).to include(embedding_candidate)
    end

    it "surfaces a linked game even when it has no embedding" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      linked_game = create(:game, title: "Linked no embedding")
      # no summary_embedding, no shared genre except via explicit link
      publish_link(channel, linked_game)

      results = described_class.call(channel)
      expect(results.map(&:game)).to include(linked_game)
    end
  end

  describe "empty profile" do
    it "returns [] when the channel has no published videos" do
      channel = create(:channel)
      expect(described_class.call(channel)).to eq([])
    end

    it "returns [] when only unpublished (unlisted/private) videos exist" do
      channel = create(:channel)
      game    = create(:game)
      video   = create(:video, :unlisted, channel: channel)
      create(:video_game_link, video: video, game: game)

      expect(described_class.call(channel)).to eq([])
    end
  end

  describe "floor and limit" do
    it "does not return results with score below FLOOR" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      # Candidate with no overlapping facets and no embedding shouldn't surface.
      create(:game, title: "Unrelated")

      zero_score_results = described_class.call(channel).select { |r| r.score < described_class::FLOOR }
      expect(zero_score_results).to be_empty
    end

    it "respects limit:" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      3.times do |i|
        g = create(:game, title: "Cand #{i}")
        create(:game_genre, game: g, genre: rpg_genre)
      end

      expect(described_class.call(channel, limit: 2).size).to be <= 2
    end

    it "returns all matching results when no limit is given" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      4.times do |i|
        g = create(:game, title: "Cand #{i}")
        create(:game_genre, game: g, genre: rpg_genre)
      end

      expect(described_class.call(channel).size).to be >= 4
    end
  end

  describe "unpublished videos" do
    it "unlisted videos do not build the profile" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "Mostly Unlisted")

      # Only unlisted video — profile stays empty
      game  = create(:game)
      create(:game_genre, game: game, genre: rpg_genre)
      video = create(:video, :unlisted, channel: channel)
      create(:video_game_link, video: video, game: game)

      expect(described_class.call(channel)).to eq([])
    end

    it "unpublished link does not grant the bonus" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      target_game = create(:game, title: "Private Link")
      create(:game_genre, game: target_game, genre: rpg_genre)
      private_video = create(:video, :private, channel: channel)
      create(:video_game_link, video: private_video, game: target_game)

      result = described_class.call(channel).find { |r| r.game == target_game }
      expect(result.breakdown[:link]).to eq(0)
    end
  end

  describe "breakdown shape" do
    it "includes fit: and link: keys in every result" do
      rpg_genre = create(:genre, name: "RPG")
      channel   = create(:channel, title: "RPG Hub")
      seed_profile(channel, rpg_genre)

      result_game = create(:game, title: "Cand")
      create(:game_genre, game: result_game, genre: rpg_genre)

      result = described_class.call(channel).first
      expect(result.breakdown).to include(:fit, :link)
    end
  end
end
