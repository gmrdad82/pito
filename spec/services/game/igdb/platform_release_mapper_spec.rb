# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Igdb::PlatformReleaseMapper do
  def row(platform, category:, y: nil, m: nil, d: nil)
    { "platform" => { "name" => platform }, "category" => category, "y" => y, "m" => m, "d" => d }
  end

  it "maps each platform to its token + component hash" do
    json = { "release_dates" => [
      row("PlayStation 5",  category: 0, y: 2026, m: 7, d: 31),
      row("Xbox Series X|S", category: 5, y: 2026)  # Q3
    ] }
    result = described_class.call(json)
    expect(result["ps"]).to eq(year: 2026, month: 7, day: 31)
    expect(result["xbox"]).to eq(year: 2026, quarter: 3)
  end

  it "groups multiple IGDB platforms into one token (PS4 + PS5 → ps)" do
    json = { "release_dates" => [
      row("PlayStation 4", category: 0, y: 2026, m: 7, d: 31),
      row("PlayStation 5", category: 0, y: 2026, m: 7, d: 31)
    ] }
    expect(described_class.call(json).keys).to eq([ "ps" ])
  end

  it "keeps the MOST PRECISE row per token" do
    json = { "release_dates" => [
      row("PlayStation 5", category: 2, y: 2026),               # year only
      row("PlayStation 4", category: 0, y: 2026, m: 7, d: 31)   # day — wins
    ] }
    expect(described_class.call(json)["ps"]).to eq(year: 2026, month: 7, day: 31)
  end

  it "drops unrecognised platforms (Stadia)" do
    json = { "release_dates" => [ row("Google Stadia", category: 0, y: 2026, m: 7, d: 31) ] }
    expect(described_class.call(json)).to eq({})
  end

  it "drops TBD (category 7) rows" do
    json = { "release_dates" => [ { "platform" => { "name" => "PlayStation 5" }, "category" => 7 } ] }
    expect(described_class.call(json)).to eq({})
  end

  it "ignores rows with a blank platform name" do
    json = { "release_dates" => [ { "platform" => nil, "category" => 0, "y" => 2026, "m" => 7, "d" => 31 } ] }
    expect(described_class.call(json)).to eq({})
  end

  it "returns {} for missing / nil release_dates" do
    expect(described_class.call({})).to eq({})
    expect(described_class.call(nil)).to eq({})
  end
end
