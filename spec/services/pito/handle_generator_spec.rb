# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::HandleGenerator, type: :service do
  let(:conversation) { Conversation.create! }

  describe ".call" do
    it "returns a handle matching word-digits format" do
      handle = described_class.call(conversation)
      expect(handle).to match(/\A[a-z]+-\d{4}\z/)
    end

    it "uses a Greek word" do
      handle = described_class.call(conversation)
      word = handle.split("-").first
      expect(Pito::HandleGenerator::GREEK_WORDS).to include(word)
    end

    it "returns a handle unique within the conversation" do
      first  = described_class.call(conversation)
      second = described_class.call(conversation)
      # They may be equal by chance but the generator avoids repeats
      # when the first is already taken — inject a conflict to test.
      turn = conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 1)
      Event.create_with_position!(
        conversation:, turn:, kind: "confirmation",
        payload: { confirmation_handle: first }
      )
      non_conflict = described_class.call(conversation)
      expect(non_conflict).not_to eq(first)
    end
  end

  describe "GREEK_WORDS" do
    it "has 24 entries (alpha…omega)" do
      expect(Pito::HandleGenerator::GREEK_WORDS.size).to eq(24)
    end

    it "starts with alpha and ends with omega" do
      expect(Pito::HandleGenerator::GREEK_WORDS.first).to eq("alpha")
      expect(Pito::HandleGenerator::GREEK_WORDS.last).to eq("omega")
    end
  end
end
