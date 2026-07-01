# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::PlatformReleaseGroups do
  let(:game) { create(:game) }

  def add(token, **attrs)
    create(:game_platform_release, { game: game, platform_token: token, release_year: 2026, release_month: nil, release_day: nil }.merge(attrs))
  end

  it "returns [] when the game has no platform releases" do
    expect(described_class.call(game)).to eq([])
  end

  it "collapses platforms that share a date into ONE group with all tokens" do
    add("ps",    release_month: 7, release_day: 31)
    add("steam", release_month: 7, release_day: 31)
    result = described_class.call(game)
    expect(result.length).to eq(1)
    expect(result.first[:tokens]).to eq(%w[ps steam])
  end

  it "splits differing dates into separate groups, earliest first" do
    add("switch", release_quarter: 3)                 # Q3 → 2026-07-01
    add("ps",     release_month: 7, release_day: 31)  # 2026-07-31
    result = described_class.call(game)
    expect(result.map { |g| g[:tokens] }).to eq([ %w[switch], %w[ps] ])
    expect(result.first[:label]).to include("Q3")
    expect(result.last[:label]).to  include("31")
  end

  it "orders tokens within a group by PlatformTokens::ORDER (ps→switch→xbox→steam)" do
    add("steam", release_month: 7, release_day: 31)
    add("xbox",  release_month: 7, release_day: 31)
    add("ps",    release_month: 7, release_day: 31)
    expect(described_class.call(game).first[:tokens]).to eq(%w[ps xbox steam])
  end
end
