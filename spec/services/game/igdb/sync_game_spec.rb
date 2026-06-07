# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Igdb::SyncGame, type: :service do
  let(:game) { create(:game, igdb_id: 1020, title: "stub") }
  let(:client) { instance_double(Game::Igdb::Client) }

  let(:game_json) do
    {
      "id" => 1020, "name" => "Lies of P", "slug" => "lies-of-p",
      "summary" => "A soulslike.",
      "rating" => 85.5, "rating_count" => 120,
      "genres" => [
        { "id" => 12, "name" => "Role-playing (RPG)", "slug" => "rpg" },
        { "id" => 31, "name" => "Adventure", "slug" => "adventure" }
      ],
      "platforms" => [
        { "id" => 6,   "name" => "PC (Microsoft Windows)", "slug" => "win" },
        { "id" => 130, "name" => "Nintendo Switch", "slug" => "switch" }
      ],
      "involved_companies" => []
    }
  end

  before do
    allow(client).to receive(:fetch_game).with(1020).and_return([ game_json ])
    allow(client).to receive(:fetch_time_to_beat).with(1020).and_return({ "hastily" => 3600 })
    allow(Game::CoverArt::Normalizer).to receive(:new).and_return(instance_double(Game::CoverArt::Normalizer, call: nil))
    allow(GameVoyageIndexJob).to receive(:perform_later)
  end

  it "populates the game end-to-end against the reconciled schema" do
    described_class.new(client: client).call(game)
    game.reload

    expect(game.title).to eq("Lies of P")
    expect(game.igdb_rating.to_f).to eq(85.5)
    expect(game.genres.map(&:name)).to contain_exactly("Role-playing (RPG)", "Adventure")
    expect(game.platforms).to eq([ "PC (Microsoft Windows)", "Nintendo Switch" ])
    expect(game.ttb_main_seconds).to eq(3600)
    expect(game.score).to be > 0
    expect(game.igdb_synced_at).to be_present
    expect(game.last_sync_error).to be_nil
  end

  it "stores all IGDB genres (no primary-genre evaluator)" do
    described_class.new(client: client).call(game)
    expect(game.reload.genres.count).to eq(2)
  end

  it "enqueues the Voyage index after sync" do
    described_class.new(client: client).call(game)
    expect(GameVoyageIndexJob).to have_received(:perform_later).with(game.id)
  end
end
