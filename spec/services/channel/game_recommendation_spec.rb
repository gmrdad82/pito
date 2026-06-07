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

  it "uses the highest-views video as probe so it drives recommendations" do
    # High-views video shares direction with target_game; low-views video is orthogonal.
    high = create(:video, channel: channel)
    high.update_column(:summary_embedding, vec(0))
    Pito::Stats.set(high, :views, 10_000)

    low = create(:video, channel: channel)
    low.update_column(:summary_embedding, vec(1)) # orthogonal — would miss the target
    Pito::Stats.set(low, :views, 10)

    target_game = create(:game, title: "High-views target")
    target_game.update_column(:summary_embedding, vec(0))

    results = described_class.call(channel)
    expect(results.map(&:game)).to include(target_game)
    expect(results.first.score).to eq(100)
  end

  it "honours the limit: keyword" do
    probe_video(vec(0))
    3.times { |i| create(:game).update_column(:summary_embedding, vec(0, value: 0.5 + i * 0.1)) }
    expect(described_class.call(channel, limit: 2).size).to eq(2)
  end

  it "includes results whose score equals exactly THRESHOLD_SCORE (boundary: in)" do
    threshold = described_class::THRESHOLD_SCORE
    # distance that maps to exactly the threshold score
    # score = ((1 - distance) * 100).round => distance = 1 - threshold/100.0
    exact_distance = 1.0 - threshold / 100.0

    probe_video(vec(0))
    game = create(:game, title: "On-threshold")
    game.update_column(:summary_embedding, vec(0))

    allow_any_instance_of(described_class).to receive(:nearest_games) do
      [ game ].tap { game.define_singleton_method(:neighbor_distance) { exact_distance } }
    end

    results = described_class.call(channel)
    expect(results.map(&:game)).to include(game)
  end
end
