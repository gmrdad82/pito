# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::Igdb::Client, type: :service do
  before do
    allow(Pito::Credentials).to receive(:igdb_client_id).and_return("client-id")
    allow(Pito::Credentials).to receive(:igdb_client_secret).and_return("client-secret")
    Rails.cache.delete("igdb:twitch_token")
    stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
      .to_return(
        status:  200,
        body:    { access_token: "tok", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#search_games" do
    it "returns parsed IGDB hits (creds header built correctly)" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with(headers: { "Client-ID" => "client-id", "Authorization" => "Bearer tok" })
        .to_return(
          status:  200,
          body:    [ { "id" => 1, "name" => "Zelda", "cover" => { "image_id" => "abc" } } ].to_json,
          headers: { "Content-Type" => "application/json" }
        )

      hits = described_class.new.search_games("zelda")
      expect(hits.map { |h| h["name"] }).to eq([ "Zelda" ])
    end

    it "rejects coverless rows" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(
          status:  200,
          body:    [ { "id" => 2, "name" => "No Cover" } ].to_json,
          headers: { "Content-Type" => "application/json" }
        )
      expect(described_class.new.search_games("nc")).to eq([])
    end

    # Smoke #16 — IGDB's search endpoint mis-tags editions/DLC (null game_type /
    # version_parent), so they slip past the API filter. The name-level net drops
    # them: searching "Elden Ring" returns only the distinct games.
    it "drops edition / DLC / bundle rows by name (keeps distinct titles)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 1,  "name" => "Elden Ring Nightreign",                              "cover" => cover },
        { "id" => 2,  "name" => "Elden Ring",                                          "cover" => cover },
        { "id" => 3,  "name" => "Elden Ring: Collector's Edition",                     "cover" => cover },
        { "id" => 4,  "name" => "Elden Ring GB",                                       "cover" => cover },
        { "id" => 5,  "name" => "Elden Ring: Shadow of the Erdtree - Premium Bundle",  "cover" => cover },
        { "id" => 6,  "name" => "Elden Ring: Deluxe Edition",                          "cover" => cover },
        { "id" => 7,  "name" => "Elden Ring: Launch Edition",                          "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      names = described_class.new.search_games("Elden Ring").map { |h| h["name"] }
      expect(names).to contain_exactly("Elden Ring Nightreign", "Elden Ring", "Elden Ring GB")
    end

    it "keeps editions when the query explicitly asks for one" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 1, "name" => "Elden Ring: Deluxe Edition", "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      names = described_class.new.search_games("elden ring deluxe edition").map { |h| h["name"] }
      expect(names).to eq([ "Elden Ring: Deluxe Edition" ])
    end

    # version_parent = null filter in the Apicalypse query body.
    it "sends version_parent = null in the query body to exclude edition variants" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(
          status:  200,
          body:    [ { "id" => 3, "name" => "RDR2", "cover" => { "image_id" => "xyz" } } ].to_json,
          headers: { "Content-Type" => "application/json" }
        )

      described_class.new.search_games("red dead")
      expect(captured_body).to include("version_parent = null")
    end

    it "includes version_parent in the fields request (needed for filter)" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(
          status:  200,
          body:    [].to_json,
          headers: { "Content-Type" => "application/json" }
        )

      described_class.new.search_games("some game")
      expect(captured_body).to include("version_parent")
    end

    it "does NOT apply version_parent filter when include_editions: true" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(
          status:  200,
          body:    [].to_json,
          headers: { "Content-Type" => "application/json" }
        )

      described_class.new.search_games("some game", include_editions: true)
      expect(captured_body).not_to include("version_parent = null")
    end

    it "keeps main games + remakes + remasters in the game_type filter (remakes not filtered out)" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.search_games("demon souls")
      expect(captured_body).to include("game_type = (0,8,9)")
    end

    it "returns BOTH the original (main) and the remake for a same-named game" do
      stub_request(:post, "https://api.igdb.com/v4/games").to_return(
        status:  200,
        body:    [
          { "id" => 1, "name" => "Demon's Souls", "game_type" => 0, "cover" => { "image_id" => "orig" },   "first_release_date" => 1_257_206_400 },
          { "id" => 2, "name" => "Demon's Souls", "game_type" => 8, "cover" => { "image_id" => "remake" }, "first_release_date" => 1_605_571_200 }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

      hits = described_class.new.search_games("demon souls")
      expect(hits.map { |h| h["id"] }).to contain_exactly(1, 2)
    end
  end
end
