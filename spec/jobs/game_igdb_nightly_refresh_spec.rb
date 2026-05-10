require "rails_helper"

RSpec.describe GameIgdbNightlyRefresh, type: :job do
  before do
    GameIgdbSync.clear
    allow_any_instance_of(described_class).to receive(:sleep) # avoid real waits
  end

  describe "#perform" do
    it "enqueues GameIgdbSync for stale synced games" do
      stale = create(:game, :stale)

      described_class.new.perform

      expect(GameIgdbSync.jobs.map { |j| j["args"].first }).to contain_exactly(stale.id)
    end

    it "does not enqueue for never-synced games" do
      _never = create(:game, igdb_synced_at: nil)
      described_class.new.perform
      expect(GameIgdbSync.jobs).to be_empty
    end

    it "does not enqueue for fresh synced games (within the 7-day window)" do
      _fresh = create(:game, :synced, igdb_synced_at: 1.day.ago)
      described_class.new.perform
      expect(GameIgdbSync.jobs).to be_empty
    end

    it "boundary check at exactly 7 days" do
      _just_inside = create(:game, :synced, igdb_synced_at: 7.days.ago + 1.minute)
      described_class.new.perform
      expect(GameIgdbSync.jobs).to be_empty
    end

    it "sleeps 0.3s between enqueues" do
      create(:game, :stale)
      create(:game, :stale)

      job = described_class.new
      expect(job).to receive(:sleep).with(0.3).at_least(:once)
      job.perform
    end

    it "is a no-op with zero stale games" do
      expect { described_class.new.perform }.not_to raise_error
      expect(GameIgdbSync.jobs).to be_empty
    end
  end

  describe "cron registration" do
    it "is registered in config/sidekiq_cron.yml at `0 3 * * *`" do
      schedule = YAML.load_file(Rails.root.join("config/sidekiq_cron.yml"))
      entry = schedule["game_igdb_nightly_refresh"]
      expect(entry).to be_present
      expect(entry["cron"]).to eq("0 3 * * *")
      expect(entry["class"]).to eq("GameIgdbNightlyRefresh")
    end
  end
end
