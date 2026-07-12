# frozen_string_literal: true

require "rails_helper"

# The ai_message follow-up: `apply [n]` runs a suggested command; `@ai <text>`
# continues the thread with a new pending :ai event anchored on the source
# answer (the orchestrator pins that exchange into the model's context).
RSpec.describe Pito::FollowUp::Handlers::AiMessage do
  let(:conversation) { Conversation.singleton }

  def make_ai_event(blocks: [], payload_extra: {})
    turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation), input_kind: :chat, input_text: "@ai q"
    )
    Event.create_with_position!(
      conversation:, turn:, kind: :ai,
      payload: { "status" => "done", "blocks" => blocks, "reply_handle" => "a1" }.merge(payload_extra)
    )
  end

  describe "@ai continuation" do
    it "appends a pending :ai event carrying the prompt and the anchor id, keeping the source live" do
      event  = make_ai_event(blocks: [ { "type" => "text", "text" => "answer" } ])
      result = described_class.new.call(event:, rest: "@ai and what about tekken?", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)

      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("and what about tekken?")
      expect(pending[:payload]["anchor_event_id"]).to eq(event.id)
    end

    it "honors the --web opt-in exactly like a fresh @ai turn (smoke-found gap)" do
      event   = make_ai_event
      result  = described_class.new.call(event:, rest: "@ai --web is it out yet?", conversation:)
      pending = result.events.first

      expect(pending[:payload]["web"]).to be(true)
      expect(pending[:payload]["prompt"]).to eq("is it out yet?")
    end

    it "sets no web key without the flag" do
      event   = make_ai_event
      result  = described_class.new.call(event:, rest: "@ai plain question", conversation:)
      expect(result.events.first[:payload]).not_to have_key("web")
    end

    it "accepts any @ai casing in the reply text" do
      event  = make_ai_event
      result = described_class.new.call(event:, rest: "@AI more please", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["prompt"]).to eq("more please")
    end

    it "errors on a bare @ai with nothing to ask" do
      event  = make_ai_event
      result = described_class.new.call(event:, rest: "@ai   ", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.chat.ai.needs_prompt")
    end
  end

  describe "anything else" do
    it "rejects unknown actions — apply is gone (owner call), @ai is the only reply verb" do
      event  = make_ai_event
      %w[frobnicate apply].each do |action|
        result = described_class.new.call(event:, rest: action, conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.errors.unknown_action")
      end
    end
  end
end
