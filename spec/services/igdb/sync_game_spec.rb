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
      expect(g.external_gog_id).to eq("gog-app-id-1234")
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
end
