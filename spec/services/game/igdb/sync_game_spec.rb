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

  # Platforms are owner-editable; an IGDB re-sync must not clobber them.
  it "preserves owner-set platforms on re-sync (does NOT overwrite with IGDB's list)" do
    game.update!(platforms: [ "PlayStation 5", "Steam Deck" ])
    described_class.new(client: client).call(game)
    expect(game.reload.platforms).to eq([ "PlayStation 5", "Steam Deck" ])
  end

  it "seeds platforms from IGDB when the game has none yet (initial import)" do
    game.update!(platforms: [])
    described_class.new(client: client).call(game)
    expect(game.reload.platforms).to eq([ "PC (Microsoft Windows)", "Nintendo Switch" ])
  end

  it "preserves owner-set price and footage_hours on re-sync" do
    game.update!(price: 49.99, footage_hours: 12.5)
    described_class.new(client: client).call(game)
    expect(game.reload.price.to_f).to eq(49.99)
    expect(game.footage_hours.to_f).to eq(12.5)
  end

  it "enqueues the Voyage index after sync" do
    described_class.new(client: client).call(game)
    expect(GameVoyageIndexJob).to have_received(:perform_later).with(game.id)
  end

  describe "idempotent re-sync (E11 — false nightly \"updated\" flags)" do
    include ActiveSupport::Testing::TimeHelpers
    # The nightly refresh detects change by comparing game.updated_at before and
    # after the sync. A re-sync with IDENTICAL IGDB data must therefore leave
    # updated_at untouched — the unconditional update! calls that re-stamped
    # every game every night ("checked 60, updated 60") are the E11 root cause.
    it "does not advance game.updated_at when IGDB returns identical data" do
      described_class.new(client: client).call(game)
      stamp = game.reload.updated_at

      travel 1.hour do
        described_class.new(client: client).call(game)
      end

      expect(game.reload.updated_at).to eq(stamp)
    end

    it "still stamps igdb_synced_at on every sync (bookkeeping, touch-free)" do
      described_class.new(client: client).call(game)
      first = game.reload.igdb_synced_at

      travel 1.hour do
        described_class.new(client: client).call(game)
      end

      expect(game.reload.igdb_synced_at).to be > first
    end

    it "advances updated_at when a release date genuinely changes" do
      # Seed with real release dates first (the base fixture carries none).
      seeded = game_json.merge(
        "release_dates" => [
          { "platform" => { "name" => "PlayStation 5" }, "category" => 0, "y" => 2026, "m" => 7, "d" => 31 }
        ]
      )
      allow(client).to receive(:fetch_game).with(1020).and_return([ seeded ])
      described_class.new(client: client).call(game)
      stamp = game.reload.updated_at

      moved = seeded.deep_dup
      moved["release_dates"].each { |rd| rd["y"] = 2031 if rd["y"] }
      allow(client).to receive(:fetch_game).with(1020).and_return([ moved ])

      travel 1.hour do
        described_class.new(client: client).call(game)
      end

      expect(game.reload.updated_at).to be > stamp
    end
  end

  describe "per-platform release dates (Item 24)" do
    let(:releases_json) do
      game_json.merge(
        "release_dates" => [
          { "platform" => { "name" => "PlayStation 5" },          "category" => 0, "y" => 2026, "m" => 7, "d" => 31 },
          { "platform" => { "name" => "PC (Microsoft Windows)" }, "category" => 0, "y" => 2026, "m" => 7, "d" => 31 },
          { "platform" => { "name" => "Nintendo Switch" },        "category" => 5, "y" => 2026 },                       # Q3
          { "platform" => { "name" => "Google Stadia" },          "category" => 0, "y" => 2026, "m" => 1, "d" => 1 }    # dropped
        ]
      )
    end

    before { allow(client).to receive(:fetch_game).with(1020).and_return([ releases_json ]) }

    it "creates one platform_release row per recognised token (Stadia dropped)" do
      described_class.new(client: client).call(game)
      expect(game.platform_releases.pluck(:platform_token)).to contain_exactly("ps", "steam", "switch")
    end

    it "stores the per-platform components (day for PS, quarter for Switch)" do
      described_class.new(client: client).call(game)
      ps = game.platform_releases.find_by(platform_token: "ps")
      expect([ ps.release_year, ps.release_month, ps.release_day ]).to eq([ 2026, 7, 31 ])
      sw = game.platform_releases.find_by(platform_token: "switch")
      expect([ sw.release_year, sw.release_quarter ]).to eq([ 2026, 3 ])
    end

    it "derives games.release_date as the earliest across platforms (Switch Q3 → 2026-07-01)" do
      described_class.new(client: client).call(game)
      expect(game.reload.release_date).to eq(Date.new(2026, 7, 1))
    end

    it "drops platform_release rows for platforms absent on a later re-sync" do
      described_class.new(client: client).call(game)
      expect(game.platform_releases.count).to eq(3)

      allow(client).to receive(:fetch_game).with(1020).and_return([
        game_json.merge("release_dates" => [
          { "platform" => { "name" => "PlayStation 5" }, "category" => 0, "y" => 2026, "m" => 7, "d" => 31 }
        ])
      ])
      described_class.new(client: client).call(game)
      expect(game.platform_releases.pluck(:platform_token)).to eq([ "ps" ])
    end
  end
end
