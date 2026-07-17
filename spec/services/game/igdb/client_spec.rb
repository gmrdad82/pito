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

    it "keeps main games + bundles + remakes + remasters + expanded games in the game_type filter" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.search_games("demon souls")
      expect(captured_body).to include("game_type = (0,3,8,9,10)")
    end

    it "includes expanded_game (game_type 10) in the game_type filter" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.search_games("granblue fantasy relink endless ragnarok")
      expect(captured_body).to include("10")
    end

    it "does NOT include packs (game_type 13) in the game_type filter" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.search_games("some game")
      expect(captured_body).not_to match(/game_type = \([^)]*13/)
    end

    # IGB1 (2026-06-28): bundles (game_type 3) now pass the API filter so combo
    # bundles are returned; non-combo gt3 rows are dropped post-fetch.
    it "includes bundles (game_type 3) in the game_type filter (IGB1)" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.search_games("some game")
      expect(captured_body).to include("game_type = (0,3,8,9,10)")
    end

    it "keeps an expanded game (game_type 10) in the search results" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 9999, "name" => "Granblue Fantasy: Relink - Endless Ragnarok", "game_type" => 10, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("Granblue Fantasy Relink Endless Ragnarok")
      expect(hits.map { |h| h["id"] }).to include(9999)
    end

    # IGB1 — expanded game (game_type 10) is always kept, even when the name
    # contains "Edition" and a colon prefix that would normally drop it.
    it "keeps a gt10 expanded game despite 'Edition' in name and colon prefix (IGB1 Kirby case)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 1001, "name" => "Kirby and the Forgotten Land: Nintendo Switch 2 Edition + Star-Crossed World",
          "game_type" => 10, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("Kirby Forgotten Land")
      expect(hits.map { |h| h["id"] }).to include(1001)
    end

    # IGB1 — combo bundles (game_type 3, name contains " + ") are kept.
    it "keeps gt3 combo bundles whose name contains ' + ' (IGB1 Mario cases)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 2001, "name" => "Super Mario 3D World + Bowser's Fury",           "game_type" => 3, "cover" => cover },
        { "id" => 2002, "name" => "Super Mario Galaxy + Super Mario Galaxy 2",        "game_type" => 3, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("Super Mario")
      expect(hits.map { |h| h["id"] }).to contain_exactly(2001, 2002)
    end

    # G85 — ampersand combos: IGDB joins some two-title bundles with " & "
    # instead of " + " ("Yakuza Kiwami 3 & Dark Ties"); the old " + "-only
    # pattern dropped them from the import sidebar.
    it "keeps gt3 combo bundles joined with ' & ' (G85 Yakuza Kiwami 3 & Dark Ties)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 4001, "name" => "Yakuza Kiwami 3 & Dark Ties", "game_type" => 3, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("yakuza kiwami 3 & dark ties")
      expect(hits.map { |h| h["id"] }).to eq([ 4001 ])
    end

    it "still drops a gt3 row whose ampersand is unspaced or part of a single title (G85)" do
      cover = { "image_id" => "img" }
      body = [
        # No spaced joiner — not a combo; gt3 without the pattern drops.
        { "id" => 4002, "name" => "Game&Watch Collection", "game_type" => 3, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("game watch")
      expect(hits).to be_empty
    end

    # IGB1 — non-combo gt3 bundles (no " + " in name) are dropped.
    it "drops gt3 non-combo bundles (no ' + ' in name) (IGB1)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 3001, "name" => "Some Game: Deluxe Edition",   "game_type" => 3, "cover" => cover },
        { "id" => 3002, "name" => "Another Pack",                 "game_type" => 3, "cover" => cover },
        { "id" => 3003, "name" => "Real Game",                    "game_type" => 0, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("some game")
      expect(hits.map { |h| h["id"] }).to eq([ 3003 ])
    end

    # 2026-07-01 — bundle-name ALLOWLIST: GOTY / Game of the Year / Anniversary
    # editions (game_type 3) are kept even without " + " (owner: the Rayman case).
    it "keeps gt3 Anniversary-edition bundles (owner Rayman case)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 6001, "name" => "Rayman: 30th Anniversary Edition", "game_type" => 3, "cover" => cover },
        { "id" => 6002, "name" => "Some Game 10th anniversary",       "game_type" => 3, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("Rayman 30th Anniversary")
      expect(hits.map { |h| h["id"] }).to contain_exactly(6001, 6002)
    end

    it "keeps gt3 GOTY / Game of the Year bundles in every case form" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 6101, "name" => "The Witcher 3: Wild Hunt - GOTY Edition", "game_type" => 3, "cover" => cover },
        { "id" => 6102, "name" => "Skyrim GoTY",                             "game_type" => 3, "cover" => cover },
        { "id" => 6103, "name" => "Fallout: Game of The Year Edition",       "game_type" => 3, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("goty")
      expect(hits.map { |h| h["id"] }).to contain_exactly(6101, 6102, 6103)
    end

    it "still DROPS gt3 non-combo bundles not on the allowlist (Deluxe / Collector / Pack)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 6201, "name" => "Some Game: Deluxe Edition",            "game_type" => 3, "cover" => cover },
        { "id" => 6202, "name" => "Some Game: Collector's Pack",          "game_type" => 3, "cover" => cover },
        { "id" => 6203, "name" => "Some Game: 30th Anniversary Edition",  "game_type" => 3, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("some game")
      # Only the Anniversary bundle survives; Deluxe + Collector's Pack drop.
      expect(hits.map { |h| h["id"] }).to eq([ 6203 ])
    end

    # IGB1 — existing gt0 name-filter behaviour is unchanged.
    it "keeps gt0 base game but still drops gt0 edition-noise and colon-prefix denoise rows (IGB1 backward compat)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 4001, "name" => "Street Fighter 6",                      "game_type" => 0, "cover" => cover },
        { "id" => 4002, "name" => "Street Fighter 6: Mad Gear Box",         "game_type" => 0, "cover" => cover },
        { "id" => 4003, "name" => "Street Fighter 6: Deluxe Edition",       "game_type" => 0, "cover" => cover },
        { "id" => 4004, "name" => "Street Fighter VI 12 Peoples",           "game_type" => 0, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("Street Fighter 6")
      expect(hits.map { |h| h["id"] }).to contain_exactly(4001, 4004)
    end

    # 2026-07-08 — owner plays only PS/Xbox/Switch/Steam. IGDB carries a second,
    # arcade-only "Tekken 7" (id 394038, slug tekken-7--1) with version_parent=null
    # and an identical name to the console release (id 7498) — neither the edition
    # filter nor the colon denoise catches it. Filtering to owner platforms drops it.
    it "drops arcade-only rows but keeps the same-named console/PC release (Tekken 7 dup)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 7498,   "name" => "Tekken 7", "game_type" => 10, "cover" => cover,
          "platforms" => [ { "name" => "PlayStation 4" }, { "name" => "PC (Microsoft Windows)" }, { "name" => "Xbox One" } ] },
        { "id" => 394038, "name" => "Tekken 7", "game_type" => 0, "cover" => cover,
          "platforms" => [ { "name" => "Arcade" } ] }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("tekken 7")
      expect(hits.map { |h| h["id"] }).to eq([ 7498 ])
    end

    it "keeps a row that is on Arcade AND an owner platform" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 19555, "name" => "Some Fighter", "game_type" => 0, "cover" => cover,
          "platforms" => [ { "name" => "Arcade" }, { "name" => "PlayStation VR" } ] }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("some fighter")
      expect(hits.map { |h| h["id"] }).to eq([ 19555 ])
    end

    it "keeps a row with no platforms listed (null-tolerant — missing data must not drop a title)" do
      cover = { "image_id" => "img" }
      body = [
        { "id" => 8001, "name" => "Platformless Game", "game_type" => 0, "cover" => cover }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      hits = described_class.new.search_games("platformless")
      expect(hits.map { |h| h["id"] }).to eq([ 8001 ])
    end

    it "requests platforms.name in the search fields (needed for the platform filter)" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.search_games("anything")
      expect(captured_body).to include("platforms.name")
    end

    # IGB1 — cover-less rows drop for every game_type.
    it "drops cover-less rows regardless of game_type (IGB1)" do
      body = [
        { "id" => 5001, "name" => "GT10 No Cover",                 "game_type" => 10 },
        { "id" => 5002, "name" => "GT3 Combo No Cover A + B",      "game_type" => 3  },
        { "id" => 5003, "name" => "GT0 No Cover",                  "game_type" => 0  }
      ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      expect(described_class.new.search_games("no cover")).to eq([])
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

  # L6 flip (2026-07-17): game_modes/hypes/age_ratings added to GAME_FIELDS
  # so multiplayer/single_player/hyped/family_friendly can derive from
  # synced IGDB facts instead of Claude judgment (traits-design.md L6).
  describe "#fetch_game" do
    it "requests game_modes, hypes, and the nested age_ratings fields" do
      captured_body = nil
      stub_request(:post, "https://api.igdb.com/v4/games")
        .with { |req| captured_body = req.body; true }
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      described_class.new.fetch_game(1)

      expect(captured_body).to include("game_modes.id")
      expect(captured_body).to include("game_modes.name")
      expect(captured_body).to include("hypes")
      # Post-2025 IGDB v4 age_ratings shape (verified live 2026-07-17) —
      # nested through age_ratings.organization + age_ratings.rating_category,
      # NOT the retired numeric category/rating enum pair.
      expect(captured_body).to include("age_ratings.organization.name")
      expect(captured_body).to include("age_ratings.rating_category.rating")
    end
  end
end
