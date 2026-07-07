# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Search do
  let(:conversation) { Conversation.singleton }

  def search(raw)
    msg = Pito::Chat::Parser.call(Pito::Lex::Lexer.call(raw), raw:, conversation:)
    described_class.new(message: msg, conversation:).call
  end

  def stub_similar(games)
    results = games.map do |g|
      Pito::Recommendation::GameSimilarity::Result.new(game: g, score: 90, breakdown: {})
    end
    allow(Pito::Recommendation::GameSimilarity).to receive(:call).and_return(results)
  end

  it "asks for a seed on a bare `search`" do
    expect(search("search").events.first[:payload]["text"]).to include("Search for what")
  end

  it "reports seed-not-found for an unknown title" do
    result = search("search games like nonexistent")
    expect(result.events.first[:payload]["text"]).to include("nonexistent")
  end

  context "with a seed game and similar results" do
    let!(:seed) { create(:game, title: "Tekken 7") }
    let!(:g1)   { create(:game, title: "Street Fighter 6") }
    let!(:g2)   { create(:game, title: "Mortal Kombat 1") }

    it "renders a game_list card of the similar games in ranked order" do
      stub_similar([ g1, g2 ])
      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["reply_target"]).to eq("game_list")
      expect(payload["game_ids"]).to eq([ g1.id, g2.id ])
    end

    it "resolves the seed fuzzily (search games like tekken → Tekken 7)" do
      stub_similar([ g1 ])
      search("search games like tekken")
      expect(Pito::Recommendation::GameSimilarity).to have_received(:call).with(seed, limit: nil)
    end

    it "reports no-matches when similarity is empty" do
      stub_similar([])
      expect(search("search games like tekken 7").events.first[:payload]["text"]).to include("close enough")
    end

    it "stamps a ranked_ids cursor + more footer when results exceed a page" do
      allow(Pito::Dispatch::Config).to receive(:pager).with(verb: :list)
        .and_return(page_size: 1, more_verb: "next")
      stub_similar([ g1, g2 ])
      payload = search("search games like tekken 7").events.first[:payload]
      expect(payload["game_ids"]).to eq([ g1.id ])
      expect(payload["list_cursor"]["ranked_ids"]).to eq([ g1.id, g2.id ])
      expect(payload["list_cursor"]["offset"]).to eq(1)
      expect(payload["list_footer"].to_s).to include("next")
    end
  end
end
