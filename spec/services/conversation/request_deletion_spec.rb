# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation::RequestDeletion do
  let(:conversation) { Conversation.create!(title: "Unnamed test") }

  before do
    allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row)
  end

  it "marks the conversation as deleting" do
    described_class.call(conversation:)
    expect(conversation.reload.deleting_at).to be_present
  end

  it "broadcasts the global sidebar row (shimmering-dots placeholder)" do
    described_class.call(conversation:)
    expect(Pito::Stream::Broadcaster)
      .to have_received(:broadcast_global_conversation_row).with(conversation:)
  end

  it "enqueues the deletion cascade job once with the conversation id" do
    expect { described_class.call(conversation:) }
      .to have_enqueued_job(DeleteConversationJob).with(conversation.id)
  end

  it "returns the conversation" do
    expect(described_class.call(conversation:)).to eq(conversation)
  end

  it "is idempotent — a conversation already deleting enqueues no second job" do
    conversation.update!(deleting_at: Time.current)
    expect { described_class.call(conversation:) }
      .not_to have_enqueued_job(DeleteConversationJob)
  end
end
