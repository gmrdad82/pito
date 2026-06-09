# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncVideosJob, type: :job do
  let!(:connection) { create(:youtube_connection) }
  let!(:channel)    { create(:channel, handle: "@pito", youtube_connection: connection) }

  before do
    allow(NightlyVideoSyncJob).to receive(:perform_now)
  end

  describe "#perform" do
    it "calls NightlyVideoSyncJob.perform_now for each scoped channel (specific ids)" do
      described_class.new.perform([ channel.id ], "@pito")
      expect(NightlyVideoSyncJob).to have_received(:perform_now).with(channel.id)
    end

    it "calls NightlyVideoSyncJob.perform_now for all connected channels when channel_ids is empty" do
      described_class.new.perform([], "all channels")
      expect(NightlyVideoSyncJob).to have_received(:perform_now).with(channel.id)
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
