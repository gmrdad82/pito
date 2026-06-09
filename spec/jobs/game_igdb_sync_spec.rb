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

  # ── BUG B: chat-initiated resync broadcasts detail + enhanced ─────────────────

  describe "#perform with conversation_id (chat-initiated resync)" do
    let(:conversation) { Conversation.create! }

    before do
      # Stub update_column on game reload to avoid missing-column errors
      allow(game).to receive(:reload).and_return(game)

      # Stub VoyageIndexer
      allow(::Game::VoyageIndexer).to receive(:call)

      # Stub DetailMessage
      allow(Pito::MessageBuilder::Game::Detail).to receive(:call)
        .and_return({ "body" => "<div>detail</div>", "html" => true })

      # Stub broadcaster cable writes
      allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:broadcast_event)
      allow_any_instance_of(Pito::Stream::Broadcaster).to receive(:complete_turn)
    end

    it "creates a turn in the conversation" do
      expect {
        described_class.new.perform(game.id, conversation_id: conversation.id)
      }.to change { conversation.turns.count }.by(1)
    end

    it "broadcasts a detail (system) event into the conversation" do
      described_class.new.perform(game.id, conversation_id: conversation.id)
      expect(conversation.events.where(kind: "system").count).to eq(1)
    end

    it "broadcasts an enhanced event into the conversation" do
      described_class.new.perform(game.id, conversation_id: conversation.id)
      expect(conversation.events.where(kind: "enhanced").count).to eq(1)
    end

    it "calls Game::VoyageIndexer to reindex before emitting" do
      expect(::Game::VoyageIndexer).to receive(:call).with(game)
      described_class.new.perform(game.id, conversation_id: conversation.id)
    end

    context "when IGDB raises ValidationError (sync failed)" do
      before do
        allow(sync_game_double).to receive(:call).and_raise(
          Game::Igdb::Client::ValidationError, "IGDB has no game with id=12345"
        )
      end

      it "does NOT create chat events when the sync failed" do
        described_class.new.perform(game.id, conversation_id: conversation.id)
        expect(conversation.events.count).to eq(0)
      end
    end

    context "when conversation_id is nil (page-path resync)" do
      it "does NOT create any chat events" do
        expect {
          described_class.new.perform(game.id, conversation_id: nil)
        }.not_to change { Event.count }
      end

      it "still syncs the game" do
        expect(sync_game_double).to receive(:call)
        described_class.new.perform(game.id, conversation_id: nil)
      end
    end
  end
end
