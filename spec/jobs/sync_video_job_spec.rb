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

      it "broadcasts a summary system event to the conversation" do
        broadcaster = instance_double(Pito::Stream::Broadcaster, emit: nil, complete_turn: nil)
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        described_class.new.perform(video.id, conversation_id: conversation.id)

        expect(broadcaster).to have_received(:emit).with(
          hash_including(kind: :system, payload: hash_including("text"))
        )
        expect(broadcaster).to have_received(:complete_turn)
      end

      it "creates a turn for the sync" do
        broadcaster = instance_double(Pito::Stream::Broadcaster, emit: nil, complete_turn: nil)
        allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)

        expect {
          described_class.new.perform(video.id, conversation_id: conversation.id)
        }.to change { conversation.turns.count }.by(1)
      end
    end
  end
end
