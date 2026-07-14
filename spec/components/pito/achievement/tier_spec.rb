# frozen_string_literal: true

require "rails_helper"

# G127: per-scope ladders + positional stone materials + channel-subs awards.
RSpec.describe Pito::Achievement::Tier do
  T = described_class

  describe ".series_for" do
    it "channel subs = 15 stone steps to 50K plus the three award thresholds" do
      expect(T.series_for(scope: "Channel", metric: "subs"))
        .to eq([ 1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 2_000, 5_000,
                 10_000, 20_000, 50_000, 100_000, 1_000_000, 10_000_000 ])
    end

    it "keeps the 1-2-5 rhythm to each ceiling (vid views -> 1M)" do
      s = T.series_for(scope: "Video", metric: "views")
      expect(s.first(6)).to eq([ 1, 2, 5, 10, 20, 50 ])
      expect(s.last).to eq(1_000_000)
    end

    { %w[Video views] => 1_000_000, %w[Video watched_hours] => 100_000,
      %w[Video likes] => 20_000, %w[Video comments] => 5_000,
      %w[Video subs_gained] => 5_000, %w[Game views] => 10_000_000,
      %w[Game watched_hours] => 500_000, %w[Game likes] => 200_000,
      %w[Game comments] => 20_000, %w[Game subs_gained] => 10_000,
      %w[Channel views] => 50_000_000, %w[Channel watched_hours] => 2_000_000,
      %w[Channel likes] => 500_000, %w[Channel comments] => 50_000 }.each do |(scope, metric), ceiling|
      it "#{scope} #{metric} tops out at #{ceiling} (monetized-channel scale)" do
        expect(T.series_for(scope:, metric:).last).to eq(ceiling)
      end
    end

    it "raises on an unknown pair" do
      expect { T.series_for(scope: "Channel", metric: "subs_gained") }.to raise_error(KeyError)
    end
  end

  describe ".material_for" do
    it "the first step is always wood" do
      expect(T.material_for(scope: "Video", metric: "views", threshold: 1)).to eq("wood")
    end

    it "every stone ladder's pinnacle is opal" do
      expect(T.material_for(scope: "Video", metric: "comments", threshold: 5_000)).to eq("opal")
      expect(T.material_for(scope: "Channel", metric: "views", threshold: 50_000_000)).to eq("opal")
      expect(T.material_for(scope: "Channel", metric: "subs", threshold: 50_000)).to eq("opal")
    end

    it "the channel-subs awards are the metals (YouTube scale)" do
      expect(T.material_for(scope: "Channel", metric: "subs", threshold: 100_000)).to eq("silver")
      expect(T.material_for(scope: "Channel", metric: "subs", threshold: 1_000_000)).to eq("gold")
      expect(T.material_for(scope: "Channel", metric: "subs", threshold: 10_000_000)).to eq("diamond")
    end

    it "no metal ever appears outside the channel-subs award steps" do
      %w[Video Game].each do |scope|
        T.ceilings.fetch(scope).each_key do |metric|
          mats = T.series_for(scope:, metric:).map { |t| T.material_for(scope:, metric:, threshold: t) }
          expect(mats).to all(be_in(T::STONES))
        end
      end
    end

    it "progresses through the stones in order along a ladder" do
      s    = T.series_for(scope: "Game", metric: "views")
      mats = s.map { |t| T.material_for(scope: "Game", metric: "views", threshold: t) }
      expect(mats.uniq).to eq(T::STONES) # all eight, in ladder order
    end

    it "falls back to the nearest lower step for an off-ladder legacy threshold" do
      expect { T.material_for(scope: "Video", metric: "views", threshold: 3) }.not_to raise_error
      expect(T.material_for(scope: "Video", metric: "views", threshold: 3))
        .to eq(T.material_for(scope: "Video", metric: "views", threshold: 2))
    end
  end

  describe ".award_track?" do
    it "is true only for channel subs" do
      expect(T.award_track?("Channel", "subs")).to be(true)
      expect(T.award_track?("Channel", "views")).to be(false)
      expect(T.award_track?("Video", "subs_gained")).to be(false)
    end
  end
end
