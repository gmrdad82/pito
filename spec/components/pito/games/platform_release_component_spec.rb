# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Games::PlatformReleaseComponent, type: :component do
  include ActiveSupport::Testing::TimeHelpers

  # Day-precision labels render through the house date (current year drops
  # the year) — pin "today" so 2026 reads as the current year deterministically.
  around { |example| travel_to(Time.zone.local(2026, 7, 19)) { example.run } }

  let(:game) { create(:game, release_year: 2026, release_month: 7, release_day: 31) }

  def add(token, **attrs)
    create(:game_platform_release, { game: game, platform_token: token, release_year: 2026, release_month: nil, release_day: nil }.merge(attrs))
  end

  def render_it
    render_inline(described_class.new(game: game))
  end

  context "when the game has no per-platform releases" do
    it "falls back to the single derived release label with no logos" do
      node = render_it
      expect(node.text).to include("31 Jul")
      expect(node.css("img.pito-platform-icon")).to be_empty
    end
  end

  context "when platforms share one date" do
    before do
      add("ps",    release_month: 7, release_day: 31)
      add("steam", release_month: 7, release_day: 31)
    end

    it "renders a single row with both logos" do
      node = render_it
      rows = node.css(".pito-platform-release__row")
      expect(rows.length).to eq(1)
      srcs = rows.first.css("img.pito-platform-icon").map { |i| i["src"] }
      expect(srcs).to eq([ "/platforms/playstation.svg", "/platforms/steam.svg" ])
      expect(rows.first.text).to include("31 Jul")
    end
  end

  context "when platforms have different dates" do
    before do
      add("switch", release_quarter: 3)                 # Q3 2026
      add("ps",     release_month: 7, release_day: 31)  # 31 Jul
    end

    it "renders one row per date, earliest first, each with its own logo" do
      rows = render_it.css(".pito-platform-release__row")
      expect(rows.length).to eq(2)
      expect(rows[0].text).to include("Q3 2026")
      expect(rows[0].css("img").map { |i| i["src"] }).to eq([ "/platforms/switch.svg" ])
      expect(rows[1].text).to include("31 Jul")
      expect(rows[1].css("img").map { |i| i["src"] }).to eq([ "/platforms/playstation.svg" ])
    end
  end
end
