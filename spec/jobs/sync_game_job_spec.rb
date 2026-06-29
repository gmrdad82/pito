# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncGameJob, type: :job do
  let!(:game) { create(:game, title: "Ico") }

  before do
    allow(GameIgdbSync).to receive(:perform_now)
  end

  describe "#perform" do
    it "delegates to GameIgdbSync.perform_now with no conversation_id" do
      described_class.new.perform(game.id)
      expect(GameIgdbSync).to have_received(:perform_now).with(game.id)
    end

    it "is a no-op when the game does not exist" do
      expect { described_class.new.perform(0) }.not_to raise_error
      expect(GameIgdbSync).not_to have_received(:perform_now)
    end

    context "with a conversation_id" do
      let!(:conversation) { Conversation.singleton }

      before do
        allow(GameIgdbSync).to receive(:perform_now)
        allow(game).to receive(:reload).and_return(game)
      end

      it "emits a thinking indicator before calling GameIgdbSync" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(game.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit_thinking).with(
          hash_including(dictionary: :syncing)
        )
      end

      it "resolves the thinking indicator after the sync" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(game.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:resolve_thinking)
      end

      it "broadcasts a system event with an HTML intro body" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(game.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).with(
          hash_including(
            kind:    :system,
            payload: hash_including("body", "html" => true)
          )
        )
      end

      it "renders the game title as the shimmered subject in the intro" do
        described_class.new.perform(game.id, conversation_id: conversation.id)

        event = conversation.events.where(kind: :system).last
        expect(event.payload["body"]).to include("Ico")
      end

      it "completes the turn" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(game.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:complete_turn)
      end

      it "creates a turn for the sync" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        expect {
          described_class.new.perform(game.id, conversation_id: conversation.id)
        }.to change { conversation.turns.count }.by(1)
      end
    end
  end
end
