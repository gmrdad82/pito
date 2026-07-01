# frozen_string_literal: true

require "rails_helper"

RSpec.describe GamePlatformRelease do
  it "is valid with a game, a known token, and consistent components" do
    expect(build(:game_platform_release)).to be_valid
  end

  describe "associations" do
    it "belongs to a game" do
      expect(build(:game_platform_release, game: nil)).not_to be_valid
    end

    it "is destroyed with its game" do
      game = create(:game)
      create(:game_platform_release, game: game)
      expect { game.destroy }.to change(described_class, :count).by(-1)
    end

    it "is reachable via game.platform_releases" do
      game = create(:game)
      rel  = create(:game_platform_release, game: game, platform_token: "switch")
      expect(game.platform_releases).to include(rel)
    end
  end

  describe "platform_token" do
    it "requires a token" do
      expect(build(:game_platform_release, platform_token: nil)).not_to be_valid
    end

    %w[ps switch steam].each do |token|
      it "accepts the #{token} token" do
        expect(build(:game_platform_release, platform_token: token)).to be_valid
      end
    end

    it "rejects an unknown token" do
      expect(build(:game_platform_release, platform_token: "wii")).not_to be_valid
    end

    it "is unique per (game, platform_token)" do
      game = create(:game)
      create(:game_platform_release, game: game, platform_token: "ps")
      dup = build(:game_platform_release, game: game, platform_token: "ps")
      expect(dup).not_to be_valid
    end

    it "allows the same token on different games" do
      create(:game_platform_release, game: create(:game), platform_token: "ps")
      other = build(:game_platform_release, game: create(:game), platform_token: "ps")
      expect(other).to be_valid
    end
  end

  describe "component consistency (mirrors Game)" do
    it "rejects quarter + month together" do
      rel = build(:game_platform_release, release_month: nil, release_day: nil, release_quarter: 3)
      rel.release_month = 7
      expect(rel).not_to be_valid
    end

    it "rejects a day without a month" do
      expect(build(:game_platform_release, release_month: nil, release_day: 15)).not_to be_valid
    end

    it "rejects an out-of-range quarter" do
      expect(build(:game_platform_release, release_month: nil, release_day: nil, release_quarter: 5)).not_to be_valid
    end

    it "rejects an out-of-range month" do
      expect(build(:game_platform_release, release_month: 13, release_day: nil)).not_to be_valid
    end

    it "rejects an impossible date" do
      expect(build(:game_platform_release, release_year: 2026, release_month: 2, release_day: 30)).not_to be_valid
    end
  end

  describe "#recompute_release_date (derived lower-bound)" do
    it "derives the exact day when y/m/d are present" do
      rel = create(:game_platform_release, release_year: 2026, release_month: 7, release_day: 31)
      expect(rel.release_date).to eq(Date.new(2026, 7, 31))
    end

    it "derives the quarter start for a quarter-precision date" do
      rel = create(:game_platform_release, release_year: 2026, release_quarter: 3, release_month: nil, release_day: nil)
      expect(rel.release_date).to eq(Date.new(2026, 7, 1))
    end

    it "derives Jan 1 for a year-only date" do
      rel = create(:game_platform_release, release_year: 2026, release_month: nil, release_day: nil)
      expect(rel.release_date).to eq(Date.new(2026, 1, 1))
    end
  end
end
