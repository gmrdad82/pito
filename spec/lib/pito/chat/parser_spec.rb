# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Parser do
  def lex(input)
    Pito::Lex::Lexer.call(input)
  end

  describe ".call" do
    let(:conversation) { Conversation.singleton }

    before do
      # Start clean — no leftover turns from other tests
      conversation.turns.destroy_all
    end

    it "classifies a recognised verb as :new_turn" do
      result = described_class.call(lex("list videos"), raw: "list videos", conversation:)
      expect(result.verb).to eq(:list)
      expect(result.kind).to eq(:new_turn)
      expect(result.body_tokens.map(&:value)).to eq([ "videos" ])
      expect(result.raw).to eq("list videos")
    end

    it "recognises :show as a new-turn verb" do
      result = described_class.call(lex("show something"), raw: "show something", conversation:)
      expect(result.verb).to eq(:show)
      expect(result.kind).to eq(:new_turn)
    end

    it "recognises :find as a new-turn verb" do
      result = described_class.call(lex("find items"), raw: "find items", conversation:)
      expect(result.verb).to eq(:find)
      expect(result.kind).to eq(:new_turn)
    end

    it "classifies unrecognised input as :unknown when no recent turn exists" do
      result = described_class.call(lex("hello"), raw: "hello", conversation:)
      expect(result.verb).to be_nil
      expect(result.kind).to eq(:unknown)
      expect(result.body_tokens).to eq([])
    end

    it "classifies unrecognised input as :refinement when a recent turn with result events exists" do
      # A turn is only refinement-eligible when it has result events beyond the echo
      # (echo-only turns are still dispatching via ChatDispatchJob).
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

      result = described_class.call(lex("more stuff"), raw: "more stuff", conversation:)
      expect(result.verb).to be_nil
      expect(result.kind).to eq(:refinement)
      expect(result.body_tokens.map(&:value)).to eq([ "stuff" ])
    end

    it "classifies as :unknown when the only turn is older than 30 minutes" do
      conversation.turns.create!(
        input_text: "list videos",
        input_kind: :chat,
        position: 1,
        created_at: 45.minutes.ago
      )

      result = described_class.call(lex("more stuff"), raw: "more stuff", conversation:)
      expect(result.verb).to be_nil
      expect(result.kind).to eq(:unknown)
    end

    it "classifies an unrecognised verb as :unknown (not :refinement) with no open turn" do
      result = described_class.call(lex("madeup verb"), raw: "madeup verb", conversation:)
      expect(result.verb).to be_nil
      expect(result.kind).to eq(:unknown)
    end

    it "raises NotAChatMessage for slash-prefixed input" do
      expect {
        described_class.call(lex("/help"), raw: "/help", conversation:)
      }.to raise_error(described_class::NotAChatMessage)
    end

    it "handles single-word recognised verb with no body" do
      result = described_class.call(lex("list"), raw: "list", conversation:)
      expect(result.verb).to eq(:list)
      expect(result.kind).to eq(:new_turn)
      expect(result.body_tokens).to eq([])
    end

    it "handles empty body tokens for unrecognised input" do
      result = described_class.call(lex("???"), raw: "???", conversation:)
      expect(result.verb).to be_nil
      expect(result.kind).to eq(:unknown)
    end
  end
end
