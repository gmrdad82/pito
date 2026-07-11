# frozen_string_literal: true

require "rails_helper"

RSpec.describe Event, type: :model do
  describe "KINDS" do
    it "includes all expected kinds" do
      expect(described_class::KINDS).to match_array(
        %w[echo system error enhanced thinking confirmation system_follow_up enhanced_follow_up confirmation_follow_up theme_diff ai]
      )
    end
  end

  describe "validations" do
    it "requires kind" do
      event = build(:event, kind: nil)
      expect(event).not_to be_valid
    end

    it "requires kind to be in KINDS" do
      event = build(:event, kind: "unknown")
      expect(event).not_to be_valid
      expect(event.errors[:kind]).to include("is not included in the list")
    end

    it "requires position" do
      event = build(:event, position: nil)
      expect(event).not_to be_valid
    end
  end

  describe ".next_position_for" do
    it "returns 1 when no events exist" do
      conversation = Conversation.create!
      expect(described_class.next_position_for(conversation)).to eq(1)
    end

    it "returns one more than the max position" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(position: 1, input_kind: :slash, input_text: "/help")
      conversation.events.create!(turn:, position: 1, kind: :echo, payload: {})
      conversation.events.create!(turn:, position: 2, kind: :system, payload: {})
      expect(described_class.next_position_for(conversation)).to eq(3)
    end
  end
end
