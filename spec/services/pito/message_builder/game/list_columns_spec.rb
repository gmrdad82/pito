# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::ListColumns do
  # ── vocabulary ──────────────────────────────────────────────────────────────

  describe ".vocabulary" do
    subject(:vocab) { described_class.vocabulary }

    it "returns a Hash" do
      expect(vocab).to be_a(Hash)
    end

    it "maps 'platform' to :platform" do
      expect(vocab["platform"]).to eq(:platform)
    end

    it "maps 'platforms' to :platform" do
      expect(vocab["platforms"]).to eq(:platform)
    end

    it "maps 'price' AND 'prices' to :price (D2 — plural synonym)" do
      expect(vocab["price"]).to eq(:price)
      expect(vocab["prices"]).to eq(:price)
    end

    it "maps 'genre' to :genre" do
      expect(vocab["genre"]).to eq(:genre)
    end

    it "maps 'genres' to :genre" do
      expect(vocab["genres"]).to eq(:genre)
    end

    it "maps 'developer' to :developer" do
      expect(vocab["developer"]).to eq(:developer)
    end

    it "maps 'dev' to :developer" do
      expect(vocab["dev"]).to eq(:developer)
    end

    it "maps 'publisher' to :publisher" do
      expect(vocab["publisher"]).to eq(:publisher)
    end

    it "maps 'release date' to :release_date" do
      expect(vocab["release date"]).to eq(:release_date)
    end

    it "maps 'year' to :year" do
      expect(vocab["year"]).to eq(:year)
    end

    it "maps 'channel' to :channels" do
      expect(vocab["channel"]).to eq(:channels)
    end

    it "maps 'channels' to :channels" do
      expect(vocab["channels"]).to eq(:channels)
    end

    it "maps 'footage' to :footage" do
      expect(vocab["footage"]).to eq(:footage)
    end

    it "does not include unknown tokens" do
      expect(vocab.key?("unknown_token")).to be(false)
    end
  end

  # ── headings ────────────────────────────────────────────────────────────────

  describe ".headings" do
    it "returns an empty array for no columns" do
      expect(described_class.headings([])).to eq([])
    end

    it "returns the heading for a single column" do
      expect(described_class.headings([ :genre ])).to eq([ "Genre" ])
    end

    it "returns headings in the requested order" do
      expect(described_class.headings([ :year, :developer ])).to eq([ "Year", "Developer" ])
    end

    it "returns the heading for footage" do
      expect(described_class.headings([ :footage ])).to eq([ "Footage" ])
    end

    it "includes all eight headings when all columns are requested" do
      all = %i[platform genre developer publisher channels release_date year footage]
      expect(described_class.headings(all)).to eq(
        [ "Platform", "Genre", "Developer", "Publisher", "Channels", "Release", "Year", "Footage" ]
      )
    end
  end

  # ── sort_key_for ─────────────────────────────────────────────────────────────

  describe ".sort_key_for" do
    let(:game) { create(:game, title: "Elden Ring", release_year: 2022) }

    it "returns a proc for a base column regardless of selected_columns" do
      key = described_class.sort_key_for("title", selected_columns: [])
      expect(key).to be_a(Proc)
      expect(key.call(game)).to eq("elden ring")
    end

    it "returns a proc for 'id' (base column) with no selected_columns" do
      key = described_class.sort_key_for("id", selected_columns: [])
      expect(key).to be_a(Proc)
      expect(key.call(game)).to eq(game.id)
    end

    it "returns nil for a with-column NOT in selected_columns" do
      key = described_class.sort_key_for("year", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for a with-column that IS in selected_columns" do
      key = described_class.sort_key_for("year", selected_columns: [ :year ])
      expect(key).to be_a(Proc)
      expect(key.call(game)).to eq(2022)
    end

    it "returns nil for an unknown token" do
      key = described_class.sort_key_for("bogus", selected_columns: [ :year ])
      expect(key).to be_nil
    end

    it "returns a proc for the '#' alias pointing to :id" do
      key = described_class.sort_key_for("#", selected_columns: [])
      expect(key).to be_a(Proc)
    end

    it "returns a proc for the 'game' alias pointing to :title" do
      key = described_class.sort_key_for("game", selected_columns: [])
      expect(key).to be_a(Proc)
    end

    it "is case-insensitive for the token" do
      key = described_class.sort_key_for("TITLE", selected_columns: [])
      expect(key).to be_a(Proc)
    end

    # TBA games (no release date / year) must sort AFTER known dates ascending
    # (and first descending) — the key treats unknown as the far future.
    it "sorts a TBA game (nil release_date) after a known date ascending" do
      tba   = create(:game, release_year: nil, release_month: nil, release_day: nil)
      known = create(:game, release_year: 2015, release_month: 3, release_day: 1)
      key   = described_class.sort_key_for("release date", selected_columns: [ :release_date ])
      expect(key.call(tba)).to be > key.call(known)
    end

    it "sorts a TBA game (nil year) after a known year ascending" do
      tba   = build(:game, release_year: nil)
      known = build(:game, release_year: 2015)
      key   = described_class.sort_key_for("year", selected_columns: [ :year ])
      expect(key.call(tba)).to be > key.call(known)
    end

    it "returns nil for 'channel' when :channels not in selected_columns" do
      key = described_class.sort_key_for("channel", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns nil for 'channels' when :channels not in selected_columns" do
      key = described_class.sort_key_for("channels", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for 'channel' when :channels IS in selected_columns" do
      game = create(:game)
      key  = described_class.sort_key_for("channel", selected_columns: [ :channels ])
      expect(key).to be_a(Proc)
      expect(key.call(game)).to be_a(String)
    end

    it "returns a proc for 'channels' when :channels IS in selected_columns" do
      key = described_class.sort_key_for("channels", selected_columns: [ :channels ])
      expect(key).to be_a(Proc)
    end

    it "returns nil for 'footage' when :footage not in selected_columns" do
      key = described_class.sort_key_for("footage", selected_columns: [])
      expect(key).to be_nil
    end

    it "returns a proc for 'footage' when :footage IS in selected_columns" do
      key = described_class.sort_key_for("footage", selected_columns: [ :footage ])
      expect(key).to be_a(Proc)
    end
  end

  # ── cells ────────────────────────────────────────────────────────────────────

  describe ".cells" do
    let(:action_genre)  { create(:genre, name: "Action") }
    let(:rpg_genre)     { create(:genre, name: "Role-playing") }
    let(:dev_company)   { create(:company, name: "From Software") }
    let(:pub_company)   { create(:company, name: "Bandai Namco") }

    let(:game) do
      g = create(:game, title: "Elden Ring", release_year: 2022,
                         release_month: 2, release_day: 25,
                         platforms: [ "PlayStation 5", "PC (Microsoft Windows)" ])
      create(:game_genre,    game: g, genre: action_genre)
      create(:game_genre,    game: g, genre: rpg_genre)
      create(:game_developer, game: g, company: dev_company)
      create(:game_publisher, game: g, company: pub_company)
      g.reload
    end

    it "returns an empty array for no columns" do
      expect(described_class.cells(game, [])).to eq([])
    end

    it "returns cells with the genre cap/truncate class" do
      result = described_class.cells(game, [ :genre ])
      expect(result.first[:class]).to eq("text-fg-dim pito-cell-genre")
    end

    it "returns genre names joined by ', '" do
      result = described_class.cells(game, [ :genre ])
      expect(result.first[:text]).to include("Action")
      expect(result.first[:text]).to include("Role-playing")
    end

    it "returns developer company names" do
      result = described_class.cells(game, [ :developer ])
      expect(result.first[:text]).to include("From Software")
    end

    it "returns publisher company names" do
      result = described_class.cells(game, [ :publisher ])
      expect(result.first[:text]).to include("Bandai Namco")
    end

    it "returns platform cell with html: true" do
      result = described_class.cells(game, [ :platform ])
      expect(result.first[:html]).to be(true)
    end

    it "returns platform cell text containing <img tags" do
      result = described_class.cells(game, [ :platform ])
      expect(result.first[:text]).to include("<img")
    end

    it "returns platform cell text containing /platforms/ SVG srcs" do
      result = described_class.cells(game, [ :platform ])
      expect(result.first[:text]).to include("/platforms/")
    end

    it "returns platform cell text with PlayStation and Steam icons (Xbox dropped)" do
      g = create(:game, platforms: [ "PlayStation 5", "Xbox One", "Steam" ])
      result = described_class.cells(g, [ :platform ])
      expect(result.first[:text]).to include("/platforms/playstation.svg")
      expect(result.first[:text]).to include("/platforms/steam.svg")
      expect(result.first[:text]).not_to include("Xbox")
    end

    it "returns the release year as a string" do
      result = described_class.cells(game, [ :year ])
      expect(result.first[:text]).to eq("2022")
    end

    it "returns '—' for a game with no release year" do
      tba_game = create(:game, :tba)
      result   = described_class.cells(tba_game, [ :year ])
      expect(result.first[:text]).to eq("—")
    end

    it "returns the release label for :release_date" do
      result = described_class.cells(game, [ :release_date ])
      expect(result.first[:text]).to be_a(String)
      expect(result.first[:text]).not_to be_empty
    end

    it "returns cells in the requested column order" do
      result = described_class.cells(game, [ :year, :developer ])
      expect(result.size).to eq(2)
      expect(result[0][:text]).to eq("2022")
      expect(result[1][:text]).to include("From Software")
    end

    it "right-aligns the :release_date cell" do
      result = described_class.cells(game, [ :release_date ])
      expect(result.first[:class]).to include("text-right")
    end

    it "right-aligns the :year cell" do
      result = described_class.cells(game, [ :year ])
      expect(result.first[:class]).to include("text-right")
    end

    it "adds tabular-nums to the :year cell" do
      result = described_class.cells(game, [ :year ])
      expect(result.first[:class]).to include("tabular-nums")
    end

    it "does NOT add text-right to left-aligned columns" do
      %i[platform genre developer publisher channels].each do |col|
        result = described_class.cells(game, [ col ])
        expect(result.first[:class]).not_to include("text-right"), "expected #{col} not to be right-aligned"
      end
    end

    context "channels column" do
      let(:channel1) { create(:channel, handle: "@manfygreats") }
      let(:channel2) { create(:channel, handle: "@awesomegamer") }
      let(:channel3) { create(:channel, handle: "@thirdchannel") }
      let(:game_with_channels) { create(:game) }

      def link(channel)
        video = create(:video, channel: channel)
        create(:video_game_link, game: game_with_channels, video: video)
      end

      it "returns a single @handle for a game with one linked channel" do
        link(channel1)
        game_with_channels.reload
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:text]).to eq("@manfygreats")
      end

      it "collapses two channels onto one line as `@first +1 more`" do
        link(channel1)
        link(channel2)
        game_with_channels.reload
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:text]).to match(/\A@\w+ \+1 more\z/)
      end

      it "shows `+2 more` for a game across three channels" do
        link(channel1)
        link(channel2)
        link(channel3)
        game_with_channels.reload
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:text]).to match(/\A@\w+ \+2 more\z/)
      end

      it "de-duplicates handles when multiple videos share the same channel" do
        link(channel1)
        link(channel1)
        game_with_channels.reload
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:text]).to eq("@manfygreats")
      end

      it "returns an em dash for a game with no linked videos" do
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:text]).to eq("—")
      end

      it "is plain text (not html), so it renders on a single line" do
        link(channel1)
        link(channel2)
        game_with_channels.reload
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:html]).to be(false)
        expect(result.first[:text]).not_to include("<br>")
      end

      it "applies shimmer and clamps the :channels cell (pito-token + pito-cell-channel)" do
        result = described_class.cells(game_with_channels, [ :channels ])
        expect(result.first[:class]).to include("pito-token")
        expect(result.first[:class]).to include("pito-cell-channel")
        expect(result.first[:class]).not_to include("text-cyan")
      end

      it "renders the channel @handle as a PLAIN token (no shimmer offset — owner 17.4)" do
        link(channel1)
        game_with_channels.reload
        game_b = create(:game)
        link2  = create(:video, channel: channel1)
        create(:video_game_link, game: game_b, video: link2)
        game_b.reload

        result_a = described_class.cells(game_with_channels, [ :channels ])
        result_b = described_class.cells(game_b,             [ :channels ])

        # Verify both rows show the same handle so the test is meaningful.
        expect(result_a.first[:text]).to eq(result_b.first[:text])

        # Decorative handles are plain now — no shimmer, hence no game-id offset.
        [ result_a, result_b ].each do |r|
          expect(r.first[:class]).to include("pito-token")
          expect(r.first[:class]).not_to match(/\bpito-shimmer-d\d+\b/)
        end
      end
    end

    context "footage column" do
      let(:game_with_footage) { create(:game) }

      it "returns the FootageHours total when footage_hours is set" do
        game_with_footage.update!(footage_hours: 12.5)
        result = described_class.cells(game_with_footage, [ :footage ])
        expect(result.first[:text]).to eq("12.5h")
      end

      it "strips the decimal for a whole-hour total" do
        game_with_footage.update!(footage_hours: 5)
        result = described_class.cells(game_with_footage, [ :footage ])
        expect(result.first[:text]).to eq("5h")
      end

      it "returns '0h' when there is no footage (always 0 fallback, never a dash)" do
        game_with_footage.update!(footage_hours: 0)
        result = described_class.cells(game_with_footage, [ :footage ])
        expect(result.first[:text]).to eq("0h")
      end

      it "has text-right, tabular-nums, and pito-cell-duration in cell class" do
        result = described_class.cells(game_with_footage, [ :footage ])
        expect(result.first[:class]).to include("text-right")
        expect(result.first[:class]).to include("tabular-nums")
        expect(result.first[:class]).to include("pito-cell-duration")
      end
    end

    context "price column" do
      let(:game_with_price) { create(:game) }

      it "renders coin glyphs + the number (html cell) when priced" do
        game_with_price.update!(price: BigDecimal("59.99"))
        result = described_class.cells(game_with_price, [ :price ])
        expect(result.first[:html]).to be(true)
        expect(result.first[:text]).to include("/coin/coin.gif")
        expect(result.first[:text]).to include("59.99")
        expect(result.first[:text].scan("pito-coin\"").size).to eq(3)
      end

      it "renders the FREE star for an explicit 0 price" do
        game_with_price.update!(price: 0)
        result = described_class.cells(game_with_price, [ :price ])
        expect(result.first[:text]).to include("/coin/star.gif")
        expect(result.first[:text]).not_to include("/coin/coin.gif")
      end

      it "renders an em-dash when the game is unpriced (nil)" do
        result = described_class.cells(game_with_price, [ :price ])
        expect(result.first[:text]).to eq("—")
      end

      it "is right-aligned, tabular-nums, with the pito-cell-price cap" do
        result = described_class.cells(game_with_price, [ :price ])
        expect(result.first[:class]).to include("text-right")
        expect(result.first[:class]).to include("tabular-nums")
        expect(result.first[:class]).to include("pito-cell-price")
      end

      # ── D1: decimal-aligned numbers via integer-part padding ──────────────
      it "left-pads the integer part with figure-space when price_pad_int is set" do
        game_with_price.update!(price: BigDecimal("9.89"))
        result = described_class.cells(game_with_price, [ :price ], price_pad_int: 2)
        # 1-digit "9" padded to 2 → one U+2007 before the number.
        expect(result.first[:text]).to include("\u{2007}9.89")
      end

      it "does NOT pad a number already at the max width" do
        game_with_price.update!(price: BigDecimal("99.98"))
        result = described_class.cells(game_with_price, [ :price ], price_pad_int: 2)
        expect(result.first[:text]).not_to include(" ")
        expect(result.first[:text]).to include("99.98")
      end
    end

    describe ".price_pad_int" do
      it "returns the max integer-part width across priced games (skips unpriced)" do
        games = [
          create(:game, price: BigDecimal("9.89")),    # 1
          create(:game, price: BigDecimal("129.99")),  # 3
          create(:game, price: nil),                    # skipped
          create(:game, price: BigDecimal("59.99"))     # 2
        ]
        expect(described_class.price_pad_int(games)).to eq(3)
      end

      it "counts an explicit 0 (free) as one digit and returns 0 when none priced" do
        expect(described_class.price_pad_int([ create(:game, price: 0) ])).to eq(1)
        expect(described_class.price_pad_int([ create(:game, price: nil) ])).to eq(0)
      end
    end
  end

  describe ".sort_key_for — price" do
    let(:game) { create(:game, price: BigDecimal("59.99")) }

    it "returns nil for 'price' when :price not in selected_columns" do
      expect(described_class.sort_key_for("price", selected_columns: [])).to be_nil
    end

    it "returns a proc keyed on the price when :price IS in selected_columns" do
      key = described_class.sort_key_for("price", selected_columns: [ :price ])
      expect(key).to be_a(Proc)
      expect(key.call(game)).to eq(BigDecimal("59.99"))
    end

    it "sorts an unpriced game before any priced game (nil → -1)" do
      key       = described_class.sort_key_for("price", selected_columns: [ :price ])
      unpriced  = create(:game, price: nil)
      expect(key.call(unpriced)).to eq(-1)
    end
  end

  # ── heading_cells ─────────────────────────────────────────────────────────────

  describe ".heading_cells" do
    it "tags a left-aligned added column with the cyan --added class" do
      expect(described_class.heading_cells([ :genre ])).to eq(
        [ { "text" => "Genre", "class" => "pito-table-heading--added" } ]
      )
    end

    it "right-aligns and tags :release_date" do
      result = described_class.heading_cells([ :release_date ])
      expect(result.first).to eq({ "text" => "Release", "class" => "pito-table-heading--added text-right" })
    end

    it "right-aligns and tags :year" do
      result = described_class.heading_cells([ :year ])
      expect(result.first).to eq({ "text" => "Year", "class" => "pito-table-heading--added text-right" })
    end

    it "tags every added heading, in order" do
      result = described_class.heading_cells([ :developer, :year ])
      expect(result[0]).to eq({ "text" => "Developer", "class" => "pito-table-heading--added" })
      expect(result[1]).to eq({ "text" => "Year", "class" => "pito-table-heading--added text-right" })
    end
  end

  # ── addable_footer ────────────────────────────────────────────────────────────

  describe ".addable_footer" do
    it "names the still-addable columns when some remain" do
      footer = described_class.addable_footer([ :genre ])
      expect(footer).to include("platform")
      expect(footer).to include("developer")
    end

    it "uses the all-shown variant (no column names) when every column is present" do
      footer = described_class.addable_footer(described_class::COLUMNS.keys)
      expect(footer).not_to include("platform")
      expect(footer).not_to include("genre")
    end
  end

  # ── canonical_order ───────────────────────────────────────────────────────────

  describe ".canonical_order" do
    it "returns an empty array for empty input" do
      expect(described_class.canonical_order([])).to eq([])
    end

    it "keeps a single column unchanged" do
      expect(described_class.canonical_order([ :genre ])).to eq([ :genre ])
    end

    it "sorts columns by their COLUMNS order" do
      expect(described_class.canonical_order([ :year, :platform, :developer ]))
        .to eq([ :platform, :developer, :year ])
    end

    it "ensures :release_date, :year, and :footage always trail the other columns" do
      all = %i[release_date year platform genre developer publisher channels footage]
      result = described_class.canonical_order(all)
      expect(result.last(3)).to eq(%i[release_date year footage])
    end

    it "places :channels before :release_date and :year" do
      all = %i[channels release_date year]
      result = described_class.canonical_order(all)
      expect(result.index(:channels)).to be < result.index(:release_date)
      expect(result.index(:channels)).to be < result.index(:year)
    end

    it "places :footage after :year" do
      result = described_class.canonical_order(%i[footage year platform])
      expect(result.index(:footage)).to be > result.index(:year)
    end
  end
end
