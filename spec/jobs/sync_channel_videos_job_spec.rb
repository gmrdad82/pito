# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncChannelVideosJob, type: :job do
  let!(:connection) { create(:youtube_connection) }
  let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }
  let(:library)     { instance_double(Pito::Sync::VideoLibrary, sync: nil) }

  before do
    allow(ChannelSync).to receive(:perform_now)
    allow(::Pito::Sync::VideoLibrary).to receive(:new).and_return(library)
    allow(::Channel::Youtube::StatsFetcher).to receive(:call).and_return({
      subscriber_count: 2000,
      view_count:       100_000,
      last_synced_at:   Time.current
    })
    allow(::Pito::Stats).to receive(:set)
    allow_any_instance_of(::Channel).to receive(:update_columns)
  end

  describe "#perform" do
    it "calls ChannelSync.perform_now for each scoped channel" do
      described_class.new.perform([ channel.id ], "@pito")
      expect(ChannelSync).to have_received(:perform_now).with(channel.id)
    end

    it "runs Pito::Sync::VideoLibrary#sync for each scoped channel" do
      described_class.new.perform([ channel.id ], "@pito")
      expect(::Pito::Sync::VideoLibrary).to have_received(:new).with(channel)
      expect(library).to have_received(:sync)
    end

    it "calls StatsFetcher for each scoped channel" do
      described_class.new.perform([ channel.id ], "@pito")
      expect(::Channel::Youtube::StatsFetcher).to have_received(:call).with(channel)
    end

    it "syncs all connected channels when channel_ids is empty" do
      described_class.new.perform([], "all channels")
      expect(ChannelSync).to have_received(:perform_now).with(channel.id)
      expect(library).to have_received(:sync)
    end

    context "with a conversation_id" do
      let!(:conversation) { Conversation.singleton }

      it "emits a thinking indicator before the sync work" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

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

        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:resolve_thinking)
      end

      it "broadcasts a system event with an HTML intro body" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).with(
          hash_including(
            kind:    :system,
            payload: hash_including("body", "html" => true)
          )
        )
      end

      it "renders the scope_label as the shimmered subject in the intro" do
        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        event = conversation.events.where(kind: :system).last
        expect(event.payload["body"]).to include("@pito")
      end

      it "completes the turn" do
        broadcaster = instance_double(
          Pito::Stream::Broadcaster,
          emit: nil, emit_thinking: nil, resolve_thinking: nil, complete_turn: nil
        )
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:complete_turn)
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
          described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
          expect(broadcaster).to have_received(:emit).with(
            hash_including(kind: :error, payload: hash_including(text: anything))
          )
        end

        it "resolves the thinking indicator on error (no hung spinner)" do
          described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
          expect(broadcaster).to have_received(:resolve_thinking)
        end

        it "completes the turn on error" do
          described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
          expect(broadcaster).to have_received(:complete_turn)
        end

        it "does not re-raise (job handles the error gracefully)" do
          expect {
            described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)
          }.not_to raise_error
        end
      end
    end

    context "partial-failure isolation: one channel VideoLibrary sync raises" do
      # channel (outer let!, lower PK) is returned first by Postgres natural PK
      # order from ::Channel.where(id: …). channel_two (higher PK) is second.
      # VideoLibrary is NOT per-channel-rescued in this job; when channel_two's
      # sync raises the outer rescue catches it. channel was already synced.
      let!(:channel_two) do
        create(:channel, handle: "@beta", youtube_connection: create(:youtube_connection))
      end
      let(:failing_library) { instance_double(Pito::Sync::VideoLibrary) }

      before do
        allow(failing_library).to receive(:sync).and_raise(StandardError, "quota exceeded")
        allow(::Pito::Sync::VideoLibrary).to receive(:new).with(channel_two).and_return(failing_library)
      end

      it "still processes the first channel before the second one raises" do
        described_class.new.perform([ channel.id, channel_two.id ], "two channels")
        expect(library).to have_received(:sync)
      end

      it "does not re-raise when a channel VideoLibrary sync raises" do
        expect {
          described_class.new.perform([ channel.id, channel_two.id ], "two channels")
        }.not_to raise_error
      end
    end
  end
end
