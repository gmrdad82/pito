# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Share::UniversalActions do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "hi"
    )
  end
  let(:event) do
    Event.create_with_position!(
      conversation:, turn:, kind: :system,
      payload: { "text" => "hello", "reply_handle" => "test-handle" }
    )
  end
  let(:handler) { described_class.new }

  describe "VERBS" do
    it "includes share, revoke, and unshare" do
      expect(described_class::VERBS).to match_array(%w[share revoke unshare])
    end
  end

  describe "#call — share verb" do
    it "mints a Share record" do
      expect {
        handler.call(source_event: event, rest: "share", conversation:)
      }.to change(Share, :count).by(1)
    end

    it "returns a Result::Append with consume: false" do
      result = handler.call(source_event: event, rest: "share", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to eq(false)
    end

    it "returns a :system event with the share URL" do
      result = handler.call(source_event: event, rest: "share", conversation:)
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
      payload = result.events.first[:payload]
      expect(payload["text"]).to include("/share/")
    end

    it "is idempotent — calling share twice returns the same Share" do
      result1 = handler.call(source_event: event, rest: "share", conversation:)
      result2 = handler.call(source_event: event, rest: "share", conversation:)
      url1 = result1.events.first[:payload]["text"]
      url2 = result2.events.first[:payload]["text"]
      expect(url1).to eq(url2)
      expect(Share.where(event:).count).to eq(1)
    end

    it "reuses the existing Share when called multiple times" do
      handler.call(source_event: event, rest: "share", conversation:)
      expect {
        handler.call(source_event: event, rest: "share", conversation:)
      }.not_to change(Share, :count)
    end
  end

  describe "#call — revoke verb" do
    it "enqueues RevokeShareJob" do
      expect {
        handler.call(source_event: event, rest: "revoke", conversation:)
      }.to have_enqueued_job(RevokeShareJob).with(event.id)
    end

    it "returns a Result::Append with consume: true" do
      result = handler.call(source_event: event, rest: "revoke", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to eq(true)
    end

    it "returns a :system event with a revoke_ack message" do
      result = handler.call(source_event: event, rest: "revoke", conversation:)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload]["text"]).to be_present
    end
  end

  describe "#call — unshare verb (alias for revoke)" do
    it "enqueues RevokeShareJob" do
      expect {
        handler.call(source_event: event, rest: "unshare", conversation:)
      }.to have_enqueued_job(RevokeShareJob).with(event.id)
    end

    it "returns a Result::Append with consume: true" do
      result = handler.call(source_event: event, rest: "unshare", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to eq(true)
    end
  end

  describe "#call — unknown verb" do
    it "returns a Result::Error" do
      result = handler.call(source_event: event, rest: "bogus", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
