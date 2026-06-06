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

    # T16.7 — version_parent = null filter in the Apicalypse query body.
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
  end
end
