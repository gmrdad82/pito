# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::ChannelsComponent do
  let(:game) { create(:game, title: "Shadow of the Colossus") }

  ChannelResult2 = Struct.new(:channel, :score, keyword_init: true) unless defined?(ChannelResult2)

  def build_channel(handle:)
    Channel.new(handle: handle, title: "T", youtube_channel_id: "UC#{SecureRandom.hex(4)}")
  end

  def render_component(shares: nil)
    render_inline(described_class.new(
      game: game, intro: "The matches.",
      distribution_caption: "dist cap", recommendation_caption: "reco cap", shares: shares
    ))
  end

  before { allow(Pito::Recommendations).to receive(:channels_for).and_return([]) }

  describe "intro line" do
    it "renders the passed-in (stable) intro" do
      expect(render_component.at_css(".pito-game-enhanced-message__intro").text).to include("The matches.")
    end
  end

  describe "with channel results" do
    let(:ch1) { build_channel(handle: "gamegrumps") }
    let(:ch2) { build_channel(handle: "markiplier") }
    let(:results) do
      [ ChannelResult2.new(channel: ch1, score: 78), ChannelResult2.new(channel: ch2, score: 65) ]
    end

    before do
      allow(Pito::Recommendations).to receive(:channels_for)
        .with(game, include_all: true).and_return(results)
    end

    it "renders both columns (distribution + recommendation)" do
      node = render_component
      expect(node.css(".pito-game-channels__col--dist")).not_to be_empty
      expect(node.css(".pito-game-channels__col--reco")).not_to be_empty
    end

    it "renders col 1 as the NoData canvas when no shares yet (pending)" do
      node = render_component
      expect(node.css(".pito-game-channels__col--dist .pito-metric--nodata")).not_to be_empty
      expect(node.css(".pito-game-channels__col--dist .pito-metric--bar")).to be_empty
    end

    it "renders col 1 as the offset bars when shares are present (ready)" do
      shares = [
        Game::ChannelDistribution::Share.new(channel: ch1, share: 60, raw: {}),
        Game::ChannelDistribution::Share.new(channel: ch2, share: 40, raw: {})
      ]
      node = render_component(shares: shares)
      expect(node.css(".pito-game-channels__col--dist .pito-metric--bar")).not_to be_empty
      expect(node.css(".pito-game-channels__col--dist .pito-metric--nodata")).to be_empty
    end

    it "renders an avatar row + score bar per channel in col 2" do
      node = render_component
      expect(node.css(".pito-game-channels__reco-row").length).to eq(2)
      expect(node.css(".pito-game-channels__reco-score .pito-score-bar").length).to eq(2)
    end

    it "caps col 2 at 5 rows" do
      many = (1..7).map { |i| ChannelResult2.new(channel: build_channel(handle: "c#{i}"), score: 50) }
      allow(Pito::Recommendations).to receive(:channels_for).with(game, include_all: true).and_return(many)
      expect(render_component.css(".pito-game-channels__reco-row").length).to eq(5)
    end
  end

  describe "when there are no channel results" do
    it "renders neither column, just the intro" do
      node = render_component
      expect(node.css(".pito-game-channels")).to be_empty
      expect(node.at_css(".pito-game-enhanced-message__intro")).to be_present
    end

    it "does not raise" do
      expect { render_component }.not_to raise_error
    end
  end
end
