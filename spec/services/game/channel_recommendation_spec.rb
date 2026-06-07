# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::ChannelRecommendation, type: :service do
  # 1024-dim unit vector with a single hot dimension → predictable cosine.
  def vec(index, value: 1.0)
    Array.new(1024, 0.0).tap { |a| a[index] = value }
  end

  let(:game) { create(:game, title: "Lies of P") }

  before { game.update_column(:summary_embedding, vec(0)) }

  def video_for(channel, embedding)
    create(:video, channel: channel).tap { |v| v.update_column(:summary_embedding, embedding) }
  end

  it "returns [] for a nil game" do
    expect(described_class.call(nil)).to eq([])
  end

  it "returns [] when the game has no embedding" do
    game.update_column(:summary_embedding, nil)
    expect(described_class.call(game)).to eq([])
  end

  it "returns channels of the videos nearest the game (grouped, scored)" do
    near = create(:channel, title: "Soulslike Central")
    video_for(near, vec(0))

    results = described_class.call(game)
    expect(results.map(&:channel)).to eq([ near ])
    expect(results.first.score).to eq(100)
  end

  it "drops channels below the 25 score floor, keeps the rest ranked best-first" do
    near = create(:channel, title: "On-topic")
    video_for(near, vec(0))      # score 100
    far = create(:channel, title: "Off-topic")
    video_for(far, vec(1))       # orthogonal → score 0, below floor

    results = described_class.call(game)
    expect(results.map(&:channel)).to eq([ near ])
    expect(results.first.score).to eq(100)
  end

  it "collapses multiple videos of one channel into a single result (best video wins)" do
    channel = create(:channel, title: "Multi")
    video_for(channel, vec(0, value: 0.8)) # farther
    video_for(channel, vec(0))             # closest → E=100

    results = described_class.call(game)
    expect(results.size).to eq(1)
    expect(results.first.channel).to eq(channel)
    expect(results.first.score).to eq(100)
  end

  describe "GG composition — game→game similarity over linked games (the Dead Space hop)" do
    it "recommends a channel for a NEW game via a similar game it already covers" do
      # Channel covers "Pragmata" (linked to its video). A brand-new "Dead Space"
      # — no videos, no links anywhere — shares Pragmata's genre + developer, so
      # the channel surfaces via GameSimilarity.between(dead_space, pragmata).
      shared_genre = create(:genre)
      shared_dev   = create(:company)

      pragmata = create(:game, title: "Pragmata")
      create(:game_genre, game: pragmata, genre: shared_genre)
      create(:game_developer, game: pragmata, company: shared_dev)

      channel = create(:channel, title: "Manfy")
      vid = create(:video, channel: channel)
      VideoGameLink.create!(video: vid, game: pragmata)

      dead_space = create(:game, title: "Dead Space")
      create(:game_genre, game: dead_space, genre: shared_genre)
      create(:game_developer, game: dead_space, company: shared_dev)

      result = described_class.call(dead_space).find { |r| r.channel == channel }
      expect(result).to be_present
      # G=100 + D=100 → blend 32, above the 25 floor.
      expect(result.score).to eq(32)
    end

    it "scores a channel 100 when it directly covers the target game (explicit link)" do
      g = create(:game, title: "Linked")
      channel = create(:channel)
      vid = create(:video, channel: channel)
      VideoGameLink.create!(video: vid, game: g)

      expect(described_class.call(g).find { |r| r.channel == channel }.score).to eq(100)
    end
  end

  it "ignores videos without an embedding" do
    channel = create(:channel, title: "Sparse")
    create(:video, channel: channel) # no embedding
    video_for(channel, vec(0))

    expect(described_class.call(game).map(&:channel)).to eq([ channel ])
  end

  it "returns ALL matched channels by default (no cap)" do
    4.times do
      ch = create(:channel)
      video_for(ch, vec(0))
    end
    expect(described_class.call(game).size).to eq(4)
  end

  it "honours an explicit limit: keyword when given" do
    3.times do
      ch = create(:channel)
      video_for(ch, vec(0))
    end
    expect(described_class.call(game, limit: 2).size).to eq(2)
  end

  describe "include_all:" do
    it "returns EVERY channel, video-less ones scored 0 and sorted last" do
      near = create(:channel, title: "Has video")
      video_for(near, vec(0)) # score 100
      empty1 = create(:channel, title: "No videos A")
      empty2 = create(:channel, title: "No videos B")

      results = described_class.call(game, include_all: true)
      expect(results.map(&:channel)).to contain_exactly(near, empty1, empty2)
      expect(results.first.channel).to eq(near)
      expect(results.first.score).to eq(100)
      expect(results.select { |r| r.score.zero? }.map(&:channel)).to contain_exactly(empty1, empty2)
    end

    it "does not apply the score floor when include_all is true" do
      far = create(:channel, title: "Off-topic")
      video_for(far, vec(1)) # score 0, below the 25 floor
      results = described_class.call(game, include_all: true)
      expect(results.map(&:channel)).to include(far)
    end

    it "still returns [] when there are no channels at all" do
      expect(described_class.call(game, include_all: true)).to eq([])
    end
  end

  describe "explicit video→game links" do
    it "scores a channel 100 when one of its videos is linked to the game (beats weak embedding)" do
      ch = create(:channel, title: "Linked")
      v  = video_for(ch, vec(1)) # orthogonal → embedding score 0
      VideoGameLink.create!(video: v, game: game)

      result = described_class.call(game).find { |r| r.channel == ch }
      expect(result).to be_present
      expect(result.score).to eq(100)
    end

    it "surfaces a linked channel even when the game has no embedding" do
      game.update_column(:summary_embedding, nil)
      ch = create(:channel, title: "Linked-only")
      v  = create(:video, channel: ch) # no embedding
      VideoGameLink.create!(video: v, game: game)

      expect(described_class.call(game).map(&:channel)).to eq([ ch ])
    end
  end
end
