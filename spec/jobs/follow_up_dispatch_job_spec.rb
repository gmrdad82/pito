# frozen_string_literal: true

require "rails_helper"

# Fake mutate handler — registered only during this spec file.
class FakeMutateHandler < Pito::FollowUp::Handler
  target "fake_mutate"
  mode   :mutate

  def call(event:, rest:, conversation:)
    Pito::FollowUp::Result::Mutation.new(
      kind:    :enhanced,
      payload: event.payload.merge("done" => true, "rest" => rest)
    )
  end
end

# Fake append handler — registered only during this spec file.
class FakeAppendHandler < Pito::FollowUp::Handler
  target "fake_append"
  mode   :append

  def call(event:, rest:, conversation:)
    Pito::FollowUp::Result::Append.new(
      events: [
        { kind: :system, payload: { text: "appended by #{rest}" } }
      ]
    )
  end
end

# Fake error handler.
class FakeErrorHandler < Pito::FollowUp::Handler
  target "fake_error"
  mode   :mutate

  def call(event:, rest:, conversation:)
    Pito::FollowUp::Result::Error.new(
      message_key:  "pito.errors.something",
      message_args: {}
    )
  end
end

RSpec.describe FollowUpDispatchJob, type: :job do
  let(:conversation) { Conversation.create! }
  let(:source_turn) do
    conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 1)
  end

  describe "Mutation result" do
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "alpha-1111",
          "reply_target" => "fake_mutate",
          "text"         => "original"
        }
      )
    end

    before do
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(
        instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, complete_turn: nil)
      )
    end

    it "updates the event kind" do
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(source_event.reload.kind).to eq("enhanced")
    end

    it "merges done: true into the payload" do
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(source_event.reload.payload["done"]).to be true
    end

    it "stores the rest string in the payload" do
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(source_event.reload.payload["rest"]).to eq("do-it")
    end

    it "calls broadcaster.replace_event" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, complete_turn: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(broadcaster).to have_received(:replace_event).with(source_event)
    end

    it "emits pito:done so the dots fade out (turn-less mutate)" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, complete_turn: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "do-it")
      expect(broadcaster).to have_received(:broadcast_done).with(dom_id: "event_#{source_event.id}")
    end
  end

  describe "Append result" do
    let(:echo_turn) do
      conversation.turns.create!(input_kind: :hashtag, input_text: "#alpha-2222 run", position: 2)
    end
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "alpha-2222",
          "reply_target" => "fake_append",
          "text"         => "pick something"
        }
      )
    end

    it "creates a new event for each append result" do
      expect {
        described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      }.to change(Event, :count).by(1)
    end

    it "the new event has the correct kind and payload" do
      described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      new_event = echo_turn.events.last
      expect(new_event.kind).to eq("system")
      expect(new_event.payload["text"]).to eq("appended by hello")
    end

    it "marks the source event consumed" do
      described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      expect(source_event.reload.payload["reply_consumed"]).to be true
    end

    it "broadcasts replace_event on the (now-consumed) source" do
      broadcaster = instance_double(Pito::Stream::Broadcaster, replace_event: nil, broadcast_event: nil, broadcast_done: nil, complete_turn: nil)
      allow(Pito::Stream::Broadcaster).to receive(:new).and_return(broadcaster)
      described_class.perform_now(source_event.id, rest: "hello", turn_id: echo_turn.id)
      expect(broadcaster).to have_received(:replace_event).with(source_event)
    end
  end

  describe "Error result" do
    let(:echo_turn) do
      conversation.turns.create!(input_kind: :hashtag, input_text: "#err-5555 bad", position: 3)
    end
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: {
          "reply_handle" => "err-5555",
          "reply_target" => "fake_error"
        }
      )
    end

    it "appends an error event to the turn" do
      expect {
        described_class.perform_now(source_event.id, rest: "bad", turn_id: echo_turn.id)
      }.to change { echo_turn.events.where(kind: "error").count }.by(1)
    end
  end

  describe "missing handler (unknown target)" do
    let!(:source_event) do
      Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: { "reply_handle" => "gamma-9999", "reply_target" => "nonexistent" }
      )
    end

    it "does not raise" do
      expect {
        described_class.perform_now(source_event.id, rest: "anything")
      }.not_to raise_error
    end
  end
end
