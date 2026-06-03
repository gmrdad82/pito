# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatDispatchJob, type: :job do
  let(:conversation) { create(:conversation) }

  def setup_turn(input_text:, input_kind: nil)
    kind = input_kind || (input_text.start_with?("/") ? "slash" : input_text.start_with?("#") ? "hashtag" : "chat")
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: kind,
      input_text: input_text
    )
    conversation.events.create!(
      turn:,
      position: Event.next_position_for(conversation),
      kind:     "echo",
      payload:  { text: input_text }
    )
    turn
  end

  describe "#perform" do
    context "with a hashtag message" do
      let(:turn) { setup_turn(input_text: "#alpha-1234 hello", input_kind: :hashtag) }

      before do
        conf_turn = conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 99)
        Event.create_with_position!(
          conversation:, turn: conf_turn,
          kind: "confirmation",
          payload: {
            command: "test",
            confirmation_handle: "alpha-1234",
            authenticated: true
          }
        )
      end

      it "creates result events" do
        expect {
          described_class.perform_now(turn.id, channel: nil, period: nil)
        }.to change { turn.events.reload.count }.by_at_least(1)
      end

      it "stamps completed_at" do
        described_class.perform_now(turn.id, channel: nil, period: nil)
        expect(turn.reload.completed_at).not_to be_nil
      end

      it "produces a system event" do
        described_class.perform_now(turn.id, channel: nil, period: nil)
        event = turn.events.reload.find { |e| e.kind == "system" }
        expect(event).to be_present
        expect(event.payload["message_key"]).to eq("pito.hashtag.reply.acknowledged")
      end
    end
  end
end
