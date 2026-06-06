# frozen_string_literal: true

require "rails_helper"

RSpec.describe GameIgdbSync, type: :job do
  let(:game) { create(:game, igdb_id: 12_345) }

  let(:sync_game_double) { instance_double(Game::Igdb::SyncGame, call: game) }

  before do
    allow(Game::Igdb::SyncGame).to receive(:new).and_return(sync_game_double)
    # game.resyncing / update_column(:resyncing) references a column that
    # may not exist in the current schema; stub the DB-level operations so
    # the job logic is exercised without hitting a missing-column error.
    allow_any_instance_of(Game).to receive(:update_column).with(:resyncing, anything)
    allow(Game).to receive(:where).and_call_original
    allow(Game).to receive(:where).with(id: game.id).and_return(
      double(update_all: nil)
    )
  end

  describe "#perform" do
    it "delegates to Game::Igdb::SyncGame" do
      expect(sync_game_double).to receive(:call).with(anything)
      described_class.new.perform(game.id)
    end

    it "is a no-op when the game does not exist" do
      expect(sync_game_double).not_to receive(:call)
      expect { described_class.new.perform(0) }.not_to raise_error
    end

    context "when IGDB raises RateLimited" do
      let(:rate_limited_error) do
        Game::Igdb::Client::RateLimited.new(retry_after: 1)
      end

      before do
        allow(sync_game_double).to receive(:call).and_raise(rate_limited_error)
        allow_any_instance_of(described_class).to receive(:sleep)
      end

      it "re-raises so the job can be retried" do
        expect { described_class.new.perform(game.id) }.to raise_error(Game::Igdb::Client::RateLimited)
      end
    end

    context "when IGDB raises ValidationError" do
      before do
        allow(sync_game_double).to receive(:call).and_raise(
          Game::Igdb::Client::ValidationError, "IGDB has no game with id=12345"
        )
      end

      it "does NOT re-raise (non-retryable)" do
        expect { described_class.new.perform(game.id) }.not_to raise_error
      end
    end
  end
end
