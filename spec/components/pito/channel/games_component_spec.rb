# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Channel::GamesComponent, type: :component do
  let(:channel) { create(:channel, title: "Grid Channel", handle: "@grid") }

  def link!(game, count: 1, to: channel)
    count.times do
      video = create(:video, channel: to)
      create(:video_game_link, video:, game:)
    end
  end

  def render_grid
    render_inline(described_class.new(channel: channel))
  end

  it "renders one card per linked game" do
    link!(create(:game, title: "Alpha"))
    link!(create(:game, title: "Beta"))
    expect(render_grid.css(".pito-channel-games__card").size).to eq(2)
  end

  it "sorts cards alphabetically by title" do
    zulu  = create(:game, title: "Zulu Quest")
    alpha = create(:game, title: "Alpha Racer")
    link!(zulu)
    link!(alpha)
    ids = render_grid.css(".pito-channel-games__card").map { |c| c["data-game-id"].to_i }
    expect(ids).to eq([ alpha.id, zulu.id ])
  end

  it "renders each game exactly once regardless of how many vids link it" do
    game = create(:game, title: "Multi")
    link!(game, count: 3)
    expect(render_grid.css(".pito-channel-games__card").size).to eq(1)
  end

  it "shows the per-channel vid count, pluralized ('3 vids' / '1 vid')" do
    link!(create(:game, title: "Multi"), count: 3)
    link!(create(:game, title: "Single"), count: 1)
    counts = render_grid.css(".pito-channel-games__count").map(&:text)
    expect(counts).to eq([ "3 vids", "1 vid" ])
  end

  it "counts only THIS channel's vids — links on other channels don't inflate" do
    game  = create(:game, title: "Shared")
    other = create(:channel, handle: "@other")
    link!(game, count: 1)
    link!(game, count: 5, to: other)
    expect(render_grid.css(".pito-channel-games__count").first.text).to eq("1 vid")
  end

  it "renders the #id token with a show-game prefill on each card" do
    game = create(:game, title: "Clickable")
    link!(game)
    id_token = render_grid.css(".pito-channel-games__id").first
    expect(id_token).to be_present
    expect(id_token.text).to include("##{game.id}")
  end

  it "renders no title and no score bar on the cards (owner spec)" do
    link!(create(:game, title: "NoChrome"))
    node = render_grid
    expect(node.css(".pito-channel-games__card .pito-score-bar")).to be_empty
    expect(node.css(".pito-channel-games__card").first.text).not_to include("NoChrome")
  end

  it "renders the intro line through Pito::Copy (count + shimmered title)" do
    link!(create(:game, title: "Solo"))
    intro = render_grid.css(".pito-channel-games__intro").first
    expect(intro).to be_present
    expect(intro.text).to be_present
  end

  it "pluralizes the count-bound noun ('1 game', never '1 games')" do
    link!(create(:game, title: "Solo"))
    intro = render_grid.css(".pito-channel-games__intro").first.text
    expect(intro).not_to match(/\b1 games\b/)
  end

  it "interpolates the count as an integer, never a grouped-count hash" do
    link!(create(:game, title: "One"))
    link!(create(:game, title: "Two"))
    intro = render_grid.css(".pito-channel-games__intro").first.text
    expect(intro).not_to include("=>")
    expect(intro).to include("2") if intro.match?(/\d/)
  end
end
