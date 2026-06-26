# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation::Rename do
  let(:conversation) { Conversation.create!(title: "Untitled") }

  it "updates the conversation title" do
    described_class.call(conversation:, title: "My Channel")
    expect(conversation.reload.title).to eq("My Channel")
  end

  it "returns the conversation" do
    expect(described_class.call(conversation:, title: "X")).to eq(conversation)
  end

  it "broadcasts the chatbox conversation name and the global sidebar row" do
    broadcaster = instance_double(Pito::Stream::Broadcaster, broadcast_conversation_name: nil)
    allow(Pito::Stream::Broadcaster).to receive(:new).with(conversation:).and_return(broadcaster)
    allow(Pito::Stream::Broadcaster).to receive(:broadcast_global_conversation_row)

    described_class.call(conversation:, title: "Named Now")

    expect(broadcaster).to have_received(:broadcast_conversation_name)
    expect(Pito::Stream::Broadcaster).to have_received(:broadcast_global_conversation_row).with(conversation:)
  end
end
