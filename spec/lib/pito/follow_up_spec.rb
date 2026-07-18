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

  # ── availability — the owner's "no actions → no handle, no chip" rule ──────

  describe ".actions_possible? (mint-time)" do
    before { Pito::FollowUp::Registry.register_all! }

    it "is true when reply_target names a Registry-registered target with its own actions" do
      payload = { "reply_target" => "game_detail" }
      expect(described_class.actions_possible?(payload:, kind: "system")).to be true
    end

    it "is true regardless of kind/origin when the registered target has actions (target branch short-circuits)" do
      payload = { "reply_target" => "confirmation" }
      # confirmation kind isn't in the universal share `kinds:` list, and the
      # origin below is opted out — neither would pass the universal branch,
      # proving the registered-target check is independent of it.
      payload["origin_tool"] = "sync"
      expect(described_class.actions_possible?(payload:, kind: "confirmation")).to be true
    end

    it "is false when reply_target names a target with NO registered actions (e.g. the retired theme_diff target)" do
      payload = { "reply_target" => "theme_diff" }
      expect(described_class.actions_possible?(payload:, kind: "theme_diff")).to be false
    end

    it "is true (universal fallback) with no reply_target, an un-opted-out origin, and an allowed kind" do
      payload = {}
      expect(described_class.actions_possible?(payload:, kind: "system")).to be true
    end

    it "is false with no reply_target when the origin tool opted out (universal_reply: false)" do
      payload = { "origin_tool" => "sync" }
      expect(described_class.actions_possible?(payload:, kind: "system")).to be false
    end

    it "is false with no reply_target when kind isn't covered by the universal share kinds list" do
      payload = {}
      expect(described_class.actions_possible?(payload:, kind: "confirmation")).to be false
    end

    it "reads origin_verb as a fallback for origin_tool" do
      payload = { "origin_verb" => "sync" }
      expect(described_class.actions_possible?(payload:, kind: "system")).to be false
    end

    it "works with symbol-key payloads" do
      payload = { reply_target: "game_detail" }
      expect(described_class.actions_possible?(payload:, kind: :system)).to be true
    end
  end

  describe ".renderable_actions? (render-time)" do
    let(:conversation) { Conversation.create! }
    let(:turn) { create(:turn, conversation:) }

    before { Pito::FollowUp::Registry.register_all! }

    it "is true for an unconsumed event whose target has registered actions" do
      event = create(:event, conversation:, turn:, kind: "system",
                     payload: { "reply_handle" => "a-1", "reply_target" => "game_detail" })
      expect(described_class.renderable_actions?(event)).to be true
    end

    it "is true for an unconsumed universal-only event (allowed kind, no opt-out)" do
      event = create(:event, conversation:, turn:, kind: "system",
                     payload: { "reply_handle" => "a-2" })
      expect(described_class.renderable_actions?(event)).to be true
    end

    it "is false once the event is consumed, even with a target that has actions" do
      event = create(:event, conversation:, turn:, kind: "system",
                     payload: { "reply_handle" => "a-3", "reply_target" => "game_detail", "reply_consumed" => true })
      expect(described_class.renderable_actions?(event)).to be false
    end

    it "is false for an event whose origin tool opted out and carries no registered target" do
      event = create(:event, conversation:, turn:, kind: "system",
                     payload: { "reply_handle" => "a-4", "origin_tool" => "sync" })
      expect(described_class.renderable_actions?(event)).to be false
    end

    it "is false for a legacy target with zero registered actions and a kind outside the universal set" do
      event = create(:event, conversation:, turn:, kind: "theme_diff",
                     payload: { "reply_handle" => "a-5", "reply_target" => "theme_diff" })
      expect(described_class.renderable_actions?(event)).to be false
    end
  end
end
