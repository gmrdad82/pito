# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::ChannelProfile do
  let(:channel) { create(:channel) }

  def publish_linking(game, count = 1)
    count.times do
      video = create(:video, :public, channel: channel)
      create(:video_game_link, video: video, game: game)
    end
  end

  def game_with_genre(genre, **attrs)
    game = create(:game, **attrs)
    create(:game_genre, game: game, genre: genre)
    game
  end

  it "weights a genre shared by more videos higher, normalized to 1 (reinforce)" do
    rpg  = create(:genre, name: "RPG")
    plat = create(:genre, name: "Platform")
    publish_linking(game_with_genre(rpg))
    publish_linking(game_with_genre(rpg))
    publish_linking(game_with_genre(plat))

    profile = described_class.call(channel)
    expect(profile.genres[rpg.id]).to be > profile.genres[plat.id]
    expect(profile.genres.values.sum).to be_within(0.001).of(1.0)
  end

  it "amplifies a game's contribution by its published-video count" do
    rpg  = create(:genre, name: "RPG")
    plat = create(:genre, name: "Platform")
    publish_linking(game_with_genre(rpg), 3)
    publish_linking(game_with_genre(plat), 1)

    profile = described_class.call(channel)
    expect(profile.genres[rpg.id]).to be_within(0.001).of(0.75)
    expect(profile.total_videos).to eq(4)
  end

  it "computes a video-weighted score centroid (skipping nils)" do
    publish_linking(create(:game, score: 90), 2)
    publish_linking(create(:game, score: 60), 1)
    expect(described_class.call(channel).score).to be_within(0.1).of(80.0)
  end

  it "is empty for a channel with no published videos" do
    expect(described_class.call(channel)).to be_empty
  end

  it "ignores unpublished (unlisted / private) videos" do
    game  = create(:game)
    video = create(:video, :unlisted, channel: channel)
    create(:video_game_link, video: video, game: game)

    expect(described_class.call(channel)).to be_empty
  end
end
