# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Dispatch::Finalizer, "handle stamping" do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "hi"
    )
  end
  let(:finalizer) { described_class.new(conversation:) }

  # Pre-create echo + placeholder so persist can reuse the placeholder
  let!(:echo) do
    Event.create_with_position!(conversation:, turn:, kind: :echo, payload: { text: "hi" })
  end
  let!(:placeholder) do
    Event.create_with_position!(
      conversation:, turn:, kind: :thinking,
      payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 3.seconds.ago.iso8601 }
    )
  end

  describe "#persist — HANDLE_STAMP_KINDS" do
    it "stamps reply_handle on persisted :system events" do
      events = finalizer.persist(events: [ { kind: :system, payload: { "text" => "hello" } } ], turn:)
      expect(events.first.payload["reply_handle"]).to be_present
    end

    it "stamps reply_handle on persisted :enhanced events" do
      # Need two system events so the second becomes :enhanced
      events = finalizer.persist(
        events: [
          { kind: :system, payload: { "text" => "intro" } },
          { kind: :system, payload: { "text" => "card" } }
        ],
        turn:
      )
      enhanced = events.find { |e| e.kind == "enhanced" }
      expect(enhanced).to be_present
      expect(enhanced.payload["reply_handle"]).to be_present
    end

    it "does NOT stamp reply_handle on :echo events" do
      # echo events don't go through persist (they're emitted directly),
      # but verify HANDLE_STAMP_KINDS does not include echo
      expect(described_class::HANDLE_STAMP_KINDS).not_to include("echo")
    end

    it "does NOT stamp reply_handle on :error events" do
      expect(described_class::HANDLE_STAMP_KINDS).not_to include("error")
    end

    it "does not double-stamp a payload already carrying reply_handle" do
      original_handle = "pre-existing-handle"
      payload = { "text" => "hello", "reply_handle" => original_handle, "reply_target" => "game_list" }
      events = finalizer.persist(events: [ { kind: :system, payload: } ], turn:)
      expect(events.first.payload["reply_handle"]).to eq(original_handle)
    end
  end
end
