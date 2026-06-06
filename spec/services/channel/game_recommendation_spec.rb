# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::GameRecommendation, type: :service do
  def vec(index, value: 1.0)
    Array.new(1024, 0.0).tap { |a| a[index] = value }
  end

  let(:channel) { create(:channel, title: "Soulslike Central") }

  # The channel's probe video sits at vec(0); games near vec(0) should surface.
  def probe_video(embedding, views: 100)
    create(:video, channel: channel).tap do |v|
      v.update_column(:summary_embedding, embedding)
      Pito::Stats.set(v, :views, views)
    end
  end

  it "returns [] for a nil channel" do
    expect(described_class.call(nil)).to eq([])
  end

  it "returns [] when the channel has no embedded videos" do
    create(:video, channel: channel) # no embedding
    expect(described_class.call(channel)).to eq([])
  end

  it "returns games nearest the channel's videos (scored)" do
    probe_video(vec(0))
    game = create(:game, title: "Lies of P")
    game.update_column(:summary_embedding, vec(0))

    results = described_class.call(channel)
    expect(results.map(&:game)).to eq([ game ])
    expect(results.first.score).to eq(100)
  end

  it "drops games below the score threshold" do
    probe_video(vec(0))
    near = create(:game, title: "On-topic")
    near.update_column(:summary_embedding, vec(0))
    far = create(:game, title: "Off-topic")
    far.update_column(:summary_embedding, vec(1)) # orthogonal → score 0

    expect(described_class.call(channel).map(&:game)).to eq([ near ])
  end

  it "merges hits from multiple probe videos keeping the best distance" do
    probe_video(vec(0, value: 0.8), views: 200)
    probe_video(vec(0), views: 50)
    game = create(:game, title: "Lies of P")
    game.update_column(:summary_embedding, vec(0))

    results = described_class.call(channel)
    expect(results.size).to eq(1)
    expect(results.first.distance).to be_within(0.0001).of(0.0)
  end

  it "skips games without an embedding" do
    probe_video(vec(0))
    create(:game, title: "Unindexed") # no embedding
    create(:game, title: "Indexed").update_column(:summary_embedding, vec(0))

    expect(described_class.call(channel).map { |r| r.game.title }).to eq([ "Indexed" ])
  end
end
