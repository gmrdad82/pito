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

  # ── no chat broadcast ────────────────────────────────────────────────────────

  it "does NOT pass a conversation_id to GameIgdbSync (no chat broadcast)" do
    create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_now).with(Integer)
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
    allow(GameIgdbSync).to receive(:perform_now).with(game.id).and_raise(RuntimeError, "boom")

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
  it "(c) creates NO Notification when there are no stale upcoming games at all" do
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
    allow(GameIgdbSync).to receive(:perform_now).with(game.id).and_raise(RuntimeError, "boom")

    run!
    msg = Notification.last.message
    expect(msg).to include("Exploding Game")
    expect(msg).to include("boom")
  end
end
