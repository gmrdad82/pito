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
end
