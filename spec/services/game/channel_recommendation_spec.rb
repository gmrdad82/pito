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

  it "drops channels whose nearest video is below the score threshold" do
    near = create(:channel, title: "On-topic")
    video_for(near, vec(0))
    far = create(:channel, title: "Off-topic")
    video_for(far, vec(1)) # orthogonal → score 0

    expect(described_class.call(game).map(&:channel)).to eq([ near ])
  end

  it "collapses multiple videos of one channel into a single result (best distance)" do
    channel = create(:channel, title: "Multi")
    video_for(channel, vec(0, value: 0.8)) # farther
    video_for(channel, vec(0))             # closest

    results = described_class.call(game)
    expect(results.size).to eq(1)
    expect(results.first.channel).to eq(channel)
    expect(results.first.distance).to be_within(0.0001).of(0.0)
  end

  it "ignores videos without an embedding" do
    channel = create(:channel, title: "Sparse")
    create(:video, channel: channel) # no embedding
    video_for(channel, vec(0))

    expect(described_class.call(game).map(&:channel)).to eq([ channel ])
  end
end
