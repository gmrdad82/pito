require "rails_helper"

# Phase 27 §1a — Sidekiq wrapper for Platforms::SyncFromIgdb.
RSpec.describe Platforms::SyncFromIgdbJob, type: :job do
  describe "#perform" do
    it "delegates to Platforms::SyncFromIgdb.call" do
      result = Platforms::SyncFromIgdb::Result.new(created: 1, updated: 2, total: 3)
      allow(Platforms::SyncFromIgdb).to receive(:call).and_return(result)

      returned = described_class.new.perform

      expect(Platforms::SyncFromIgdb).to have_received(:call)
      expect(returned).to eq(result)
    end

    it "logs the created / updated / total counts" do
      result = Platforms::SyncFromIgdb::Result.new(created: 4, updated: 5, total: 9)
      allow(Platforms::SyncFromIgdb).to receive(:call).and_return(result)
      allow(Rails.logger).to receive(:info)

      described_class.new.perform

      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/created=4 updated=5 total=9/))
    end

    it "lets IGDB errors surface so Sidekiq retries" do
      allow(Platforms::SyncFromIgdb).to receive(:call)
        .and_raise(Igdb::Client::ServerError.new("500"))

      expect {
        described_class.new.perform
      }.to raise_error(Igdb::Client::ServerError)
    end
  end

  describe "enqueueing" do
    it "lands on the default queue" do
      described_class.clear
      described_class.perform_async
      expect(described_class.jobs.size).to eq(1)
      expect(described_class.jobs.last["queue"]).to eq("default")
    end
  end

  describe "cron entry" do
    it "registers the platforms_sync_from_igdb cron line" do
      cron_yaml = YAML.safe_load(File.read(Rails.root.join("config/sidekiq_cron.yml")))
      entry = cron_yaml["platforms_sync_from_igdb"]
      expect(entry).to be_a(Hash)
      expect(entry["class"]).to eq("Platforms::SyncFromIgdbJob")
      expect(entry["cron"]).to match(/\A\d+ \d+ \* \* \d\z/)
    end
  end
end
