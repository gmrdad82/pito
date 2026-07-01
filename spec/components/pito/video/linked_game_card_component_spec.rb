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

  # C2 (0.8.1): the linked-game card drops Publisher + Developer — noise on a vid's
  # slim game card. (They still render on the full `show game` card.)
  it "does NOT render publisher company names" do
    company = create(:company, name: "Neowiz")
    create(:game_publisher, game: game, company: company)
    game.reload

    node = render_inline(described_class.new(game: game))
    expect(node.text).not_to include("Neowiz")
    expect(node.text).not_to include("Publisher")
  end

  it "does NOT render developer company names" do
    company = create(:company, name: "Round8 Studio")
    create(:game_developer, game: game, company: company)
    game.reload

    node = render_inline(described_class.new(game: game))
    expect(node.text).not_to include("Round8 Studio")
    expect(node.text).not_to include("Developer")
  end

  it "renders the Last sync at row (igdb_synced_at)" do
    game.update!(igdb_synced_at: Time.zone.local(2026, 6, 26, 14, 30))
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Last sync at").and include("26-06-2026 14:30")
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

  it "renders the Price row with coin glyphs + the number when priced" do
    game.update!(price: BigDecimal("59.99"))
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Price")
    expect(node.text).to include("59.99")
    expect(node.css("img.pito-coin").size).to eq(3)
    expect(node.to_html).to include("/coin/coin.gif")
  end

  it "renders the FREE star for an explicit 0 price" do
    game.update!(price: 0)
    node = render_inline(described_class.new(game: game))
    expect(node.text).to include("Price")
    expect(node.to_html).to include("/coin/star.gif")
  end

  it "always renders the Price row with an em-dash when unpriced (nil)" do
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

  it "renders the click-to-sync image placeholder when nothing is attached (item 22)" do
    node = render_inline(described_class.new(game: game))
    expect(node.css(".pito-video-linked-game-card__cover img")).to be_empty
    fallback = node.at_css(".pito-video-linked-game-card__cover .pito-image-fallback")
    expect(fallback).to be_present
    expect(fallback["data-pito--chat-prefill-text-value"]).to eq("sync game ##{game.id}")
  end

  # ── Big cover Ken-Burns pan (L5) ────────────────────────────────────────────
  # The linked-game card mirrors show-game's detail cover: the <img> lives inside
  # the bounded .pito-video-linked-game-card__cover box (374×210, shared CSS) and
  # carries the Ken-Burns pan hook (.pito-cover-pan, the same Z29 mechanism).
  describe "big cover Ken-Burns pan" do
    context "when cover art is attached" do
      before do
        allow_any_instance_of(described_class).to receive(:cover_attached?).and_return(true)
        allow_any_instance_of(described_class).to receive(:cover_url).and_return("/covers/test.jpg")
      end

      it "renders the cover inside the .pito-video-linked-game-card__cover box" do
        node  = render_inline(described_class.new(game: game))
        cover = node.css(".pito-video-linked-game-card__cover").first
        expect(cover).not_to be_nil
        expect(cover.css("img").first).not_to be_nil
      end

      it "the cover <img> carries the pito-cover-pan animation hook" do
        node = render_inline(described_class.new(game: game))
        img  = node.css(".pito-video-linked-game-card__cover img").first
        expect(img).not_to be_nil
        expect(img["class"]).to include("pito-cover-pan")
      end
    end

    context "when no cover art is attached (placeholder)" do
      it "renders no pito-cover-pan element" do
        node = render_inline(described_class.new(game: game))
        expect(node.css(".pito-cover-pan")).to be_empty
      end
    end
  end

  # ── Mobile-only column divider (L6) ─────────────────────────────────────────
  # When the layout stacks on mobile (<768px) a hairline sits between the cover
  # and the kv-table; it is hidden at md: and up (the two-column desktop layout
  # needs no divider).
  describe "mobile-only column divider" do
    it "renders a hairline divider between the columns" do
      node    = render_inline(described_class.new(game: game))
      divider = node.css(".pito-detail-col-divider").first
      expect(divider).not_to be_nil
      expect(divider["class"]).to include("h-px")
    end

    it "is hidden on desktop (carries md:hidden)" do
      node    = render_inline(described_class.new(game: game))
      divider = node.css(".pito-detail-col-divider").first
      expect(divider["class"]).to include("md:hidden")
    end
  end

  it "renders the ID row as a yellow kbd shimmer token with the #<id> value (clickable)" do
    node = render_inline(described_class.new(game: game))
    shimmer = node.css("span.pito-action-shimmer")
    expect(shimmer).not_to be_empty
    expect(shimmer.first.text).to include("##{game.id}")
  end

  it "wires the #id token to prefill + auto-submit `show game #id` (J20)" do
    node = render_inline(described_class.new(game: game))
    span = node.css("span.pito-action-shimmer").find { |s| s.text == "##{game.id}" }
    expect(span).to be_present
    expect(span["data-controller"]).to eq("pito--chat-prefill")
    expect(span["data-action"]).to eq("click->pito--chat-prefill#fill")
    expect(span["data-pito--chat-prefill-text-value"]).to eq("show game ##{game.id}")
    expect(span["data-pito--chat-prefill-submit-value"]).to eq("true")
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
