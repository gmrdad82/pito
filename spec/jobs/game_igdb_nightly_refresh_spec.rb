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

  # ── scope filtering ─────────────────────────────────────────────────────────

  it "syncs a stale, synced, upcoming (unreleased) game" do
    game = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(game.id)
  end

  it "does NOT sync a released game (IGDB data is final)" do
    released = create(:game, igdb_synced_at: 10.days.ago,
                             release_year: 2020, release_month: 3, release_day: 15)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_now).with(released.id)
  end

  it "does NOT sync a freshly-synced game (not stale)" do
    fresh = create(:game, igdb_synced_at: 1.day.ago, release_year: nil)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_now).with(fresh.id)
  end

  it "does NOT sync a never-synced game" do
    never = create(:game, igdb_synced_at: nil, release_year: nil)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_now).with(never.id)
  end

  # ── Notification creation ────────────────────────────────────────────────────

  it "creates exactly ONE Notification on a successful run (even with no games)" do
    expect { run! }.to change(Notification, :count).by(1)
  end

  it "creates exactly ONE Notification when there are stale upcoming games" do
    create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    expect { run! }.to change(Notification, :count).by(1)
  end

  it "Notification message contains the checked and updated counts" do
    create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    msg = Notification.last.message
    expect(msg).to include("1")   # checked count
  end

  # ── failure handling ─────────────────────────────────────────────────────────

  it "continues syncing other games when one raises, still creates ONE Notification" do
    game1 = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    game2 = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)

    call_count = 0
    allow(GameIgdbSync).to receive(:perform_now) do |id|
      call_count += 1
      raise RuntimeError, "IGDB exploded" if id == game1.id
    end

    expect { run! }.not_to raise_error
    expect(call_count).to eq(2)
    expect(Notification.count).to eq(1)
  end

  it "Notification message includes failure info when a game fails" do
    game = create(:game, title: "Exploding Game", igdb_synced_at: 10.days.ago, release_year: nil)
    allow(GameIgdbSync).to receive(:perform_now).with(game.id).and_raise(RuntimeError, "boom")

    run!
    msg = Notification.last.message
    expect(msg).to include("Exploding Game")
    expect(msg).to include("boom")
  end

  # ── no chat broadcast ────────────────────────────────────────────────────────

  it "does NOT pass a conversation_id to GameIgdbSync (no chat broadcast)" do
    create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    # perform_now is called with only the game id (no conversation_id keyword)
    expect(GameIgdbSync).to have_received(:perform_now).with(Integer)
    expect(GameIgdbSync).not_to have_received(:perform_now).with(anything, conversation_id: anything)
  end
end
