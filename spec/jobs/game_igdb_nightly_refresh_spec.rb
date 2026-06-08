# frozen_string_literal: true

require "rails_helper"

RSpec.describe GameIgdbNightlyRefresh, type: :job do
  def run!
    job = described_class.new
    allow(job).to receive(:sleep) # don't actually pace in tests
    job.perform
  end

  before { allow(GameIgdbSync).to receive(:perform_later) }

  it "enqueues a sync for a stale, synced, UPCOMING (unreleased) game" do
    game = create(:game, igdb_synced_at: 10.days.ago, release_year: nil)
    run!
    expect(GameIgdbSync).to have_received(:perform_later).with(game.id)
  end

  it "does NOT enqueue a RELEASED game (igdb data is final)" do
    released = create(:game, igdb_synced_at: 10.days.ago,
                             release_year: 2020, release_month: 3, release_day: 15)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_later).with(released.id)
  end

  it "does NOT enqueue a freshly-synced game (not stale)" do
    fresh = create(:game, igdb_synced_at: 1.day.ago, release_year: nil)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_later).with(fresh.id)
  end

  it "does NOT enqueue a never-synced game" do
    never = create(:game, igdb_synced_at: nil, release_year: nil)
    run!
    expect(GameIgdbSync).not_to have_received(:perform_later).with(never.id)
  end
end
