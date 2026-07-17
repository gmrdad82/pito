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

  it "includes alternative_names joined by space in the alt_names slot" do
    game = create(:game, title: "Lies of P", alternative_names: [ "소울라이크", "라이즈 오브 P" ])
    text = described_class.call(game)
    expect(text).to include("소울라이크")
    expect(text).to include("라이즈 오브 P")
  end

  it "skips the alt_names slot when alternative_names is blank" do
    game = create(:game, title: "Solo", alternative_names: [])
    text = described_class.call(game)
    # Only the title should precede the first separator (no double em-dash)
    expect(text).to start_with("Solo")
  end

  it "includes extras and completionist TTB hours when populated" do
    game = create(:game, title: "Elden Ring",
                         ttb_main_seconds:         72 * 3600,   # 72h
                         ttb_extras_seconds:        120 * 3600,  # 120h
                         ttb_completionist_seconds: 200 * 3600)  # 200h
    text = described_class.call(game)
    expect(text).to include("main 72h")
    expect(text).to include("extras 120h")
    expect(text).to include("completionist 200h")
  end

  it "omits extras and completionist from TTB phrase when they are zero" do
    game = create(:game, title: "Short Game",
                         ttb_main_seconds:         3 * 3600,
                         ttb_extras_seconds:        0,
                         ttb_completionist_seconds: nil)
    text = described_class.call(game)
    expect(text).to include("main 3h")
    expect(text).not_to include("extras")
    expect(text).not_to include("completionist")
  end

  it "includes a labelled traits section (scales then tags, declaration order) for a traited game" do
    game = create(:game, :with_traits, title: "Traited Game")
    text = described_class.call(game.reload)
    expect(text).to include("traits: difficulty brutal, story catching, skill based, worth it, action")
  end

  it "skips the traits slot entirely for an untraited game — embed text stays byte-identical to before traits existed, so untraited games never mass re-embed on deploy" do
    game = create(:game, title: "Untraited",
                         summary: nil, platforms: [], score: 0, ttb_main_seconds: nil)
    text = described_class.call(game.reload)
    expect(text).to eq("Untraited")
    expect(text).not_to include("traits:")
  end
end
