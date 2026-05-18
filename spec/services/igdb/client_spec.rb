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

    # 2026-05-18 — default search filters to `game_type = 0` (Main Game)
    # so bundles, DLC, packs, costumes, ports, expansions, etc. drop out
    # at the IGDB API layer. Filter is null-tolerant on `game_type` to
    # cover the rare freshly-indexed row IGDB has not yet typed. Opt out
    # via `include_editions: true`.
    it "filters to game_type = 0 (Main Game) by default" do
      expected_set = Igdb::Client::DEFAULT_SEARCH_GAME_TYPES.join(",")
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /where game_type = \(#{Regexp.escape(expected_set)}\) \| game_type = null/)
        .to_return(status: 200, body: "[]")
      client.search_games("zelda")
      expect(stub).to have_been_requested
    end

    it "is null-tolerant on game_type so search hits with null game_type survive" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| req.body.include?("| game_type = null") }
        .to_return(status: 200, body: [ { "id" => 75235, "name" => "Ghost of Tsushima", "game_type" => nil } ].to_json)
      results = client.search_games("Ghost of")
      expect(stub).to have_been_requested
      expect(results.map { |r| r["id"] }).to include(75235)
    end

    it "drops the game_type filter when include_editions: true" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| !req.body.include?("where game_type") }
        .to_return(status: 200, body: "[]")
      client.search_games("zelda", include_editions: true)
      expect(stub).to have_been_requested
    end

    it "asks IGDB for the `game_type` field so callers can inspect it" do
      stub = stub_request(:post, "https://api.igdb.com/v4/games")
        .with(body: /fields[^;]*\bgame_type\b/)
        .to_return(status: 200, body: "[]")
      client.search_games("zelda")
      expect(stub).to have_been_requested
    end

    it "exposes the back-compat DEFAULT_SEARCH_CATEGORIES alias" do
      expect(Igdb::Client::DEFAULT_SEARCH_CATEGORIES)
        .to eq(Igdb::Client::DEFAULT_SEARCH_GAME_TYPES)
    end

    it "exposes back-compat GAME_CATEGORY_* aliases (main/remake/remaster/port)" do
      expect(Igdb::Client::GAME_CATEGORY_MAIN).to     eq(Igdb::Client::GAME_TYPE_MAIN_GAME)
      expect(Igdb::Client::GAME_CATEGORY_REMAKE).to   eq(Igdb::Client::GAME_TYPE_REMAKE)
      expect(Igdb::Client::GAME_CATEGORY_REMASTER).to eq(Igdb::Client::GAME_TYPE_REMASTER)
      expect(Igdb::Client::GAME_CATEGORY_PORT).to     eq(Igdb::Client::GAME_TYPE_PORT)
    end

    # 2026-05-18 — secondary safety net on top of the API-side
    # `game_type` filter. After the API returns N rows, the client
    # drops any non-top-result row whose name starts with the top
    # result's name + ":". Catches edition / pack / DLC noise that
    # IGDB occasionally mis-tags as `game_type = 0`.
    describe "name-based de-noise" do
      it "drops rows whose name starts with `<top>:` (edition / pack suffix)" do
        payload = [
          { "id" => 1, "name" => "Street Fighter 6",                          "game_type" => 0 },
          { "id" => 2, "name" => "Street Fighter 6: Mad Gear Box",            "game_type" => 0 },
          { "id" => 3, "name" => "Street Fighter 6: Year 2 Character Pass",   "game_type" => 0 },
          { "id" => 4, "name" => "Street Fighter VI 12 Peoples",              "game_type" => 0 }
        ]
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: payload.to_json)

        results = client.search_games("street fighter 6")
        expect(results.map { |r| r["id"] }).to eq([ 1, 4 ])
      end

      it "preserves rows that share a different prefix from the top result" do
        payload = [
          { "id" => 10, "name" => "Final Fantasy XVI",      "game_type" => 0 },
          { "id" => 11, "name" => "Final Fantasy XV",       "game_type" => 0 },
          { "id" => 12, "name" => "Final Fantasy XVI: DLC", "game_type" => 0 }
        ]
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: payload.to_json)

        results = client.search_games("final fantasy")
        # Only id 12 starts with "Final Fantasy XVI:" — id 11 has a
        # different prefix and survives.
        expect(results.map { |r| r["id"] }).to match_array([ 10, 11 ])
      end

      it "is a no-op when IGDB returns one or zero rows" do
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: [ { "id" => 1, "name" => "Solo Hit" } ].to_json)
        expect(client.search_games("solo")).to eq([ { "id" => 1, "name" => "Solo Hit" } ])
      end

      it "is a no-op when the top result has a blank name (defensive)" do
        payload = [
          { "id" => 1, "name" => "",                          "game_type" => 0 },
          { "id" => 2, "name" => ": leading colon weirdness", "game_type" => 0 }
        ]
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: payload.to_json)
        results = client.search_games("anything")
        expect(results.size).to eq(2)
      end

      it "explicit edition search keeps the matching edition as top result + cousins" do
        # When the user explicitly searches for the edition, the top hit
        # IS the edition; the prefix-drop does not match anything below.
        payload = [
          { "id" => 1, "name" => "Street Fighter 6: Year 1",      "game_type" => 0 },
          { "id" => 2, "name" => "Street Fighter 6: Year 1 Pass", "game_type" => 0 }
        ]
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: payload.to_json)
        results = client.search_games("street fighter 6: year 1")
        # Top hit "Street Fighter 6: Year 1" — `Street Fighter 6: Year 1:`
        # does NOT prefix "Street Fighter 6: Year 1 Pass" (no colon
        # between "1" and "Pass"). Both survive.
        expect(results.map { |r| r["id"] }).to match_array([ 1, 2 ])
      end

      it "skips de-noise entirely when include_editions: true" do
        payload = [
          { "id" => 1, "name" => "Street Fighter 6",                "game_type" => 0 },
          { "id" => 2, "name" => "Street Fighter 6: Mad Gear Box",  "game_type" => 0 }
        ]
        stub_request(:post, "https://api.igdb.com/v4/games")
          .to_return(status: 200, body: payload.to_json)
        results = client.search_games("street fighter 6", include_editions: true)
        expect(results.size).to eq(2)
      end
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

  # Phase 14 audit F1 — IGDB outbound POSTs MUST set bounded HTTP
  # timeouts so a hung api.igdb.com endpoint cannot wedge a Sidekiq
  # worker indefinitely. Mirrors the Phase 15 fix-forward pattern
  # landed in `Youtube::ServiceFactory` and
  # `NotificationDeliveryChannel#configure_http`.
  describe "HTTP timeouts (audit F1)" do
    it "sets open / read / write timeouts on the Net::HTTP instance" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: "[]")

      captured = nil
      original_start = Net::HTTP.method(:start)
      allow(Net::HTTP).to receive(:start) do |host, port, opts = {}, &block|
        original_start.call(host, port, opts) do |http|
          captured = http
          block.call(http)
        end
      end

      client.fetch_game(7346)

      expect(captured).to be_a(Net::HTTP)
      expect(captured.open_timeout).to  eq(Igdb::Client::OPEN_TIMEOUT_SEC)
      expect(captured.read_timeout).to  eq(Igdb::Client::READ_TIMEOUT_SEC)
      expect(captured.write_timeout).to eq(Igdb::Client::WRITE_TIMEOUT_SEC)
    end

    it "uses SSL because the IGDB base URL is HTTPS" do
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: "[]")

      captured = nil
      original_start = Net::HTTP.method(:start)
      allow(Net::HTTP).to receive(:start) do |host, port, opts = {}, &block|
        original_start.call(host, port, opts) do |http|
          captured = http
          block.call(http)
        end
      end

      client.fetch_game(7346)

      expect(captured.use_ssl?).to be(true)
    end

    it "surfaces a hung connection as Net::OpenTimeout to the caller" do
      # Sad-path proof: when the underlying connection raises a timeout
      # error, it bubbles up the stack instead of getting swallowed.
      stub_request(:post, "https://api.igdb.com/v4/games").to_timeout

      expect { client.fetch_game(7346) }.to raise_error(
        an_instance_of(Net::OpenTimeout).or(an_instance_of(Net::ReadTimeout))
      )
    end
  end
end
