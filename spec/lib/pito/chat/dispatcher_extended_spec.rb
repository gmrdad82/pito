# frozen_string_literal: true

# Extended edge-case coverage for Pito::Chat::Dispatcher.
# The main dispatcher_spec.rb covers the primary dispatch paths.
# This file adds: empty input, whitespace-only, slash-prefixed input,
# unknown verb (not in registry), malformed kwargs pattern.

require "rails_helper"

RSpec.describe Pito::Chat::Dispatcher, "edge cases" do
  let(:conversation) { Conversation.singleton }

  before { conversation.turns.destroy_all }

  # ── Empty / whitespace input ──────────────────────────────────────────────────

  describe ".call — empty input" do
    it "does not raise and returns a result object" do
      expect { described_class.call(input: "", conversation:) }.not_to raise_error
    end

    it "returns a witty :system reply (not an error)" do
      result = described_class.call(input: "", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end
  end

  describe ".call — whitespace-only input" do
    it "returns a witty :system reply (not an error)" do
      result = described_class.call(input: "   ", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Ok)
    end
  end

  # ── Slash-prefixed input (misrouted) ──────────────────────────────────────────

  describe ".call — slash-prefixed input" do
    it "returns misrouted_slash error" do
      result = described_class.call(input: "/config something", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.misrouted_slash")
    end

    it "includes the raw input in message_args" do
      result = described_class.call(input: "/whatever", conversation:)
      expect(result.message_args[:raw]).to eq("/whatever")
    end
  end

  # ── Unregistered verb (recognised by parser but no handler) ──────────────────

  describe ".call — recognised verb with no handler" do
    it "returns verb_not_implemented for :find" do
      result = described_class.call(input: "find something", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.verb_not_implemented")
      expect(result.message_args[:verb]).to eq(:find)
    end
  end

  # ── Truly unknown input (no matching verb) ────────────────────────────────────

  describe ".call — completely unknown input" do
    it "returns a witty :system reply (not an error)" do
      result = described_class.call(input: "xyzzy frobble", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload][:text]).to be_present
    end
  end

  # ── No-verb input always falls through to :unknown ───────────────────────────

  describe ".call — no-verb input always classifies as :unknown" do
    context "when no turn exists" do
      it "returns a witty :system reply" do
        result = described_class.call(input: "more details", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    context "when a recent turn with system result events exists" do
      it "still returns a witty :system reply (refinement machinery removed)" do
        turn = conversation.turns.create!(
          input_text: "list videos",
          input_kind: :chat,
          position: 1,
          created_at: 5.minutes.ago
        )
        conversation.events.create!(
          turn:, position: 1,
          kind: :system,
          payload: { message_key: "pito.chat.list.descriptions.list", message_args: {} }
        )

        result = described_class.call(input: "more details", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end
  end
end
