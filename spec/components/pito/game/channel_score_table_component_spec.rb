# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::ChannelScoreTableComponent do
  Reco = Struct.new(:channel, :score, keyword_init: true) unless defined?(Reco)

  def chan(handle:)
    Channel.new(handle: handle, youtube_channel_id: "UC#{SecureRandom.hex(4)}")
  end

  it "renders one avatar + score-bar row per result" do
    results = [ Reco.new(channel: chan(handle: "a"), score: 80), Reco.new(channel: chan(handle: "b"), score: 60) ]
    node = render_inline(described_class.new(results: results, caption: "cap"))
    expect(node.css(".pito-game-channels__reco-row").length).to eq(2)
    expect(node.css(".pito-game-channels__reco-score .pito-score-bar").length).to eq(2)
  end

  it "caps at 5 rows" do
    results = (1..8).map { |i| Reco.new(channel: chan(handle: "c#{i}"), score: 50) }
    node = render_inline(described_class.new(results: results, caption: "cap"))
    expect(node.css(".pito-game-channels__reco-row").length).to eq(5)
  end

  it "falls back to a placeholder when a channel has no avatar" do
    node = render_inline(described_class.new(results: [ Reco.new(channel: chan(handle: "a"), score: 50) ], caption: "cap"))
    expect(node.css(".pito-game-channels__reco-avatar--placeholder")).not_to be_empty
  end

  it "renders the caption" do
    expect(render_inline(described_class.new(results: [], caption: "reco cap")).text).to include("reco cap")
  end
end
