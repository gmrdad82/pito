# frozen_string_literal: true

require "rails_helper"

RSpec.describe Turn, type: :model do
  subject(:turn) { build(:turn) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:input_text) }
    it { is_expected.to validate_presence_of(:position) }

    it "is valid with slash input_kind" do
      turn = build(:turn, input_kind: :slash)
      expect(turn).to be_valid
    end

    it "is valid with chat input_kind" do
      turn = build(:turn, input_kind: :chat)
      expect(turn).to be_valid
    end

    it "is valid with hashtag input_kind" do
      turn = build(:turn, input_kind: :hashtag)
      expect(turn).to be_valid
    end

    it "is invalid with an unknown input_kind" do
      turn = build(:turn, input_kind: "unknown")
      expect(turn).not_to be_valid
      expect(turn.errors[:input_kind]).to include("is not included in the list")
    end
  end

  describe "started_at stamp" do
    it "sets started_at on create" do
      turn = create(:turn)
      expect(turn.started_at).to be_present
      expect(turn.started_at).to be_within(1.second).of(Time.current)
    end
  end

  describe "#elapsed_seconds" do
    it "returns nil when started_at is nil" do
      turn.started_at = nil
      expect(turn.elapsed_seconds).to be_nil
    end

    it "returns the difference between completed_at and started_at" do
      turn = build(:turn, started_at: 10.seconds.ago, completed_at: 2.seconds.ago)
      expect(turn.elapsed_seconds).to eq(8.0)
    end

    it "uses current time when completed_at is nil" do
      turn = build(:turn, started_at: 5.seconds.ago, completed_at: nil)
      expect(turn.elapsed_seconds).to be_within(0.5).of(5.0)
    end
  end

  describe ".next_position_for" do
    it "returns 1 when no turns exist" do
      conversation = create(:conversation)
      expect(described_class.next_position_for(conversation)).to eq(1)
    end

    it "returns one more than the max position" do
      conversation = create(:conversation)
      create(:turn, conversation: conversation, position: 1, input_kind: :slash, input_text: "/help")
      create(:turn, conversation: conversation, position: 2, input_kind: :slash, input_text: "/test")
      expect(described_class.next_position_for(conversation)).to eq(3)
    end
  end

  describe "#display_text (recall-history masking)" do
    it "masks /config credentials" do
      turn = build(:turn, input_kind: :slash, input_text: "/config google client_secret=xyz")
      expect(turn.display_text).to eq("/config google client_secret=***")
    end

    it "masks /login payloads" do
      turn = build(:turn, input_kind: :slash, input_text: "/login 123456")
      expect(turn.display_text).to eq("/login ******")
    end

    it "returns non-secret input verbatim" do
      turn = build(:turn, input_kind: :chat, input_text: "list games")
      expect(turn.display_text).to eq("list games")
    end
  end
end
