# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatDispatchJob, type: :job do
  let(:conversation) { create(:conversation) }

  # Build a turn with a pre-created echo event (matches the controller's output).
  def setup_turn(input_text:, input_kind: nil)
    kind = input_kind || (input_text.start_with?("/") ? "slash" : "chat")
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
    context "with a slash command (/help)" do
      let(:turn) { setup_turn(input_text: "/help") }

      it "creates result events" do
        expect {
          described_class.perform_now(turn.id, channel: "@all")
        }.to change { turn.events.reload.count }.by_at_least(1)
      end

      it "stamps completed_at on the turn" do
        described_class.perform_now(turn.id, channel: "@all")
        expect(turn.reload.completed_at).not_to be_nil
      end

      it "adds elapsed_seconds to result event payloads" do
        described_class.perform_now(turn.id, channel: "@all")
        result_event = turn.events.reload.find { |e| e.kind != "echo" }
        expect(result_event.payload["elapsed_seconds"]).not_to be_nil
      end

      it "injects segment_style: plain for the first assistant_text" do
        described_class.perform_now(turn.id, channel: "@all")
        assistant_events = turn.events.reload.where(kind: "assistant_text").order(:position)
        expect(assistant_events.first.payload["segment_style"]).to eq("plain")
      end

      it "injects segment_style: subsequent for 2nd+ assistant_text" do
        described_class.perform_now(turn.id, channel: "@all")
        assistant_events = turn.events.reload.where(kind: "assistant_text").order(:position)
        expect(assistant_events.count).to be > 1
        expect(assistant_events.second.payload["segment_style"]).to eq("subsequent")
      end
    end

    context "with an unknown slash verb" do
      let(:turn) { setup_turn(input_text: "/unknown_xyz") }

      it "creates an error event" do
        described_class.perform_now(turn.id, channel: "@all")
        kinds = turn.events.reload.map(&:kind)
        expect(kinds).to include("error")
      end
    end

    context "with a chat message" do
      let(:turn) { setup_turn(input_text: "list videos", input_kind: "chat") }

      it "creates result events" do
        expect {
          described_class.perform_now(turn.id, channel: "@all")
        }.to change { turn.events.reload.count }.by_at_least(1)
      end

      it "stamps completed_at" do
        described_class.perform_now(turn.id, channel: "@all")
        expect(turn.reload.completed_at).not_to be_nil
      end

      it "injects segment_style: plain for the single assistant_text" do
        described_class.perform_now(turn.id, channel: "@all")
        event = turn.events.reload.find { |e| e.kind == "assistant_text" }
        expect(event.payload["segment_style"]).to eq("plain")
      end
    end

    context "elapsed_seconds" do
      let(:turn) { setup_turn(input_text: "/help") }

      it "is positive (turn ran after it was created)" do
        described_class.perform_now(turn.id, channel: "@all")
        elapsed = turn.reload.elapsed_seconds
        expect(elapsed).to be >= 0
      end
    end
  end
end
