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

      it "broadcasts a summary system event to the conversation" do
        broadcaster = instance_double(Pito::Stream::Broadcaster, emit: nil, complete_turn: nil)
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform([ channel.id ], "@pito", conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).with(
          hash_including(kind: :system, payload: hash_including("text"))
        )
        expect(broadcaster).to have_received(:complete_turn)
      end
    end
  end
end
