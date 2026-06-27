# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeleteConversationJob, type: :job do
  let!(:conversation) { create(:conversation, :named, deleting_at: Time.current) }

  it "destroys the conversation" do
    expect {
      described_class.perform_now(conversation.id)
    }.to change(Conversation, :count).by(-1)
  end

  it "destroys dependent turns and events" do
    turn = create(:turn, conversation: conversation, position: 1)
    create(:event, conversation: conversation, turn: turn)
    expect {
      described_class.perform_now(conversation.id)
    }.to change(Turn, :count).by(-1).and change(Event, :count).by(-1)
  end

  it "broadcasts the row removal on pito:global" do
    allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row_removed)
    described_class.perform_now(conversation.id)
    expect(Pito::Stream::Broadcaster).to have_received(:broadcast_global_conversation_row_removed)
      .with(uuid: conversation.uuid)
  end

  it "is a no-op for a missing id" do
    expect { described_class.perform_now(999_999) }.not_to raise_error
  end

  context "on failure" do
    before { allow_any_instance_of(::Conversation).to receive(:destroy!).and_raise(StandardError, "boom") }

    it "clears deleting_at so the normal row reappears (delete did not happen)" do
      described_class.perform_now(conversation.id)
      expect(conversation.reload.deleting_at).to be_nil
      expect(Conversation.exists?(conversation.id)).to be(true)
    end

    it "re-broadcasts the normal row" do
      allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row)
      described_class.perform_now(conversation.id)
      expect(Pito::Stream::Broadcaster).to have_received(:broadcast_global_conversation_row)
    end
  end
end
