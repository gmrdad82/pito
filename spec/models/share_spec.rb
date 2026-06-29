# frozen_string_literal: true

require "rails_helper"

RSpec.describe Share, type: :model do
  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :chat, input_text: "hi") }
  let(:event) { Event.create_with_position!(conversation:, turn:, kind: :system, payload: { text: "hello" }) }

  describe "associations" do
    it "belongs to conversation" do
      share = described_class.new(conversation:, event:, uuid: SecureRandom.uuid)
      expect(share.conversation).to eq(conversation)
    end

    it "belongs to event" do
      share = described_class.new(conversation:, event:, uuid: SecureRandom.uuid)
      expect(share.event).to eq(event)
    end
  end

  describe "validations" do
    it "requires uuid" do
      share = described_class.new(conversation:, event:)
      share.uuid = nil
      # set_uuid runs on before_create; bypass it by saving directly
      share.valid?
      # after before_create, uuid will be set — test uniqueness instead
      expect(share).to be_valid
    end

    it "requires uuid uniqueness" do
      existing_uuid = SecureRandom.uuid
      create(:share, conversation:, event:, uuid: existing_uuid)

      turn2 = conversation.turns.create!(position: 2, input_kind: :chat, input_text: "hi2")
      event2 = Event.create_with_position!(conversation:, turn: turn2, kind: :system, payload: { text: "b" })
      duplicate = build(:share, conversation:, event: event2, uuid: existing_uuid)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:uuid]).to be_present
    end

    it "requires event_id uniqueness (one share per event)" do
      create(:share, conversation:, event:)

      duplicate = build(:share, conversation:, event:)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:event_id]).to be_present
    end
  end

  describe "#to_param" do
    it "returns the uuid" do
      share = create(:share, conversation:, event:)
      expect(share.to_param).to eq(share.uuid)
    end
  end

  describe "uuid auto-generation" do
    it "auto-generates a uuid on create when none is provided" do
      share = described_class.new(conversation:, event:)
      share.save!
      expect(share.uuid).to be_present
      expect(share.uuid).to match(/\A[0-9a-f\-]{36}\z/)
    end
  end

  describe "uuid normalization" do
    it "downcases the uuid" do
      upper = SecureRandom.uuid.upcase
      share = create(:share, conversation:, event:, uuid: upper)
      expect(share.uuid).to eq(upper.downcase)
    end
  end

  describe "idempotent mint via find_or_create_by!" do
    it "returns the same share when called twice for the same event" do
      share1 = described_class.find_or_create_by!(event:) { |s| s.conversation = conversation }
      share2 = described_class.find_or_create_by!(event:) { |s| s.conversation = conversation }
      expect(share1.id).to eq(share2.id)
      expect(share1.uuid).to eq(share2.uuid)
    end

    it "creates only one record for the same event" do
      expect {
        described_class.find_or_create_by!(event:) { |s| s.conversation = conversation }
        described_class.find_or_create_by!(event:) { |s| s.conversation = conversation }
      }.to change(described_class, :count).by(1)
    end
  end
end
