require "rails_helper"

RSpec.describe GameIgdbSync, type: :job do
  describe "#perform" do
    let!(:game) { create(:game, igdb_id: 7346) }

    it "invokes Igdb::SyncGame for the given game id" do
      syncer = instance_double(Igdb::SyncGame, call: game)
      allow(Igdb::SyncGame).to receive(:new).and_return(syncer)

      described_class.new.perform(game.id)
      expect(syncer).to have_received(:call).with(game)
    end

    it "is a no-op when the game does not exist" do
      expect { described_class.new.perform(0) }.not_to raise_error
    end

    it "raises (so Sidekiq retries) on RateLimited" do
      allow_any_instance_of(Igdb::SyncGame).to receive(:call)
        .and_raise(Igdb::Client::RateLimited.new(retry_after: 1))
      allow_any_instance_of(described_class).to receive(:sleep) # don't actually sleep
      expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::RateLimited)
    end

    it "raises (so Sidekiq retries) on ServerError" do
      allow_any_instance_of(Igdb::SyncGame).to receive(:call)
        .and_raise(Igdb::Client::ServerError.new("500"))
      expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::ServerError)
    end

    it "swallows ValidationError (no Sidekiq retry)" do
      allow_any_instance_of(Igdb::SyncGame).to receive(:call)
        .and_raise(Igdb::Client::ValidationError.new("not found"))
      expect { described_class.new.perform(game.id) }.not_to raise_error
    end
  end

  describe "Sidekiq options" do
    it "is enqueued on the default queue" do
      described_class.clear
      described_class.perform_async(123)
      expect(described_class.jobs.last["queue"]).to eq("default")
    end

    it "retries up to 5 times" do
      expect(described_class.sidekiq_options["retry"]).to eq(5)
    end
  end
end
