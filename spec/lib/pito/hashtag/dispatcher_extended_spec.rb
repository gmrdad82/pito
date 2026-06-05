# frozen_string_literal: true

# Extended edge-case coverage for Pito::Hashtag::Dispatcher.
# Main dispatcher_spec.rb covers the primary dispatch paths.
# This file adds: empty handle, malformed input, handle-with-body,
# and fallback to Reply for any unregistered handle.

require "rails_helper"

RSpec.describe Pito::Hashtag::Dispatcher, "edge cases" do
  let(:conversation) { Conversation.singleton }

  before { conversation.turns.destroy_all }

  # ── Malformed / empty input ───────────────────────────────────────────────────

  describe ".call — bare # with no handle" do
    it "returns parse_failed error" do
      result = described_class.call(input: "#", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.errors.parse_failed")
    end
  end

  describe ".call — empty string" do
    it "does not raise and returns an error result" do
      result = described_class.call(input: "", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Error)
    end
  end

  describe ".call — non-hashtag input (no # prefix)" do
    it "returns parse_failed" do
      result = described_class.call(input: "hello world", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.errors.parse_failed")
    end
  end

  # ── Fallback to Reply for any unregistered handle ─────────────────────────────

  describe ".call — unregistered handle falls back to Reply (confirmation path)" do
    let!(:conf_turn) do
      t = conversation.turns.create!(input_kind: :slash, input_text: "/disconnect @x", position: 1)
      Event.create_with_position!(
        conversation:, turn: t,
        kind: "confirmation",
        payload: { command: "disconnect", confirmation_handle: "zebra-9999" }
      )
      t
    end

    it "routes to the Reply handler (not unknown_handle error)" do
      result = described_class.call(input: "#zebra-9999", conversation:)
      # Reply handler returns Ok or reply-specific error — never the generic unknown_handle key.
      if result.is_a?(Pito::Hashtag::Result::Error)
        expect(result.message_key).not_to eq("pito.hashtag.errors.unknown_handle")
      else
        expect(result).to be_a(Pito::Hashtag::Result::Ok)
      end
    end
  end

  # ── Handle with body tokens ───────────────────────────────────────────────────

  describe ".call — handle with body text dispatches to Reply" do
    let!(:conf_turn) do
      t = conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 1)
      Event.create_with_position!(
        conversation:, turn: t,
        kind: "confirmation",
        payload: { command: "test", confirmation_handle: "delta-1111" }
      )
      t
    end

    it "passes through without parse_failed" do
      result = described_class.call(input: "#delta-1111 yes please", conversation:)
      # The Reply handler processes the body — result is Ok or Error from Reply
      expect(result.message_key).not_to eq("pito.hashtag.errors.parse_failed") if result.respond_to?(:message_key)
    end
  end
end
