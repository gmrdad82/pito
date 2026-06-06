# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::EmbedText, type: :service do
  it "builds the multi-field embed text from all populated slots" do
    game = create(:game,
                  title: "Lies of P", summary: "A soulslike.",
                  platforms: [ "PC", "Switch" ], ttb_main_seconds: 7200, score: 85)
    game.genres << Genre.create!(igdb_id: 12, name: "RPG", slug: "rpg")
    game.developer_companies << Company.create!(igdb_id: 1, name: "Round8")
    game.publisher_companies << Company.create!(igdb_id: 2, name: "Neowiz")

    text = described_class.call(game.reload)

    expect(text).to include("Lies of P")
    expect(text).to include("genres: RPG")
    expect(text).to include("developer: Round8")
    expect(text).to include("publisher: Neowiz")
    expect(text).to include("platforms: PC, Switch")
    expect(text).to include("time to beat: main 2h")
    expect(text).to include("rating: 85")
    expect(text).to include("A soulslike.")
  end

  it "skips blank slots (title-only game)" do
    game = create(:game, title: "Bare", summary: nil, platforms: [], score: 0, ttb_main_seconds: nil)
    text = described_class.call(game.reload)
    expect(text).to start_with("Bare")
    expect(text).not_to include("genres:")
    expect(text).not_to include("rating:")
  end
end
