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

    it "recognises :import as a new-turn verb" do
      result = described_class.call(lex("import Pragmata"), raw: "import Pragmata", conversation:)
      expect(result.verb).to eq(:import)
      expect(result.kind).to eq(:new_turn)
    end

    it "parses `import <id>` to verb :import" do
      result = described_class.call(lex("import 1"), raw: "import 1", conversation:)
      expect(result.verb).to eq(:import)
    end

    it "recognises :find as a new-turn verb" do
      result = described_class.call(lex("find items"), raw: "find items", conversation:)
      expect(result.verb).to eq(:find)
      expect(result.kind).to eq(:new_turn)
    end

    it "canonicalizes the `rm` alias to the :delete verb" do
      result = described_class.call(lex("rm Elden Ring"), raw: "rm Elden Ring", conversation:)
      expect(result.verb).to eq(:delete)
      expect(result.kind).to eq(:new_turn)
    end

    it "canonicalizes the `ls` alias to the :list verb" do
      result = described_class.call(lex("ls games"), raw: "ls games", conversation:)
      expect(result.verb).to eq(:list)
    end

    it "classifies unrecognised input as :unknown when no recent turn exists" do
      result = described_class.call(lex("hello"), raw: "hello", conversation:)
      expect(result.verb).to be_nil
      expect(result.kind).to eq(:unknown)
      expect(result.body_tokens).to eq([])
    end

    it "classifies unrecognised input as :unknown even when a recent turn with result events exists" do
      # Refinement machinery has been removed — no-verb messages always fall through to :unknown.
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
      expect(result.kind).to eq(:unknown)
    end

    it "classifies an unrecognised verb as :unknown with no open turn" do
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
