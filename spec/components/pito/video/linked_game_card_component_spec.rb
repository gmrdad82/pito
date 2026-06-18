# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Video::LinkedGameCardComponent do
  let(:game) do
    create(
      :game,
      title:               "Lies of P",
      themes:              [ "Horror", "Action" ],
      player_perspectives: [ "Third person" ],
      release_year:        2023, release_month: 9, release_day: 19,
      release_date:        Date.new(2023, 9, 19)
    )
  end

  it "renders the title row" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Title")
    expect(node.text).to include("Lies of P")
  end

  it "renders genre names" do
    genre = create(:genre, name: "Soulslike")
    create(:game_genre, game: game, genre: genre)
    game.reload

    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Soulslike")
  end

  it "renders the perspective" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Third person")
  end

  it "renders the theme(s)" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Horror")
  end

  it "renders publisher company names" do
    company = create(:company, name: "Neowiz")
    create(:game_publisher, game: game, company: company)
    game.reload

    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Neowiz")
  end

  it "renders developer company names" do
    company = create(:company, name: "Round8 Studio")
    create(:game_developer, game: game, company: company)
    game.reload

    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Round8 Studio")
  end

  it "renders the release label" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("2023")
  end

  it "renders total footage as whole hours (TTB pillar value)" do
    create(:footage, game: game, duration_seconds: 3600)
    create(:footage, game: game, duration_seconds: 3600)
    game.reload

    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("2h")
  end

  it "renders total footage as an em-dash when there is none" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("—")
  end

  it "carries NO score/TTB bars (slim card)" do
    node = render_inline(described_class.new(game: game))
    expect(node.css(".pito-game-detail__score")).to be_empty
    expect(node.css(".pito-game-detail__ttb")).to be_empty
  end

  it "renders the cover via an <img> when cover art is attached" do
    game.cover_art.attach(
      io: StringIO.new("fake-bytes"), filename: "cover.png", content_type: "image/png"
    )
    node = render_inline(described_class.new(game: game))
    expect(node.css(".pito-video-linked-game-card__cover img")).not_to be_empty
  end

  it "renders the no-cover placeholder when nothing is attached" do
    node = render_inline(described_class.new(game: game))
    expect(node.css(".pito-video-linked-game-card__cover img")).to be_empty
    expect(node.text).to include(I18n.t("pito.game.detail.no_cover"))
  end
end
