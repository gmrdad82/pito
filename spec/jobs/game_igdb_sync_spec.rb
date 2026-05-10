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

    # Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
    describe "resyncing mutex" do
      it "flips resyncing true while SyncGame is running" do
        captured = nil
        allow(Igdb::SyncGame).to receive(:new).and_wrap_original do |orig, *args|
          syncer = orig.call(*args)
          allow(syncer).to receive(:call) do |g|
            captured = Game.find(g.id).resyncing?
            g
          end
          syncer
        end

        described_class.new.perform(game.id)
        expect(captured).to eq(true)
      end

      it "clears resyncing back to false after success" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call) { |_, g| g }
        described_class.new.perform(game.id)
        expect(game.reload.resyncing?).to eq(false)
      end

      it "clears resyncing back to false after a non-retryable error" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ValidationError.new("not found"))
        described_class.new.perform(game.id)
        expect(game.reload.resyncing?).to eq(false)
      end

      it "clears resyncing back to false even when a retryable error re-raises" do
        allow_any_instance_of(Igdb::SyncGame).to receive(:call)
          .and_raise(Igdb::Client::ServerError.new("500"))
        expect { described_class.new.perform(game.id) }.to raise_error(Igdb::Client::ServerError)
        expect(game.reload.resyncing?).to eq(false)
      end

      it "is a no-op when resyncing is already true (duplicate enqueue guard)" do
        game.update_column(:resyncing, true)
        expect_any_instance_of(Igdb::SyncGame).not_to receive(:call)
        described_class.new.perform(game.id)
        # Lock NOT released by an early-return — only the running job
        # releases the lock when it finishes.
        expect(game.reload.resyncing?).to eq(true)
      end
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
