# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::ProfileFit do
  Profile = Pito::Recommendation::ChannelProfile::Profile

  def profile(**overrides)
    base = {
      genres: {}, themes: {}, perspectives: {}, developers: {}, publishers: {}, platforms: {},
      score: nil, ttb_seconds: nil, year: nil, embedding: nil,
      linked_game_ids: [ 1 ], total_videos: 1
    }
    Profile.new(**base.merge(overrides))
  end

  def game_with_genres(*genres)
    game = create(:game)
    genres.each { |genre| create(:game_genre, game: game, genre: genre) }
    game
  end

  it "scores a game on the channel's dominant genre higher than a rare-genre game" do
    rpg  = create(:genre, name: "RPG")
    plat = create(:genre, name: "Platform")
    prof = profile(genres: { rpg.id => 0.8, plat.id => 0.2 })

    expect(described_class.call(game_with_genres(rpg), prof)).to eq(80)  # covers 0.8 of the mass
    expect(described_class.call(game_with_genres(plat), prof)).to eq(20)
    expect(described_class.call(game_with_genres(rpg), prof))
      .to be > described_class.call(game_with_genres(plat), prof)
  end

  it "rewards covering MORE of the channel's genre mass" do
    rpg  = create(:genre, name: "RPG")
    plat = create(:genre, name: "Platform")
    prof = profile(genres: { rpg.id => 0.6, plat.id => 0.4 })

    expect(described_class.call(game_with_genres(rpg, plat), prof)).to eq(100) # covers all
  end

  it "blends the score-smile against the channel's score centroid" do
    prof = profile(score: 95) # an elite channel
    elite = create(:game, score: 96)
    mid   = create(:game, score: 75)
    expect(described_class.call(elite, prof)).to be > described_class.call(mid, prof)
  end

  it "returns 0 for an empty profile" do
    expect(described_class.call(create(:game), profile(linked_game_ids: []))).to eq(0)
  end
end
