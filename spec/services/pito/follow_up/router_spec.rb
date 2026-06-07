# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Router, type: :service do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 1)
  end
  let!(:live_event) do
    Event.create_with_position!(
      conversation:, turn:, kind: "system",
      payload: {
        "reply_handle" => "delta-4823",
        "reply_target" => "fake_handler",
        "text"         => "Pick one"
      }
    )
  end

  def route(input)
    described_class.call(input:, conversation:)
  end

  describe "not a follow-up (pattern mismatch)" do
    it "returns :not_a_follow_up for plain text" do
      expect(route("hello")[:status]).to eq(:not_a_follow_up)
    end

    it "returns :not_a_follow_up for a slash command" do
      expect(route("/themes list")[:status]).to eq(:not_a_follow_up)
    end

    it "returns :not_a_follow_up for a #handle with no trailing text" do
      expect(route("#delta-4823")[:status]).to eq(:not_a_follow_up)
    end

    it "returns :not_a_follow_up for wrong digit count" do
      expect(route("#delta-48 something")[:status]).to eq(:not_a_follow_up)
    end

    it "returns :not_a_follow_up for #word-4digits with no space after" do
      expect(route("#delta-4823action")[:status]).to eq(:not_a_follow_up)
    end
  end

  describe ":ok — live event found" do
    it "returns status: :ok" do
      expect(route("#delta-4823 do it")[:status]).to eq(:ok)
    end

    it "returns the matched event" do
      expect(route("#delta-4823 do it")[:event]).to eq(live_event)
    end

    it "returns the handle" do
      expect(route("#delta-4823 do it")[:handle]).to eq("delta-4823")
    end

    it "returns the rest string" do
      expect(route("#delta-4823 do it")[:rest]).to eq("do it")
    end

    it "trims whitespace from rest" do
      expect(route("#delta-4823   preview   ")[:rest]).to eq("preview")
    end

    it "is case-insensitive for the handle" do
      expect(route("#DELTA-4823 something")[:status]).to eq(:ok)
    end
  end

  describe ":not_found — handle unknown" do
    it "returns :not_found for an unregistered handle" do
      expect(route("#omega-9999 confirm")[:status]).to eq(:not_found)
    end

    it "returns the handle in the result" do
      expect(route("#omega-9999 confirm")[:handle]).to eq("omega-9999")
    end
  end

  describe ":not_found — consumed event" do
    before do
      live_event.update!(payload: live_event.payload.merge("reply_consumed" => true))
    end

    it "returns :not_found (consumed events are not routable)" do
      expect(route("#delta-4823 something")[:status]).to eq(:not_found)
    end
  end

  describe "legacy confirmation events — fall-through behaviour" do
    let!(:conf_event) do
      Event.create_with_position!(
        conversation:, turn:, kind: "confirmation",
        payload: {
          "command"             => "disconnect",
          "confirmation_handle" => "alpha-1111"
        }
      )
    end

    it "returns :not_found when the handle matches the pattern but no event carries it" do
      # The handle matches the #<word>-<digits> pattern, so the Router runs the DB
      # lookup, but no event in the conversation has this reply_handle.
      result = route("#alpha-1111 confirm")
      expect(result[:status]).to eq(:not_found)
    end
  end
end
