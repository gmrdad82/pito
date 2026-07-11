# frozen_string_literal: true

require "rails_helper"

# Ai::History projects a conversation's recent turns into the wire `messages`
# array the AI client sends upstream. Mirrors the direct AR construction used
# by spec/dispatch/universal_reply_spec.rb (Event.create_with_position! keeps
# positions correct without hand-rolling counters).
RSpec.describe Ai::History do
  let(:conversation) { Conversation.create! }

  def make_turn(text: "hi")
    conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: text
    )
  end

  def make_event(turn:, kind:, payload: {})
    Event.create_with_position!(conversation:, turn:, kind:, payload:)
  end

  describe ".messages" do
    it "projects an echo event as a user message carrying its text" do
      turn = make_turn(text: "list vids")
      make_event(turn:, kind: :echo, payload: { "text" => "list vids" })

      expect(described_class.messages(conversation:)).to eq([
        { role: "user", content: "list vids" }
      ])
    end

    it "projects a :system event as an assistant message via Pito::Mcp::EventText (verbatim text: payload)" do
      turn = make_turn
      make_event(turn:, kind: :echo, payload: { "text" => "list vids" })
      make_event(turn:, kind: :system, payload: { "text" => "here are your vids" })

      expect(described_class.messages(conversation:)).to eq([
        { role: "user", content: "list vids" },
        { role: "assistant", content: "here are your vids" }
      ])
    end

    it "skips thinking/confirmation/theme_diff events entirely" do
      turn = make_turn
      make_event(turn:, kind: :echo, payload: { "text" => "hi" })
      make_event(turn:, kind: :thinking, payload: { "text" => "pondering…" })
      make_event(turn:, kind: :confirmation, payload: { "text" => "are you sure?" })
      make_event(turn:, kind: :theme_diff, payload: { "text" => "diff" })
      make_event(turn:, kind: :system, payload: { "text" => "done" })

      expect(described_class.messages(conversation:)).to eq([
        { role: "user", content: "hi" },
        { role: "assistant", content: "done" }
      ])
    end

    it "projects an :ai event's text blocks verbatim and brackets structured blocks" do
      turn = make_turn(text: "ai what should I play?")
      make_event(turn:, kind: :echo, payload: { "text" => "ai what should I play?" })
      make_event(turn:, kind: :ai, payload: {
        "status" => "done",
        "blocks" => [
          { "type" => "text", "text" => "Try Tekken 7." },
          { "type" => "kv_table", "rows" => [ [ "score", "84" ] ] }
        ]
      })

      expect(described_class.messages(conversation:)).to eq([
        { role: "user", content: "ai what should I play?" },
        { role: "assistant", content: "Try Tekken 7.\n[kv_table block shown]" }
      ])
    end

    it "coalesces consecutive assistant messages across turns with no echo in between" do
      turn1 = make_turn(text: "list vids")
      make_event(turn: turn1, kind: :echo, payload: { "text" => "list vids" })
      make_event(turn: turn1, kind: :system, payload: { "text" => "first answer" })

      turn2 = make_turn(text: "and?")
      make_event(turn: turn2, kind: :system, payload: { "text" => "second answer" })

      expect(described_class.messages(conversation:)).to eq([
        { role: "user", content: "list vids" },
        { role: "assistant", content: "first answer\n\nsecond answer" }
      ])
    end

    it "keeps only the newest turn_limit turns, dropping the oldest turn's text" do
      turns = Array.new(3) { |i| make_turn(text: "turn #{i}") }
      turns.each_with_index do |turn, i|
        make_event(turn:, kind: :echo, payload: { "text" => "input #{i}" })
        make_event(turn:, kind: :system, payload: { "text" => "answer #{i}" })
      end

      result   = described_class.messages(conversation:, turn_limit: 2)
      contents = result.map { |m| m[:content] }

      expect(contents.join).not_to include("input 0")
      expect(contents).to include("input 1", "answer 2")
    end

    it "keeps only the newest whole turn under a tiny char_budget, even when it alone exceeds the budget" do
      turn1 = make_turn(text: "first")
      make_event(turn: turn1, kind: :echo, payload: { "text" => "aaaa" })
      make_event(turn: turn1, kind: :system, payload: { "text" => "bbbb" })

      turn2 = make_turn(text: "second")
      make_event(turn: turn2, kind: :echo, payload: { "text" => "this is way over ten chars" })
      make_event(turn: turn2, kind: :system, payload: { "text" => "so is this reply" })

      result = described_class.messages(conversation:, char_budget: 10)

      expect(result).to eq([
        { role: "user", content: "this is way over ten chars" },
        { role: "assistant", content: "so is this reply" }
      ])
    end


    it "pins the must_include_turn even when it scrolled out of the window, at chronological position" do
      anchor = make_turn(text: "@ai first question")
      make_event(turn: anchor, kind: :echo, payload: { "text" => "@ai first question" })
      make_event(turn: anchor, kind: :ai, payload: { "status" => "done", "blocks" => [ { "type" => "text", "text" => "first answer" } ] })

      3.times do |i|
        t = make_turn(text: "filler #{i}")
        make_event(turn: t, kind: :echo, payload: { "text" => "filler #{i}" })
      end

      result = described_class.messages(conversation:, turn_limit: 2, must_include_turn: anchor)
      expect(result.first[:content]).to include("@ai first question")
      expect(result.map { |m| m[:content] }.join).to include("first answer", "filler 2")
    end

    it "keeps the pinned anchor turn even when the budget would drop the oldest" do
      anchor = make_turn(text: "@ai anchor")
      make_event(turn: anchor, kind: :echo, payload: { "text" => "@ai anchor" })

      newest = make_turn(text: "n")
      make_event(turn: newest, kind: :echo, payload: { "text" => "n" * 200 })

      result = described_class.messages(conversation:, char_budget: 10, must_include_turn: anchor)
      expect(result.map { |m| m[:content] }.join).to include("@ai anchor")
    end

    it "produces no message for a blank echo text" do
      turn = make_turn
      make_event(turn:, kind: :echo, payload: { "text" => "   " })

      expect(described_class.messages(conversation:)).to eq([])
    end
  end
end
