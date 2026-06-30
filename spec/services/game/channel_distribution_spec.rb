# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::ChannelDistribution do
  let(:game) { create(:game) }
  let(:ch_a) { create(:channel) }
  let(:ch_b) { create(:channel) }

  def cover(channel, views:)
    v = create(:video, channel: channel)
    create(:video_game_link, video: v, game: game)
    Pito::Stats.set(v, :views, views)
    v
  end

  it "returns nodata when no channel covers the game" do
    result = described_class.call(game: game, channels: [ ch_a, ch_b ])
    expect(result[:nodata]).to be true
    expect(result[:shares]).to be_empty
  end

  it "distributes by the videos+views blend, summing to 100, order preserved" do
    cover(ch_a, views: 1_000)
    cover(ch_b, views: 1_000)
    result = described_class.call(game: game, channels: [ ch_a, ch_b ])
    expect(result[:nodata]).to be false
    expect(result[:shares].sum(&:share)).to eq(100)
    expect(result[:shares].map(&:channel)).to eq([ ch_a, ch_b ])
  end

  it "gives a channel with no linked videos a 0 share" do
    cover(ch_a, views: 500)
    result = described_class.call(game: game, channels: [ ch_a, ch_b ])
    expect(result[:shares].find { |s| s.channel == ch_a }.share).to eq(100)
    expect(result[:shares].find { |s| s.channel == ch_b }.share).to eq(0)
  end

  it "floors a covering-but-dominated channel to at least 1 (still summing to 100)" do
    cover(ch_a, views: 1_000_000)
    cover(ch_b, views: 1)
    result = described_class.call(game: game, channels: [ ch_a, ch_b ])
    expect(result[:shares].find { |s| s.channel == ch_b }.share).to be >= 1
    expect(result[:shares].sum(&:share)).to eq(100)
  end

  it "preserves the caller's channel order" do
    cover(ch_a, views: 100)
    cover(ch_b, views: 100)
    result = described_class.call(game: game, channels: [ ch_b, ch_a ])
    expect(result[:shares].map(&:channel)).to eq([ ch_b, ch_a ])
  end

  it "factors injected watch-hours into the blend" do
    va = cover(ch_a, views: 1)
    vb = cover(ch_b, views: 1)
    # Equal videos + views; ch_a has all the watch-hours → it must lead.
    result = described_class.call(
      game: game, channels: [ ch_a, ch_b ], watch_hours: { va.id => 1_000.0, vb.id => 0.0 }
    )
    a = result[:shares].find { |s| s.channel == ch_a }.share
    b = result[:shares].find { |s| s.channel == ch_b }.share
    expect(a).to be > b
    expect(result[:shares].sum(&:share)).to eq(100)
  end

  it "exposes raw videos/views per channel" do
    cover(ch_a, views: 250)
    result = described_class.call(game: game, channels: [ ch_a ])
    raw = result[:shares].first.raw
    expect(raw[:videos]).to eq(1)
    expect(raw[:views]).to eq(250)
  end
end
