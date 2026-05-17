require "rails_helper"

RSpec.describe Igdb::SyncGame do
  let(:fixture_root) { Rails.root.join("spec/fixtures/igdb") }
  let(:game_payload) { JSON.parse(File.read(fixture_root.join("7346_game.json"))) }
  let(:ttb_payload)  { JSON.parse(File.read(fixture_root.join("7346_time_to_beat.json"))) }
  let(:ext_payload)  { JSON.parse(File.read(fixture_root.join("7346_external_games.json"))) }

  let(:client) { instance_double(Igdb::Client) }
  let(:syncer) { described_class.new(client: client) }

  before do
    allow(client).to receive(:fetch_game).with(7346).and_return(game_payload)
    allow(client).to receive(:fetch_time_to_beat).with(7346).and_return(ttb_payload)
    allow(client).to receive(:fetch_external_games).with(7346).and_return(ext_payload)
  end

  describe "#call" do
    it "raises when the game has no igdb_id" do
      g = create(:game, igdb_id: nil)
      expect { syncer.call(g) }.to raise_error(ArgumentError)
    end

    it "populates every IGDB-sourced column" do
      g = create(:game, igdb_id: 7346, title: "placeholder")
      syncer.call(g)
      g.reload

      expect(g.title).to eq("The Legend of Zelda: Breath of the Wild")
      expect(g.igdb_slug).to eq("the-legend-of-zelda-breath-of-the-wild")
      expect(g.summary).to start_with("The Legend of Zelda")
      expect(g.cover_image_id).to eq("co1u7n")
      expect(g.release_date).to eq(Date.new(2017, 3, 3))
      expect(g.release_year).to eq(2017)
      expect(g.igdb_rating).to eq(BigDecimal("95.5"))
      expect(g.external_steam_app_id).to eq("1086940")
      # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — the
      # `external_gog_id` / `external_epic_id` columns are gone; only
      # `external_steam_app_id` survives. The mapper drops categories
      # 5 (GOG) + 26 (Epic) silently.
      expect(g.respond_to?(:external_gog_id)).to be(false)
      expect(g.respond_to?(:external_epic_id)).to be(false)
      expect(g.ttb_main_seconds).to eq(180_000)
    end

    it "preserves local-only columns" do
      platform = create(:platform, slug: "sync-game-spec-platform")
      g = create(:game,
                 igdb_id: 7346,
                 played_at: Date.new(2024, 1, 1),
                 notes: "my private notes",
                 hours_of_footage_manual: 12)
      # Phase 27 §1a — per-platform ownership lives in the join.
      g.game_platform_ownerships.create!(platform: platform)
      syncer.call(g)
      g.reload

      expect(g.owned_platforms).to include(platform)
      expect(g.played_at).to eq(Date.new(2024, 1, 1))
      expect(g.notes).to eq("my private notes")
      expect(g.hours_of_footage_manual).to eq(12)
    end

    it "stamps igdb_synced_at and clears last_sync_error" do
      g = create(:game, igdb_id: 7346, last_sync_error: "previous error")
      syncer.call(g)
      g.reload
      expect(g.igdb_synced_at).to be_within(5.seconds).of(Time.current)
      expect(g.last_sync_error).to be_nil
    end

    it "creates Genre rows for new genres" do
      g = create(:game, igdb_id: 7346)
      expect { syncer.call(g) }.to change(Genre, :count).by_at_least(1)
      expect(g.reload.genres.map(&:name)).to include("Adventure")
    end

    it "upserts (does NOT duplicate) existing Genre rows by igdb_id" do
      Genre.create!(igdb_id: 31, name: "Stale name", slug: "stale")
      g = create(:game, igdb_id: 7346)
      expect { syncer.call(g) }.not_to change { Genre.where(igdb_id: 31).count }
      expect(Genre.find_by(igdb_id: 31).name).to eq("Adventure")
    end

    it "replaces game_genres join rows on re-sync (delete-and-create)" do
      g = create(:game, igdb_id: 7346)
      pre_existing_genre = Genre.create!(igdb_id: 999_999, name: "Stale", slug: "stale")
      g.game_genres.create!(genre: pre_existing_genre)

      syncer.call(g)

      expect(g.reload.genres.map(&:igdb_id)).not_to include(999_999)
      expect(g.genres.map(&:igdb_id)).to include(31, 12)
    end

    # Phase 27 v2 spec 01 — re-pick `primary_genre_id` on every sync.
    # The `before_save :assign_primary_genre_if_blank` model hook only
    # sets the pointer when blank. A re-sync that swaps the genres set
    # (or drops every linked genre) must update the pointer too.
    describe "Phase 27 v2 spec 01 — primary_genre re-pick on every sync" do
      it "re-picks the alphabetical winner when IGDB swaps the genres set" do
        g = create(:game, igdb_id: 7346)
        # Pre-seed a stale pointer to a genre IGDB will drop on the
        # next sync (igdb_id 999_999 is not in the fixture payload).
        stale = Genre.create!(igdb_id: 999_999, name: "Zzz Stale", slug: "stale-rp1")
        g.game_genres.create!(genre: stale)
        g.update_column(:primary_genre_id, stale.id)

        syncer.call(g)

        # Fixture genres on `7346_game.json` include "Adventure"
        # (igdb_id 31) and "Role-playing (RPG)" (igdb_id 12).
        # "Adventure" wins by LOWER(name) ASC.
        adventure = Genre.find_by(igdb_id: 31)
        expect(adventure).not_to be_nil
        expect(g.reload.primary_genre_id).to eq(adventure.id)
        expect(g.primary_genre_id).not_to eq(stale.id)
      end

      it "writes primary_genre_id = nil when the post-sync genres set is empty" do
        # Override the fixture payload's genres list to an empty array.
        empty_payload = [ game_payload.first.merge("genres" => []) ]
        allow(client).to receive(:fetch_game).with(7346).and_return(empty_payload)

        adventure = Genre.create!(igdb_id: 31, name: "Adventure", slug: "adv-rp2")
        g = create(:game, igdb_id: 7346)
        g.game_genres.create!(genre: adventure)
        g.update_column(:primary_genre_id, adventure.id)

        syncer.call(g)

        expect(g.reload.primary_genre_id).to be_nil
      end

      it "is idempotent — a sync with an unchanged genres set lands the same pointer" do
        g = create(:game, igdb_id: 7346)
        syncer.call(g)
        first_pick = g.reload.primary_genre_id
        expect(first_pick).not_to be_nil

        syncer.call(g)
        expect(g.reload.primary_genre_id).to eq(first_pick)
      end

      it "fires re-pick AFTER sync_genres lands the new join rows (call order)" do
        # Assert via observed side-effect: the post-sync
        # `primary_genre_id` matches the picker's result over IGDB's
        # current genre set. If `re_assign_primary_genre` ran BEFORE
        # `sync_genres`, the picker would have seen the pre-sync set
        # (empty / stale) and either left the pointer nil or pointed
        # at the stale genre. The expected value here proves the
        # ordering: the post-sync alphabetical winner is "Adventure"
        # (igdb_id 31).
        g = create(:game, igdb_id: 7346)
        # Pre-seed an unrelated stale that would lose to "Adventure"
        # if both were in the set together — but stale should be GONE
        # post-sync because `sync_genres` runs first.
        early_alpha_stale = Genre.create!(igdb_id: 888_888, name: "aaa-stale", slug: "aaa-stale-ordered")
        g.game_genres.create!(genre: early_alpha_stale)
        g.update_column(:primary_genre_id, early_alpha_stale.id)

        syncer.call(g)

        # If the re-pick ran BEFORE sync_genres, the stale ("aaa-stale")
        # would still be in the join AND would win alphabetically over
        # "Adventure" — the assertion below would fail. The post-sync
        # adventure win proves sync_genres ran first.
        adventure = Genre.find_by(igdb_id: 31)
        expect(g.reload.primary_genre_id).to eq(adventure.id)
        # And the stale should have been deleted from the join.
        expect(g.genres.map(&:igdb_id)).not_to include(888_888)
      end
    end

    it "creates the right Company rows + role joins" do
      g = create(:game, igdb_id: 7346)
      syncer.call(g)
      g.reload

      expect(g.developers.map(&:name)).to contain_exactly("Nintendo EPD")
      expect(g.publishers.map(&:name)).to match_array([ "Nintendo EPD", "Nintendo" ])
    end

    it "rolls back the entire sync if a sub-step raises" do
      g = create(:game, igdb_id: 7346, title: "before")
      allow_any_instance_of(described_class).to receive(:sync_publishers).and_raise("boom")

      expect { syncer.call(g) }.to raise_error("boom")
      expect(g.reload.title).to eq("before")
      expect(g.igdb_synced_at).to be_nil
    end

    it "raises ValidationError + stamps last_sync_error when IGDB returns []" do
      allow(client).to receive(:fetch_game).with(7346).and_return([])
      g = create(:game, igdb_id: 7346)
      expect { syncer.call(g) }.to raise_error(Igdb::Client::ValidationError)
      expect(g.reload.last_sync_error).to include("igdb error")
    end

    it "last-write-wins on locally edited title" do
      g = create(:game, igdb_id: 7346, title: "MY EDITED TITLE")
      syncer.call(g)
      expect(g.reload.title).to eq("The Legend of Zelda: Breath of the Wild")
    end
  end

  # Phase 28 §01a — Multi-version grouping. The IGDB payload may carry
  # a `version_parent` integer (IGDB-side parent game id) and a
  # `version_title` string. The syncer pre-resolves the parent to a
  # local Game id (importing the parent first if needed) and stamps
  # `version_parent_id` on the edition.
  describe "Phase 28 §01a — version_parent resolution" do
    let(:base_payload) { game_payload.first }

    let(:edition_payload) do
      base_payload.merge(
        "id" => 9001,
        "name" => "Pragmata Deluxe Edition",
        "slug" => "pragmata-deluxe-edition",
        "version_parent" => 9000,
        "version_title" => "Deluxe"
      )
    end

    let(:parent_payload) do
      base_payload.merge(
        "id" => 9000,
        "name" => "Pragmata",
        "slug" => "pragmata"
      ).tap { |h| h.delete("version_parent") }
    end

    before do
      allow(client).to receive(:fetch_game).with(9001).and_return([ edition_payload ])
      allow(client).to receive(:fetch_game).with(9000).and_return([ parent_payload ])
      allow(client).to receive(:fetch_time_to_beat).with(any_args).and_return([])
      allow(client).to receive(:fetch_external_games).with(any_args).and_return([])
    end

    it "stamps version_parent_id when the parent already exists locally" do
      parent = create(:game, igdb_id: 9000, title: "Pragmata", igdb_synced_at: Time.current)
      edition = create(:game, igdb_id: 9001, title: "placeholder")
      syncer.call(edition)
      expect(edition.reload.version_parent_id).to eq(parent.id)
      expect(edition.version_title).to eq("Deluxe")
    end

    it "recursively imports the parent when not yet in DB" do
      edition = create(:game, igdb_id: 9001, title: "placeholder")
      expect { syncer.call(edition) }.to change(Game, :count).by(1)
      parent = Game.find_by(igdb_id: 9000)
      expect(parent).not_to be_nil
      expect(parent.title).to eq("Pragmata")
      expect(edition.reload.version_parent_id).to eq(parent.id)
    end

    it "leaves version_parent_id nil when the payload has no version_parent" do
      no_parent_payload = edition_payload.dup
      no_parent_payload.delete("version_parent")
      no_parent_payload.delete("version_title")
      allow(client).to receive(:fetch_game).with(9001).and_return([ no_parent_payload ])

      edition = create(:game, igdb_id: 9001, title: "placeholder")
      syncer.call(edition)
      expect(edition.reload.version_parent_id).to be_nil
    end

    it "is idempotent on re-import (no duplicate parent rows)" do
      create(:game, igdb_id: 9000, title: "Pragmata", igdb_synced_at: Time.current)
      edition = create(:game, igdb_id: 9001, title: "placeholder")
      syncer.call(edition)
      expect { syncer.call(edition) }.not_to change(Game, :count)
    end

    it "stops at the first primary when IGDB returns a chain" do
      grandparent_payload = parent_payload.merge("id" => 8999, "name" => "Pragmata Root")
      chain_parent_payload = parent_payload.merge("version_parent" => 8999)
      allow(client).to receive(:fetch_game).with(9000).and_return([ chain_parent_payload ])
      allow(client).to receive(:fetch_game).with(8999).and_return([ grandparent_payload ])

      edition = create(:game, igdb_id: 9001, title: "placeholder")
      # The resolver walks the chain up to the first primary and stops
      # there — it does NOT mirror the intermediate row locally. So one
      # row lands (the root primary).
      expect { syncer.call(edition) }.to change(Game, :count).by(1)
      root = Game.find_by(igdb_id: 8999)
      expect(edition.reload.version_parent_id).to eq(root.id)
    end
  end
end
