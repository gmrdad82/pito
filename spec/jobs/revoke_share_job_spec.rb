# frozen_string_literal: true

require "rails_helper"

RSpec.describe RevokeShareJob, type: :job do
  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :chat, input_text: "hi") }
  let(:event) { Event.create_with_position!(conversation:, turn:, kind: :system, payload: { text: "hello" }) }
  let!(:share) { create(:share, conversation:, event:) }

  describe "#perform" do
    it "destroys the Share record for the given event_id" do
      expect { described_class.new.perform(event.id) }.to change(Share, :count).by(-1)
    end

    it "is idempotent when the share is already gone" do
      share.destroy!
      expect { described_class.new.perform(event.id) }.not_to raise_error
      expect(Share.count).to eq(0)
    end

    it "does not raise when no share exists for the event_id" do
      turn2 = conversation.turns.create!(position: 2, input_kind: :chat, input_text: "x")
      event2 = Event.create_with_position!(conversation:, turn: turn2, kind: :system, payload: { text: "b" })
      expect { described_class.new.perform(event2.id) }.not_to raise_error
    end
  end
end
