require "rails_helper"
require "ostruct"

RSpec.describe Igdb::Client do
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:token_cache) { Igdb::TokenCache.new(cache: cache) }
  let(:rate_limiter) { Igdb::RateLimiter.new(rate: 100, interval: 1.0, concurrency: 100) }
  let(:client) { described_class.new(token_cache: token_cache, rate_limiter: rate_limiter) }

  before do
    allow(Rails.application.credentials).to receive(:igdb).and_return(
      OpenStruct.new(client_id: "test_client_id", client_secret: "test_client_secret")
    )
    stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
      .to_return(status: 200, body: { access_token: "TOKEN", expires_in: 5_184_000 }.to_json)
  end

  describe "#search_games" do
    it "returns the parsed array on success" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /search "zelda"/)
        .to_return(status: 200, body: [ { "id" => 7346, "name" => "Zelda" } ].to_json)

      results = client.search_games("zelda", limit: 5)
      expect(results).to eq([ { "id" => 7346, "name" => "Zelda" } ])
    end

    it "defaults to limit 10" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /limit 10;/)
        .to_return(status: 200, body: "[]")

      client.search_games("zelda")
    end

    it "rejects a blank query" do
      expect { client.search_games("") }.to raise_error(ArgumentError)
      expect { client.search_games(nil) }.to raise_error(ArgumentError)
    end

    it "escapes embedded quotes in the body" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /search "'; drop tables;"/i)
        .to_return(status: 200, body: "[]")
      client.search_games("'; drop tables;")
      expect(stub).to have_been_requested
    end

    # Phase 14 §1 polish (2026-05-10) — default search filters to the
    # "main entries" category set so cluttery deluxe / ultimate edition
    # rows drop out (Pragmata Deluxe Edition, Red Dead Redemption II
    # Ultimate Edition, etc.). The filter is opt-out via
    # `include_editions: true`.
    it "filters to main + remake + remaster + port categories by default" do
      expected_set = Igdb::Client::DEFAULT_SEARCH_CATEGORIES.join(",")
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /where category = \(#{Regexp.escape(expected_set)}\)/)
        .to_return(status: 200, body: "[]")
      client.search_games("zelda")
      expect(stub).to have_been_requested
    end

    it "drops the category filter when include_editions: true" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| !req.body.include?("where category") }
        .to_return(status: 200, body: "[]")
      client.search_games("zelda", include_editions: true)
      expect(stub).to have_been_requested
    end

    it "asks IGDB for the `category` field so callers can inspect it" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /fields[^;]*\bcategory\b/)
        .to_return(status: 200, body: "[]")
      client.search_games("zelda")
      expect(stub).to have_been_requested
    end
  end

  describe "#fetch_game" do
    it "returns a one-element array on success" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /where id = 7346/)
        .to_return(status: 200, body: [ { "id" => 7346 } ].to_json)

      expect(client.fetch_game(7346)).to eq([ { "id" => 7346 } ])
    end

    it "returns [] for a non-existent id" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: "[]")
      expect(client.fetch_game(99_999_999)).to eq([])
    end

    it "rejects non-integer ids" do
      expect { client.fetch_game(0) }.to raise_error(ArgumentError)
      expect { client.fetch_game("seven") }.to raise_error(ArgumentError)
    end

    it "POSTs the documented Apicalypse body shape" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /\Afields id, name,.*where id = 7346; limit 1;\z/m)
        .to_return(status: 200, body: "[]")
      client.fetch_game(7346)
      expect(stub).to have_been_requested
    end

    it "POSTs both Client-ID and Authorization headers" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(headers: {
          "Client-ID" => "test_client_id",
          "Authorization" => "Bearer TOKEN"
        }).to_return(status: 200, body: "[]")
      client.fetch_game(7346)
      expect(stub).to have_been_requested
    end
  end

  describe "#fetch_time_to_beat" do
    it "POSTs against /game_time_to_beats with where game_id = ..." do
      stub = stub_request(:post, "https://api.igdb.com/v4/game_time_to_beats")
        .with(body: /where game_id = 7346/)
        .to_return(status: 200, body: [ { "hastily" => 1 } ].to_json)
      client.fetch_time_to_beat(7346)
      expect(stub).to have_been_requested
    end

    it "returns [] when IGDB has no TTB row" do
      stub_request(:post, "https://api.igdb.com/v4/game_time_to_beats")
        .to_return(status: 200, body: "[]")
      expect(client.fetch_time_to_beat(7346)).to eq([])
    end
  end

  describe "#fetch_external_games" do
    it "POSTs against /external_games" do
      stub = stub_request(:post, "https://api.igdb.com/v4/external_games")
        .with(body: /where game = 7346/)
        .to_return(status: 200, body: "[]")
      client.fetch_external_games(7346)
      expect(stub).to have_been_requested
    end
  end

  describe "#fetch_genres / #fetch_platforms / #fetch_companies" do
    it "fetches genres by ids" do
      stub_request(:post, "https://api.igdb.com/v4/genres")
        .with(body: /where id = \(31,32\)/)
        .to_return(status: 200, body: [ { "id" => 31 }, { "id" => 32 } ].to_json)
      result = client.fetch_genres([ 31, 32 ])
      expect(result.size).to eq(2)
    end

    it "returns [] for an empty id list" do
      expect(client.fetch_genres([])).to eq([])
      expect(client.fetch_platforms([])).to eq([])
      expect(client.fetch_companies([])).to eq([])
    end

    it "fetches platforms by ids" do
      stub_request(:post, "https://api.igdb.com/v4/platforms")
        .to_return(status: 200, body: [ { "id" => 6 } ].to_json)
      expect(client.fetch_platforms([ 6 ])).to eq([ { "id" => 6 } ])
    end

    it "fetches companies by ids" do
      stub_request(:post, "https://api.igdb.com/v4/companies")
        .to_return(status: 200, body: [ { "id" => 70 } ].to_json)
      expect(client.fetch_companies([ 70 ])).to eq([ { "id" => 70 } ])
    end
  end

  describe "auth flow" do
    it "uses a cached token across sequential calls (single Twitch hit)" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: "[]")
      client.fetch_game(7346)
      client.fetch_game(7346)
      expect(WebMock).to have_requested(:post, %r{id\.twitch\.tv/oauth2/token}).once
    end

    it "invalidates the token + retries once on a 401" do
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "T1", expires_in: 5_184_000 }.to_json)
        .to_return(status: 200, body: { access_token: "T2", expires_in: 5_184_000 }.to_json)

      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 401, body: "")
        .to_return(status: 200, body: [ { "id" => 7346 } ].to_json)

      expect(client.fetch_game(7346)).to eq([ { "id" => 7346 } ])
      expect(WebMock).to have_requested(:post, %r{id\.twitch\.tv/oauth2/token}).twice
    end

    it "raises AuthError on a second 401" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 401, body: "")
      expect { client.fetch_game(7346) }.to raise_error(Igdb::Client::AuthError)
    end
  end

  describe "rate-limit / errors" do
    it "raises RateLimited on 429 with Retry-After" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 429, body: "", headers: { "Retry-After" => "5" })
      expect { client.fetch_game(7346) }.to raise_error(Igdb::Client::RateLimited) do |err|
        expect(err.retry_after).to eq(5)
      end
    end

    it "defaults retry_after to 1 when 429 has no Retry-After" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 429, body: "")
      expect { client.fetch_game(7346) }.to raise_error(Igdb::Client::RateLimited) do |err|
        expect(err.retry_after).to eq(1)
      end
    end

    it "raises ValidationError on 400" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 400, body: "bad")
      expect { client.fetch_game(7346) }.to raise_error(Igdb::Client::ValidationError)
    end

    it "returns [] on 404" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 404, body: "")
      expect(client.fetch_game(7346)).to eq([])
    end

    it "raises ServerError on 500" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 500, body: "")
      expect { client.fetch_game(7346) }.to raise_error(Igdb::Client::ServerError)
    end
  end
end
