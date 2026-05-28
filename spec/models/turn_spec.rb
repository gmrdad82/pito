# frozen_string_literal: true

require "rails_helper"

RSpec.describe Turn, type: :model do
  describe "validations" do
    it "is valid with slash input_kind" do
      turn = build(:turn, input_kind: "slash")
      expect(turn).to be_valid
    end

    it "is valid with chat input_kind" do
      turn = build(:turn, input_kind: "chat")
      expect(turn).to be_valid
    end

    it "is invalid with an unknown input_kind" do
      turn = build(:turn, input_kind: "unknown")
      expect(turn).not_to be_valid
      expect(turn.errors[:input_kind]).to include("is not included in the list")
    end

    it "requires input_text" do
      turn = build(:turn, input_text: nil)
      expect(turn).not_to be_valid
    end

    it "requires position" do
      turn = build(:turn, position: nil)
      expect(turn).not_to be_valid
    end
  end

  describe ".next_position_for" do
    it "returns 1 when no turns exist" do
      conversation = Conversation.create!
      expect(described_class.next_position_for(conversation)).to eq(1)
    end

    it "returns one more than the max position" do
      conversation = Conversation.create!
      conversation.turns.create!(position: 1, input_kind: "slash", input_text: "/help")
      conversation.turns.create!(position: 2, input_kind: "slash", input_text: "/test")
      expect(described_class.next_position_for(conversation)).to eq(3)
    end
  end
end
