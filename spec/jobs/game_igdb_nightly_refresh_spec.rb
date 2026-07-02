# frozen_string_literal: true

require "rails_helper"

RSpec.describe GameIgdbNightlyRefresh, type: :job do
  before do
    # Stub out the heavy IGDB sync — perform_now returns nil by default
    allow(GameIgdbSync).to receive(:perform_now)
  end

  def run!
    described_class.new.perform
  end

  # ── bulk prefetch (0.9.0 Phase 3) ───────────────────────────────────────────

  it "bulk-prefetches every awaited game's IGDB + ttb rows and hands each sync its payload" do
    game   = create(:game, igdb_id: 4242, igdb_synced_at: 10.days.ago, release_year: nil)
    client = instance_double(Game::Igdb::Client)
    allow(Game::Igdb::Client).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_games_by_ids).with([ game.igdb_id ])
      .and_return([ { "id" => game.igdb_id, "name" => "Awaited" } ])
    allow(client).to receive(:fetch_time_to_beats_by_game_ids).with([ game.igdb_id ])
      .and_return([ { "game_id" => game.igdb_id, "hastily" => 3600 } ])

    run!

    expect(GameIgdbSync).to have_received(:perform_now).with(
      game.id,
      prefetched: {
        game_json: hash_including("id" => game.igdb_id),
        ttb_json:  [ hash_including("game_id" => game.igdb_id) ]
      }
    )
  end

  it "falls back to per-game fetches (prefetched: nil) when the bulk prefetch errors" do
    game   = create(:game, igdb_id: 4243, igdb_synced_at: 10.days.ago, release_year: nil)
    client = instance_double(Game::Igdb::Client)
    allow(Game::Igdb::Client).to receive(:new).and_return(client)
    allow(client).to receive(:fetch_games_by_ids).and_raise(Game::Igdb::Client::ServerError, "5xx")

    run!

    expect(GameIgdbSync).to have_received(:perform_now).with(game.id, prefetched: nil)
  end

  # ── scope filtering ─────────────────────────────────────────────────────────

  it "syncs a synced, awaited (TBA) game" do
    game = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(game.id, prefetched: anything)
  end

  it "does NOT sync a released game (day-precision past date — IGDB data is final)" do
    released = create(:game, igdb_synced_at: 10.days.ago,
                             release_year: 2020, release_month: 3, release_day: 15)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_now).with(released.id, prefetched: anything)
  end

  it "syncs a game whose date is only quarter-precision, even after the window opens (no fixed clear date)" do
    # Q-window lower bound is in the past, but no release_day — "sync until a
    # fixed clear date" (owner 2026-07-02): still awaited.
    game = create(:game, igdb_synced_at: 10.days.ago,
                         release_year: Date.current.year, release_quarter: 1)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(game.id, prefetched: anything)
  end

  it "syncs a game settled at game level whose platform row is only quarter-precision" do
    game = create(:game, igdb_synced_at: 10.days.ago,
                         release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "ps",
           release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "switch",
           release_year: Date.current.year, release_quarter: 1,
           release_month: nil, release_day: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(game.id, prefetched: anything)
  end

  it "syncs even a freshly-synced awaited game (nightly cadence — no stale gate, Item 51)" do
    fresh = create(:game, igdb_synced_at: 1.hour.ago, release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(fresh.id, prefetched: anything)
  end

  it "syncs a game released on one platform while another platform's date is still ahead (Item 51)" do
    game = create(:game, igdb_synced_at: 10.days.ago,
                         release_year: 2020, release_month: 3, release_day: 15)
    future = Date.current + 40.days
    create(:game_platform_release, game:, platform_token: "ps",
           release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "switch",
           release_year: future.year, release_month: future.month, release_day: future.day)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(game.id, prefetched: anything)
  end

  it "syncs a game released on one platform while another platform is TBA (Item 51)" do
    game = create(:game, igdb_synced_at: 10.days.ago,
                         release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "steam",
           release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "xbox", release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(game.id, prefetched: anything)
  end

  it "does NOT sync a game released on every platform" do
    game = create(:game, igdb_synced_at: 10.days.ago,
                         release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "ps",
           release_year: 2020, release_month: 3, release_day: 15)
    create(:game_platform_release, game:, platform_token: "steam",
           release_year: 2021, release_month: 6, release_day: 1)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_now).with(game.id, prefetched: anything)
  end

  it "does NOT sync a never-synced game" do
    never = create(:game, igdb_synced_at: nil, release_year: nil)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_now).with(never.id, prefetched: anything)
  end

  # ── no chat broadcast ────────────────────────────────────────────────────────

  it "does NOT pass a conversation_id to GameIgdbSync (no chat broadcast)" do
    create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(Integer, prefetched: anything)
    expect(GameIgdbSync).not_to have_received(:perform_now).with(anything, conversation_id: anything)
  end

  # ── Notification creation — conditional ─────────────────────────────────────

  # (a) changed-only → notification created
  it "(a) creates ONE Notification when games were updated" do
    game = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)

    # Simulate a DB write by advancing updated_at after perform_now is called
    allow(GameIgdbSync).to receive(:perform_now) do |id|
      Game.where(id: id).update_all(updated_at: Time.current + 1.second) # rubocop:disable Rails/SkipsModelValidations
    end

    expect { run! }.to change(Notification, :count).by(1)
  end

  # (b) failure → notification created
  it "(b) creates ONE Notification when at least one game fails" do
    game = create(:game, title: "Broken Game", igdb_synced_at: 10.days.ago, release_year: nil)
    allow(GameIgdbSync).to receive(:perform_now).with(game.id, prefetched: anything).and_raise(RuntimeError, "boom")

    expect { run! }.to change(Notification, :count).by(1)
    msg = Notification.last.message
    expect(msg).to include("Broken Game")
    expect(msg).to include("boom")
  end

  # (c) all-quiet, nothing releasing → NO notification
  it "(c) creates NO Notification when nothing changed, no failures, nothing releasing within 30 days" do
    # A stale upcoming game exists but sync produces no change and no failure
    create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    # GameIgdbSync is stubbed to return nil (no write) → updated_at does not advance

    expect { run! }.not_to change(Notification, :count)
  end

  # (c) also: completely empty scope → no notification
  it "(c) creates NO Notification when there are no awaited games at all" do
    expect { run! }.not_to change(Notification, :count)
  end

  # (d) the date-less "releasing within 30 days" summary was removed from
  # this job — dated countdowns are now ReleaseCountdownJob's responsibility.
  # A soon-releasing game with 0 changed / 0 failed is therefore a quiet run.
  it "(d) creates NO Notification merely because a game releases within 30 days" do
    future_date = Date.current + 15.days
    create(:game,
           igdb_synced_at: 10.days.ago,
           release_year:   future_date.year,
           release_month:  future_date.month,
           release_day:    future_date.day)
    # Sync stub returns nil — no DB change, no failure

    expect { run! }.not_to change(Notification, :count)
  end

  # (e) game releasing in 60 days → NOT in releasing_30d → no notification (assuming no other activity)
  it "(e) does NOT create a Notification for a game releasing in 60 days when nothing else changed" do
    far_date = Date.current + 60.days
    create(:game,
           igdb_synced_at: 10.days.ago,
           release_year:   far_date.year,
           release_month:  far_date.month,
           release_day:    far_date.day)
    # Sync stub returns nil — no DB change, no failure, not within 30 days

    expect { run! }.not_to change(Notification, :count)
  end

  # ── failure handling ─────────────────────────────────────────────────────────

  it "continues syncing other games when one raises" do
    game1 = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    game2 = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)

    call_count = 0
    allow(GameIgdbSync).to receive(:perform_now) do |id|
      call_count += 1
      raise RuntimeError, "IGDB exploded" if id == game1.id
    end

    expect { run! }.not_to raise_error
    expect(call_count).to eq(2)
  end

  it "Notification message includes failure info when a game fails" do
    game = create(:game, title: "Exploding Game", igdb_synced_at: 10.days.ago, release_year: nil)
    allow(GameIgdbSync).to receive(:perform_now).with(game.id, prefetched: anything).and_raise(RuntimeError, "boom")

    run!
    msg = Notification.last.message
    expect(msg).to include("Exploding Game")
    expect(msg).to include("boom")
  end

  # ── edge cases ────────────────────────────────────────────────────────────────

  it "lists ALL three failures in the notification when multiple games raise" do
    game1 = create(:game, title: "Alpha Game", igdb_synced_at: 10.days.ago, release_year: nil)
    game2 = create(:game, title: "Beta Game",  igdb_synced_at: 10.days.ago, release_year: nil)
    game3 = create(:game, title: "Gamma Game", igdb_synced_at: 10.days.ago, release_year: nil)

    allow(GameIgdbSync).to receive(:perform_now).with(game1.id, prefetched: anything).and_raise(RuntimeError, "err alpha")
    allow(GameIgdbSync).to receive(:perform_now).with(game2.id, prefetched: anything).and_raise(RuntimeError, "err beta")
    allow(GameIgdbSync).to receive(:perform_now).with(game3.id, prefetched: anything).and_raise(RuntimeError, "err gamma")

    expect { run! }.to change(Notification, :count).by(1)

    msg = Notification.last.message
    expect(msg).to include("Alpha Game")
    expect(msg).to include("Beta Game")
    expect(msg).to include("Gamma Game")
    expect(msg).to include("err alpha")
    expect(msg).to include("err beta")
    expect(msg).to include("err gamma")
  end

  it "visits every game, and notification reflects both changed titles and failures in a mixed run" do
    good1 = create(:game, title: "Good One",  igdb_synced_at: 10.days.ago, release_year: nil)
    good2 = create(:game, title: "Good Two",  igdb_synced_at: 10.days.ago, release_year: nil)
    bad1  = create(:game, title: "Bad Game",  igdb_synced_at: 10.days.ago, release_year: nil)

    allow(GameIgdbSync).to receive(:perform_now) do |id|
      if id == bad1.id
        raise RuntimeError, "network timeout"
      else
        Game.where(id: id).update_all(updated_at: Time.current + 1.second) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    expect { run! }.not_to raise_error

    # All three games must be visited regardless of the failure
    expect(GameIgdbSync).to have_received(:perform_now).exactly(3).times

    msg = Notification.last.message
    # Changed games appear in the updated-titles section
    expect(msg).to include("Good One")
    expect(msg).to include("Good Two")
    # Failed game appears in the failures section
    expect(msg).to include("Bad Game")
    expect(msg).to include("network timeout")
  end
end
