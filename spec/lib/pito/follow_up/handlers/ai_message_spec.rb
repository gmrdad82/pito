# frozen_string_literal: true

require "rails_helper"

# The ai_message follow-up: `apply`/`use`/`accept` STAGE the answer's
# suggested command (the web client intercepts this client-side and never
# reaches this handler — this is the non-web fallback that hands the command
# text back as a system message); `@ai <text>` continues the thread with a
# new pending :ai event anchored on the source answer (the orchestrator pins
# that exchange into the model's context). `@ai` now routes through the SAME
# target-agnostic path (ToolDelegator -> the uniform Router contract ->
# Chat::Handlers::Ai) every OTHER rostered card's `@ai` reply takes — these
# specs exercise the REAL delegation end to end (no hand-rolled regex left
# in the handler to unit-test in isolation).
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

  describe "anything else — truly unknown actions" do
    it "rejects an undeclared action with the target-scoped invalid_action key" do
      event  = make_ai_event
      result = described_class.new.call(event:, rest: "frobnicate", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.ai_message.errors.invalid_action")
      expect(result.message_args).to eq(action: "frobnicate")
    end
  end

  describe "apply/use/accept — the non-web fallback (WP6)" do
    let(:suggestion_block) { { "type" => "suggestion", "command" => "show vid #12" } }

    %w[apply use accept].each do |action|
      it "hands back the suggested command as a system message for `#{action}` (consume: false)" do
        event  = make_ai_event(blocks: [ { "type" => "text", "text" => "answer" }, suggestion_block ])
        result = described_class.new.call(event:, rest: action, conversation:)

        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to be(false)
        expect(result.events.length).to eq(1)

        appended = result.events.first
        expect(appended[:kind]).to eq(:system)
        expect(appended[:payload]).to eq(
          Pito::MessageBuilder::Text.call("pito.copy.ai.apply_fallback", command: "show vid #12")
        )
      end
    end

    it "errors with no_suggestion when the answer carries no suggestion block" do
      event  = make_ai_event(blocks: [ { "type" => "text", "text" => "just words, no command" } ])
      result = described_class.new.call(event:, rest: "apply", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.ai_message.errors.no_suggestion")
    end

    it "errors with no_suggestion when the answer has no blocks at all" do
      event  = make_ai_event(blocks: [])
      result = described_class.new.call(event:, rest: "use", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.ai_message.errors.no_suggestion")
    end
  end
end
