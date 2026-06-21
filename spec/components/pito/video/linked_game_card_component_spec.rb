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

  describe "root layout" do
    it "carries flex-col (mobile-first single-column default)" do
      node = render_inline(described_class.new(game: game))
      root = node.css(".pito-video-linked-game-card").first
      expect(root["class"]).to include("flex-col")
    end

    it "carries md:flex-row (desktop two-column at the md: breakpoint)" do
      node = render_inline(described_class.new(game: game))
      root = node.css(".pito-video-linked-game-card").first
      expect(root["class"]).to include("md:flex-row")
    end

    it "carries md:items-start (aligns columns at the top on desktop)" do
      node = render_inline(described_class.new(game: game))
      root = node.css(".pito-video-linked-game-card").first
      expect(root["class"]).to include("md:items-start")
    end
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

  it "renders total footage via the FootageHours formatter" do
    game.update!(footage_hours: 12.5)

    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("12.5h")
  end

  it "strips the decimal for a whole-hour total" do
    game.update!(footage_hours: 2)

    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("2h")
  end

  it "renders total footage as an em-dash when there is none" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("—")
  end

  it "labels the footage row 'Footage' (capitalised), not the lowercase TTB label" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Footage")
    expect(node.text).not_to match(/\bfootage\b/)
  end

  it "renders the Price row with the euro value when the game is priced" do
    game.update!(price: BigDecimal("59.99"))
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Price")
    expect(node.text).to include("€59.99")
  end

  it "always renders the Price row with an em dash when unpriced" do
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Price")
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

  it "renders the ID row as a shimmer token with the #<id> value" do
    node = render_inline(described_class.new(game: game))
    shimmer = node.css("span.pito-token-shimmer")
    expect(shimmer).not_to be_empty
    expect(shimmer.first.text).to include("##{game.id}")
  end

  it "renders the ID row immediately after the Title row" do
    node = render_inline(described_class.new(game: game))
    # Each KV row renders as two sibling spans in the grid (key + value).
    # Find only the key-label spans (dim class) to check label ordering.
    key_labels = node.css(".pito-video-linked-game-card__fields span.text-fg-dim.whitespace-nowrap").map(&:text)
    title_idx = key_labels.index { |t| t.include?("Title") }
    id_idx    = key_labels.index("ID")
    expect(title_idx).not_to be_nil
    expect(id_idx).not_to be_nil
    expect(id_idx).to eq(title_idx + 1)
  end
end
