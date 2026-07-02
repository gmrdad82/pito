# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Search::Modules::IgdbGames, type: :service do
  subject(:mod) { described_class.new }

  it "registers itself under :igdb_games" do
    expect(Pito::Search::Registry.for(:igdb_games)).to eq(described_class)
  end

  it "wraps IGDB hits in the standard envelope" do
    allow_any_instance_of(Game::Igdb::Client)
      .to receive(:search_games).and_return([ { "id" => 1, "name" => "Zelda" } ])
    result = mod.call(query: "zel")
    expect(result[:hits].size).to eq(1)
    expect(result[:total]).to eq(1)
    expect(result[:error]).to be_nil
  end

  it "turns an IGDB error into a non-raising error envelope" do
    allow_any_instance_of(Game::Igdb::Client)
      .to receive(:search_games).and_raise(Game::Igdb::Client::Error, "boom")
    result = mod.call(query: "zel")
    expect(result[:hits]).to eq([])
    expect(result[:error][:kind]).to eq("upstream_unavailable")
  end

  it "returns empty for a blank query without calling IGDB" do
    expect_any_instance_of(Game::Igdb::Client).not_to receive(:search_games)
    expect(mod.call(query: "  ")).to eq(hits: [], total: 0, error: nil)
  end
end

RSpec.describe Pito::Search::Registry, type: :service do
  it "raises a clear error for an unknown module" do
    expect { described_class.for(:nope) }.to raise_error(KeyError, /no search module/)
  end
  # ── result cache (0.9.0 Phase 7) ─────────────────────────────────────────────

  describe "result cache" do
    around do |example|
      original    = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    it "answers a repeat query from the cache (one upstream call)" do
      client = instance_double(Game::Igdb::Client)
      allow(Game::Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:search_games).and_return([ { "id" => 1, "name" => "Hollow Knight" } ])

      2.times { Pito::Search::Modules::IgdbGames.new.call(query: "Hollow Knight") }

      expect(client).to have_received(:search_games).once
    end

    it "normalizes case for the cache key but keeps queries distinct by limit" do
      client = instance_double(Game::Igdb::Client)
      allow(Game::Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:search_games).and_return([])

      Pito::Search::Modules::IgdbGames.new.call(query: "SILKSONG")
      Pito::Search::Modules::IgdbGames.new.call(query: "silksong")
      Pito::Search::Modules::IgdbGames.new.call(query: "silksong", limit: 3)

      expect(client).to have_received(:search_games).twice # case-folded hit + limit variant
    end

    it "NEVER caches an error envelope (upstream blips stay retryable)" do
      client = instance_double(Game::Igdb::Client)
      allow(Game::Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:search_games)
        .and_raise(Game::Igdb::Client::ServerError, "5xx")

      first = Pito::Search::Modules::IgdbGames.new.call(query: "Celeste")
      allow(client).to receive(:search_games).and_return([ { "id" => 2 } ])
      second = Pito::Search::Modules::IgdbGames.new.call(query: "Celeste")

      expect(first[:error]).to be_present
      expect(second[:error]).to be_nil
      expect(second[:hits]).to be_present
    end
  end
end
