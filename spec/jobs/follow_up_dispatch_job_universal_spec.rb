# frozen_string_literal: true

require "rails_helper"

# Fake registered handler for testing the non-universal path still works.
class FakeTargetedHandler < Pito::FollowUp::Handler
  target "fake_targeted_for_universal_spec"
  mode   :append

  def call(event:, rest:, conversation:, **)
    Pito::FollowUp::Result::Append.new(
      events: [ { kind: :system, payload: { text: "targeted: #{rest}" } } ]
    )
  end
end

RSpec.describe FollowUpDispatchJob, "universal verb routing" do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "hi"
    )
  end

  # A source event that carries a reply_handle (but no reply_target — universal verbs
  # don't need one).
  let(:source_event) do
    Event.create_with_position!(
      conversation:, turn:, kind: :system,
      payload: { "text" => "hello", "reply_handle" => "test-handle" }
    )
  end

  # A turn for the reply to append into.
  let(:reply_turn) do
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :hashtag,
      input_text: "#test-handle share"
    )
  end

  before do
    # Pre-create echo + placeholder for the reply turn so Finalizer#persist can run.
    Event.create_with_position!(conversation:, turn: reply_turn, kind: :echo, payload: { text: "#test-handle share" })
    Event.create_with_position!(
      conversation:, turn: reply_turn, kind: :thinking,
      payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 3.seconds.ago.iso8601 }
    )
  end

  describe "universal verb short-circuit (share)" do
    it "routes to UniversalActions instead of the registered handler" do
      expect(Pito::Share::UniversalActions).to receive(:new).and_call_original
      described_class.new.perform(source_event.id, rest: "share", turn_id: reply_turn.id)
    end

    it "creates a Share record" do
      expect {
        described_class.new.perform(source_event.id, rest: "share", turn_id: reply_turn.id)
      }.to change(Share, :count).by(1)
    end

    it "appends a :system event to the reply turn" do
      described_class.new.perform(source_event.id, rest: "share", turn_id: reply_turn.id)
      appended = reply_turn.events.where(kind: "system").first
      expect(appended).to be_present
      expect(appended.payload["text"]).to include("/share/")
    end

    it "does NOT consume the source event (consume: false for share)" do
      described_class.new.perform(source_event.id, rest: "share", turn_id: reply_turn.id)
      expect(source_event.reload.payload["reply_consumed"]).to be_nil
    end
  end

  describe "universal verb short-circuit (revoke)" do
    it "enqueues RevokeShareJob" do
      expect {
        described_class.new.perform(source_event.id, rest: "revoke", turn_id: reply_turn.id)
      }.to have_enqueued_job(RevokeShareJob).with(source_event.id)
    end

    it "consumes the source event (consume: true for revoke)" do
      described_class.new.perform(source_event.id, rest: "revoke", turn_id: reply_turn.id)
      expect(source_event.reload.payload["reply_consumed"]).to eq(true)
    end
  end

  describe "non-universal verb still uses registered handler" do
    let(:targeted_event) do
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: {
          "text"         => "targeted",
          "reply_handle" => "targeted-handle",
          "reply_target" => "fake_targeted_for_universal_spec"
        }
      )
    end

    it "does not route to UniversalActions" do
      expect(Pito::Share::UniversalActions).not_to receive(:new)
      # Need a reply turn for targeted handler
      targeted_reply_turn = conversation.turns.create!(
        position: Turn.next_position_for(conversation),
        input_kind: :hashtag,
        input_text: "#targeted-handle show"
      )
      Event.create_with_position!(conversation:, turn: targeted_reply_turn, kind: :echo, payload: { text: "#targeted-handle show" })
      Event.create_with_position!(
        conversation:, turn: targeted_reply_turn, kind: :thinking,
        payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 3.seconds.ago.iso8601 }
      )
      described_class.new.perform(targeted_event.id, rest: "show", turn_id: targeted_reply_turn.id)
    end

    it "routes to the registered handler for a non-universal verb" do
      targeted_reply_turn = conversation.turns.create!(
        position: Turn.next_position_for(conversation),
        input_kind: :hashtag,
        input_text: "#targeted-handle show"
      )
      Event.create_with_position!(conversation:, turn: targeted_reply_turn, kind: :echo, payload: { text: "#targeted-handle show" })
      Event.create_with_position!(
        conversation:, turn: targeted_reply_turn, kind: :thinking,
        payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 3.seconds.ago.iso8601 }
      )
      described_class.new.perform(targeted_event.id, rest: "show", turn_id: targeted_reply_turn.id)
      appended = targeted_reply_turn.events.where(kind: "system").first
      expect(appended.payload["text"]).to include("targeted: show")
    end
  end
end
