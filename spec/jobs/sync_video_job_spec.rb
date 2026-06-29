# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncVideoJob, type: :job do
  let!(:connection) { create(:youtube_connection) }
  let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video)      { create(:video, channel: channel, title: "Walkthrough Part 1", youtube_video_id: "yt_abc") }

  describe "#perform" do
    before do
      allow_any_instance_of(::Channel::Youtube::Client).to receive(:videos_list).and_return({ items: [] })
    end

    it "is a no-op when the video does not exist" do
      expect { described_class.new.perform(0) }.not_to raise_error
    end

    it "is a no-op when the channel has no youtube_connection" do
      orphan_channel = create(:channel)
      orphan_video   = create(:video, channel: orphan_channel, title: "Orphan")
      expect { described_class.new.perform(orphan_video.id) }.not_to raise_error
    end

    context "with a conversation_id" do
      let!(:conversation) { Conversation.singleton }

      it "emits a thinking indicator before fetching from YouTube" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(video.id, conversation_id: conversation.id)

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

        described_class.new.perform(video.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:resolve_thinking)
      end

      it "broadcasts a system event with an HTML intro body" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(video.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).with(
          hash_including(
            kind:    :system,
            payload: hash_including("body", "html" => true)
          )
        )
      end

      it "renders the video title as the shimmered subject in the intro" do
        described_class.new.perform(video.id, conversation_id: conversation.id)

        event = conversation.events.where(kind: :system).last
        expect(event.payload["body"]).to include("Walkthrough Part 1")
      end

      it "completes the turn" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(video.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:complete_turn)
      end

      it "creates a turn for the sync" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        expect {
          described_class.new.perform(video.id, conversation_id: conversation.id)
        }.to change { conversation.turns.count }.by(1)
      end

      context "when the job raises an unexpected error mid-flight" do
        # Trigger the outer rescue by having the success-path :system emit raise.
        # The :error emit in the rescue block must still succeed.
        let(:broadcaster) do
          instance_double(
            Pito::Stream::Broadcaster,
            emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
          )
        end

        before do
          allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
          allow(broadcaster).to receive(:emit)
            .with(hash_including(kind: :system)).and_raise(StandardError, "cable failure")
          allow(broadcaster).to receive(:emit)
            .with(hash_including(kind: :error)).and_return(nil)
        end

        it "emits an :error event into the conversation" do
          described_class.new.perform(video.id, conversation_id: conversation.id)
          expect(broadcaster).to have_received(:emit).with(
            hash_including(kind: :error, payload: hash_including(text: anything))
          )
        end

        it "resolves the thinking indicator on error (no hung spinner)" do
          described_class.new.perform(video.id, conversation_id: conversation.id)
          expect(broadcaster).to have_received(:resolve_thinking)
        end

        it "completes the turn on error" do
          described_class.new.perform(video.id, conversation_id: conversation.id)
          expect(broadcaster).to have_received(:complete_turn)
        end

        it "does not re-raise (job handles the error gracefully)" do
          expect {
            described_class.new.perform(video.id, conversation_id: conversation.id)
          }.not_to raise_error
        end
      end
    end
  end
end
