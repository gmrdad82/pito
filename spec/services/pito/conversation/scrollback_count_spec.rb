# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Conversation::ScrollbackCount, type: :service do
  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(input_kind: :chat, input_text: "hi", position: 1) }

  # Positions: echo@1, thinking@2, system@3, echo@4
  # Pivot used in most examples: position 3 (the system event)
  before do
    Event.create!(conversation:, turn:, kind: "echo",    position: 1, payload: {})
    Event.create!(conversation:, turn:, kind: "thinking", position: 2, payload: {})
    Event.create!(conversation:, turn:, kind: "system",  position: 3, payload: {})
    Event.create!(conversation:, turn:, kind: "echo",    position: 4, payload: {})
  end

  describe ".around" do
    subject(:result) { described_class.around(conversation:, position: 3) }

    it "counts non-thinking events strictly before the position" do
      # echo@1 qualifies; thinking@2 is excluded; system@3 is the pivot (excluded)
      expect(result[:before]).to eq(1)
    end

    it "counts non-thinking events strictly after the position" do
      # echo@4 qualifies; system@3 is the pivot (excluded)
      expect(result[:after]).to eq(1)
    end

    it "excludes thinking events from the before count" do
      # Without the thinking filter, before would be 2 (echo@1 + thinking@2)
      expect(result[:before]).not_to eq(2)
    end

    it "returns an Integer for both keys" do
      expect(result[:before]).to be_a(Integer)
      expect(result[:after]).to be_a(Integer)
    end

    context "at position 0 (before all events)" do
      subject(:result) { described_class.around(conversation:, position: 0) }

      it "returns 0 before" do
        expect(result[:before]).to eq(0)
      end

      it "counts all non-thinking events after" do
        # echo@1, system@3, echo@4 = 3 (thinking@2 excluded)
        expect(result[:after]).to eq(3)
      end
    end

    context "at the last position (after all events)" do
      subject(:result) { described_class.around(conversation:, position: 5) }

      it "counts all non-thinking events before" do
        # echo@1, system@3, echo@4 = 3
        expect(result[:before]).to eq(3)
      end

      it "returns 0 after" do
        expect(result[:after]).to eq(0)
      end
    end
  end
end
