# frozen_string_literal: true

require "rails_helper"

RSpec.describe Conversation, type: :model do
  subject(:conversation) { build(:conversation) }

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:uuid).ignoring_case_sensitivity }

    it "validates uniqueness of uuid" do
      first = create(:conversation)
      second = build(:conversation, uuid: first.uuid)
      expect(second).not_to be_valid
      expect(second.errors[:uuid]).to include("has already been taken")
    end
  end

  describe "uuid generation" do
    it "sets a uuid before creation" do
      conv = create(:conversation)
      expect(conv.uuid).to be_present
      expect(conv.uuid).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "preserves an explicitly assigned lowercase uuid" do
      custom_uuid = "550e8400-e29b-41d4-a716-446655440000"
      conv = create(:conversation, uuid: custom_uuid)
      expect(conv.uuid).to eq(custom_uuid)
    end

    it "downcases an uppercased uuid" do
      upper = "550E8400-E29B-41D4-A716-446655440000"
      conv  = create(:conversation, uuid: upper)
      expect(conv.uuid).to eq(upper.downcase)
    end
  end

  describe "#to_param" do
    it "returns the uuid" do
      conv = create(:conversation)
      expect(conv.to_param).to eq(conv.uuid)
    end
  end

  describe "#display_name" do
    it "returns the title when present" do
      conv = build(:conversation, title: "My Chat")
      expect(conv.display_name).to eq("My Chat")
    end

    it "returns 'Unnamed N' when title is nil" do
      conv = create(:conversation, title: nil)
      expect(conv.display_name).to eq("Unnamed #{conv.id}")
    end
  end

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
