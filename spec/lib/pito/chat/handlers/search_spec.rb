# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Search do
  let(:conversation) { Conversation.singleton }

  def search(raw)
    msg = Pito::Chat::Parser.call(Pito::Lex::Lexer.call(raw), raw:, conversation:)
    described_class.new(message: msg, conversation:).call
  end

  def stub_similar(results)
    allow(Pito::Recommendation::GameSimilarity).to receive(:call).and_return(results)
  end

  def result_for(game, score:, breakdown: {})
    Pito::Recommendation::GameSimilarity::Result.new(game: game, score: score, breakdown: breakdown)
  end

  it "asks for a seed on a bare `search`" do
    expect(search("search").events.first[:payload]["text"]).to include("Search for what")
  end

  it "reports seed-not-found for an unknown title" do
    result = search("search games like nonexistent")
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  context "with a seed that has a genre" do
    let!(:seed) { create(:game, title: "Tekken 7") }
    let!(:high_g) { create(:game, title: "Street Fighter 6") }
    let!(:low_g)  { create(:game, title: "Mortal Kombat 1") }
    let!(:no_g)   { create(:game, title: "Katamari Damacy") }

    before { seed.genres << create(:genre) }

    it "keeps only genre-overlapping results, seed first" do
      stub_similar([
        result_for(high_g, score: 68, breakdown: { g: 100 }),
        result_for(low_g,  score: 34, breakdown: { g: 33 }),
        result_for(no_g,   score: 51, breakdown: { g: 0, pp: 100 })
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ seed.id, high_g.id, low_g.id ])
    end

    it "resolves the seed fuzzily (search games like tekken → Tekken 7) and leads with it" do
      stub_similar([ result_for(high_g, score: 68, breakdown: { g: 100 }) ])
      payload = search("search games like tekken").events.first[:payload]
      expect(Pito::Recommendation::GameSimilarity).to have_received(:call).with(seed, limit: nil)
      expect(payload["game_ids"].first).to eq(seed.id)
    end

    it "renders just the seed row when nothing is relevant" do
      stub_similar([ result_for(no_g, score: 51, breakdown: { g: 0, pp: 100 }) ])
      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ seed.id ])
    end

    it "stamps a ranked_ids cursor + more footer when results exceed a page" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(tool: :list)
        .and_return(page_size: 1, more_tool: "next")
      stub_similar([
        result_for(high_g, score: 68, breakdown: { g: 100 }),
        result_for(low_g,  score: 34, breakdown: { g: 33 })
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ seed.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ seed.id, high_g.id, low_g.id ])
      expect(payload["list_cursor"]["offset"]).to eq(1)
      expect(payload["list_footer"].to_s).to include("next")
    end
  end

  context "with a seed that has no genres" do
    let!(:seed) { create(:game, title: "Tekken 7") }
    let!(:above_floor) { create(:game, title: "Street Fighter 6") }
    let!(:below_floor) { create(:game, title: "Mortal Kombat 1") }

    it "keeps only results at or above the no-genre score floor" do
      stub_similar([
        result_for(above_floor, score: 45, breakdown: {}),
        result_for(below_floor, score: 35, breakdown: {})
      ])

      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ seed.id, above_floor.id ])
    end
  end
end
