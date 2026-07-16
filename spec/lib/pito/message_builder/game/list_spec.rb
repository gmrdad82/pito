# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::List do
  let(:conversation) { create(:conversation) }
  let!(:zelda) { create(:game, title: "Tears of the Kingdom") }
  let!(:lies)  { create(:game, title: "Lies of P") }

  describe ".call" do
    let(:games) { ::Game.order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "includes table_rows with each game" do
      expect(payload["table_rows"]).to be_present
      expect(payload["table_rows"].size).to eq(2)
    end

    it "uses the #-prefixed game id as the first cell and title as the second cell" do
      rows = payload["table_rows"]
      expect(rows.map { |r| r[:cells][0][:text] }).to include("##{lies.id}", "##{zelda.id}")
      expect(rows.map { |r| r[:cells][1][:text] }).to include("Lies of P", "Tears of the Kingdom")
    end

    it "carries chat-prefill data on the #id cell so a click auto-submits `show game #id` (J6)" do
      row  = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{lies.id}" }
      data = row[:cells][0][:data]
      expect(data[:controller]).to eq("pito--chat-prefill")
      expect(data[:action]).to eq("click->pito--chat-prefill#fill")
      expect(data[:"pito--chat-prefill-text-value"]).to eq("show game ##{lies.id}")
      expect(data[:"pito--chat-prefill-submit-value"]).to eq("true")
    end

    it "wraps the intro count in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">2</span>})
    end

    it "wraps the noun in a subject-shimmer span" do
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">games</span>})
    end

    it "sets html true so the shimmer intro reveals via the htmlProse path" do
      expect(payload["html"]).to be true
    end

    it "is follow-up-able with target game_list" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("game_list")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "includes table_heading with # as a right-aligned hash and Game as a string" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Game" ])
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end

    it "payload includes list_footer as a String" do
      expect(payload["list_footer"]).to be_a(String)
    end
  end

  describe ".call with columns: [:genre, :footage]" do
    let(:genre)  { create(:genre, name: "Action") }
    let!(:game)  { create(:game, title: "Devil May Cry", footage_hours: 3) }
    let!(:_link) { create(:game_genre, game: game, genre: genre) }

    let(:games) { ::Game.includes(:genres).order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation, columns: [ :genre, :footage ]) }

    it "sets table_heading to [#-hash, Game, Genre, Footage-hash]" do
      expect(payload["table_heading"]).to eq([
        { "text" => "#", "class" => "text-right" },
        "Game",
        { "text" => "Genre", "class" => "pito-table-heading--added" },
        { "text" => "Footage", "class" => "pito-table-heading--added text-right" }
      ])
    end

    it "returns 4 cells per row" do
      expect(payload["table_rows"].first[:cells].size).to eq(4)
    end

    it "includes the genre name in the third cell" do
      genre_text = payload["table_rows"].first[:cells][2][:text]
      expect(genre_text).to include("Action")
    end

    it "includes the footage value in the fourth cell" do
      footage_text = payload["table_rows"].first[:cells][3][:text]
      expect(footage_text).to be_a(String).and be_present
    end
  end

  describe ".call with columns: [] (default)" do
    let(:games) { ::Game.order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation) }

    it "has heading [#-hash, Game] with no extra columns" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Game" ])
    end

    it "returns 2 cells per row" do
      row = payload["table_rows"].first
      expect(row[:cells].size).to eq(2)
    end

    it "first cell has yellow kbd shimmer token and is right-aligned (clickable)" do
      cell = payload["table_rows"].first[:cells][0]
      expect(cell[:class]).to include("pito-action-shimmer")
      expect(cell[:class]).to include("text-right")
    end

    it "second cell has text-fg class" do
      cell = payload["table_rows"].first[:cells][1]
      expect(cell[:class]).to include("text-fg")
    end

    it "title cell (index 1) carries the pito-cell-title class" do
      cell = payload["table_rows"].first[:cells][1]
      expect(cell[:class]).to include("pito-cell-title")
      expect(cell[:class]).to include("text-fg")
    end
  end

  # ── Pluralization ────────────────────────────────────────────────────────────

  describe ".call — intro pluralization" do
    context "with 1 game" do
      let!(:solo) { create(:game, title: "Solo Game") }
      let(:games) { ::Game.where(id: solo.id) }

      subject(:payload) { described_class.call(games, conversation: conversation) }

      it "uses singular 'game' in the intro noun span" do
        expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">game</span>})
        expect(payload["body"]).not_to match(/>games</)
      end
    end

    context "with 2 games" do
      let(:games) { ::Game.order(:title) }

      subject(:payload) { described_class.call(games, conversation: conversation) }

      it "uses plural 'games' in the intro noun span" do
        expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">games</span>})
      end
    end
  end

  # ── Full columns (all 6 with-cols) ────────────────────────────────────────────

  describe ".call — fixed_leading" do
    context "when :platform is among the columns" do
      let(:games) { ::Game.order(:title) }

      subject(:payload) { described_class.call(games, conversation: conversation, columns: [ :platform ]) }

      it "sets fixed_leading to 1" do
        expect(payload["fixed_leading"]).to eq(1)
      end
    end

    context "when :platform is not among the columns" do
      let(:games) { ::Game.order(:title) }

      subject(:payload) { described_class.call(games, conversation: conversation, columns: [ :genre ]) }

      it "sets fixed_leading to 0" do
        expect(payload["fixed_leading"]).to eq(0)
      end
    end

    context "when no columns are requested" do
      let(:games) { ::Game.order(:title) }

      subject(:payload) { described_class.call(games, conversation: conversation) }

      it "sets fixed_leading to 0" do
        expect(payload["fixed_leading"]).to eq(0)
      end
    end
  end

  describe ".call with columns (developer, publisher, genre, platform, footage) — release/year removed (item 24)" do
    let(:genre)       { create(:genre, name: "Action") }
    let(:dev_co)      { create(:company, name: "Studio Dev") }
    let(:pub_co)      { create(:company, name: "Studio Pub") }

    let!(:game) do
      g = create(:game, title: "Full Game", footage_hours: 4,
                        platforms: [ "PlayStation 5" ])
      create(:game_genre,     game: g, genre: genre)
      create(:game_developer, game: g, company: dev_co)
      create(:game_publisher, game: g, company: pub_co)
      g.reload
    end

    let(:games)   { ::Game.includes(:genres, :developer_companies, :publisher_companies).where(id: game.id) }
    let(:columns) { %i[developer publisher genre platform footage] }

    subject(:payload) { described_class.call(games, conversation: conversation, columns: columns) }

    it "has fixed_leading == 1 (platform)" do
      expect(payload["fixed_leading"]).to eq(1)
    end

    it "has fixed_trailing == 1 (footage)" do
      expect(payload["fixed_trailing"]).to eq(1)
    end

    it "columns are in canonical order (platform, genre, developer, publisher, footage)" do
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to eq(%w[# Game Platform Genre Developer Publisher Footage])
    end

    it "# heading is a right-aligned hash" do
      expect(payload["table_heading"].first).to eq({ "text" => "#", "class" => "text-right" })
    end

    it "Footage heading is a right-aligned hash" do
      entry = payload["table_heading"].find { |h| h.is_a?(Hash) && h["text"] == "Footage" }
      expect(entry).to eq({ "text" => "Footage", "class" => "pito-table-heading--added text-right" })
    end

    it "Footage cell is right-aligned" do
      row           = payload["table_rows"].first
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      footage_cell  = row[:cells][heading_texts.index("Footage")]
      expect(footage_cell[:class]).to include("text-right")
    end
  end

  describe ".call with columns: [:footage]" do
    let!(:game) { create(:game, title: "Footage Game", footage_hours: 12.5) }

    let(:games) { ::Game.where(id: game.id) }

    subject(:payload) { described_class.call(games, conversation: conversation, columns: [ :footage ]) }

    it "sets fixed_trailing to 1" do
      expect(payload["fixed_trailing"]).to eq(1)
    end

    it "includes a right-aligned Footage heading entry" do
      expect(payload["table_heading"]).to include({ "text" => "Footage", "class" => "pito-table-heading--added text-right" })
    end

    it "footage cell has text-right, tabular-nums, and pito-cell-duration classes" do
      footage_cell = payload["table_rows"].first[:cells].last
      expect(footage_cell[:class]).to include("text-right")
      expect(footage_cell[:class]).to include("tabular-nums")
      expect(footage_cell[:class]).to include("pito-cell-duration")
    end

    it "footage cell shows the FootageHours total" do
      footage_cell = payload["table_rows"].first[:cells].last
      expect(footage_cell[:text]).to eq("12.5h")
    end

    it "footage cell shows 0h when the game has no footage (always 0 fallback)" do
      game.update!(footage_hours: 0)
      footage_cell = payload["table_rows"].first[:cells].last
      expect(footage_cell[:text]).to eq("0h")
    end
  end

  # ── Scores (search's `like` path) ────────────────────────────────────────────

  describe ".call with scores:" do
    let(:games)  { ::Game.order(:title) }
    let(:scores) { { lies.id => 87, zelda.id => 42 } }

    subject(:payload) { described_class.call(games, conversation: conversation, scores: scores) }

    it "appends a trailing Score heading" do
      expect(payload["table_heading"]).to eq([
        { "text" => "#", "class" => "text-right" },
        "Game",
        "Score"
      ])
    end

    it "appends a trailing { score: } cell matching each record's score" do
      lies_row  = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{lies.id}" }
      zelda_row = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{zelda.id}" }
      expect(lies_row[:cells].last).to eq({ score: 87 })
      expect(zelda_row[:cells].last).to eq({ score: 42 })
    end

    context "when a record's id is absent from the scores hash" do
      let(:scores) { { lies.id => 87 } }

      it "renders { score: nil } for the record missing from the hash" do
        zelda_row = payload["table_rows"].find { |r| r[:cells][0][:text] == "##{zelda.id}" }
        expect(zelda_row[:cells].last).to eq({ score: nil })
      end
    end
  end

  describe ".call with scores: nil (explicit) — identical to omitting scores" do
    let(:games) { ::Game.order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation, scores: nil) }

    it "does not append a Score heading" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Game" ])
    end

    it "does not append a score cell to any row" do
      payload["table_rows"].each do |row|
        expect(row[:cells].size).to eq(2)
      end
    end
  end
end
