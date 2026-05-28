# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation, type: :model do
  describe ".singleton" do
    it "creates a conversation when none exists" do
      expect { Conversation.singleton }.to change(described_class, :count).by(1)
    end

    it "returns the same record across calls" do
      first = Conversation.singleton
      second = Conversation.singleton
      expect(first).to eq(second)
    end

    it "does not create a new record when one already exists" do
      Conversation.singleton
      expect { Conversation.singleton }.not_to change(described_class, :count)
    end
  end
end
