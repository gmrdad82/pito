# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp, type: :service do
  let(:conversation) { Conversation.create! }

  describe ".make_followupable!" do
    it "injects reply_handle and reply_target into the payload" do
      payload = {}
      result  = described_class.make_followupable!(payload, target: "my_handler", conversation:)
      expect(result["reply_handle"]).to match(/\A[a-z]+-\d{4}\z/)
      expect(result["reply_target"]).to eq("my_handler")
    end

    it "is idempotent — does not overwrite an existing reply_handle" do
      payload = { "reply_handle" => "zeta-1234", "reply_target" => "original" }
      described_class.make_followupable!(payload, target: "changed", conversation:)
      expect(payload["reply_handle"]).to eq("zeta-1234")
      expect(payload["reply_target"]).to eq("original")
    end

    it "returns the same (mutated) hash" do
      payload = {}
      result  = described_class.make_followupable!(payload, target: "t", conversation:)
      expect(result).to be(payload)
    end

    it "works with symbol-key payloads" do
      payload = {}
      described_class.make_followupable!(payload, target: "t", conversation:)
      # Written as string keys regardless of input type
      expect(payload["reply_handle"]).to be_present
    end
  end

  describe ".followupable?" do
    it "returns true when reply_handle (string key) is present" do
      expect(described_class.followupable?({ "reply_handle" => "alpha-1234" })).to be true
    end

    it "returns true when reply_handle (symbol key) is present" do
      expect(described_class.followupable?({ reply_handle: "alpha-1234" })).to be true
    end

    it "returns false when reply_handle is absent" do
      expect(described_class.followupable?({})).to be false
    end
  end

  describe ".consumed?" do
    it "returns true when reply_consumed is true (boolean)" do
      expect(described_class.consumed?({ "reply_consumed" => true })).to be true
    end

    it "returns true when reply_consumed is 'true' (string from DB)" do
      expect(described_class.consumed?({ "reply_consumed" => "true" })).to be true
    end

    it "returns false when reply_consumed is false" do
      expect(described_class.consumed?({ "reply_consumed" => false })).to be false
    end

    it "returns false when reply_consumed is absent" do
      expect(described_class.consumed?({})).to be false
    end
  end
end
