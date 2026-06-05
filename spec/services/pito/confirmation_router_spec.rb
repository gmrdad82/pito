# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ConfirmationRouter, type: :service do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(
      input_kind: :slash, input_text: "/disconnect @pito", position: 1
    )
  end
  let!(:pending_event) do
    Event.create_with_position!(
      conversation:, turn:, kind: "confirmation",
      payload: {
        command: "disconnect",
        confirmation_handle: "alpha-1111",
        channel_id: 42,
        authenticated: true
      }
    )
  end

  def route(input)
    described_class.call(input:, conversation:)
  end

  describe "valid confirm" do
    it "returns the event and :confirm action" do
      result = route("#alpha-1111 confirm")
      expect(result[:event]).to eq(pending_event)
      expect(result[:action]).to eq(:confirm)
    end
  end

  describe "valid cancel" do
    it "returns the event and :cancel action" do
      result = route("#alpha-1111 cancel")
      expect(result[:action]).to eq(:cancel)
    end
  end

  describe "case-insensitive matching" do
    it "accepts CONFIRM in uppercase" do
      result = route("#alpha-1111 CONFIRM")
      expect(result[:error]).to be_nil
    end

    it "lowercases the handle before lookup" do
      result = route("#ALPHA-1111 confirm")
      expect(result[:event]).to eq(pending_event)
    end
  end

  describe "handle not found" do
    it "returns error: :not_found" do
      result = route("#omega-9999 confirm")
      expect(result[:error]).to eq(:not_found)
      expect(result[:handle]).to eq("omega-9999")
    end
  end

  describe "already resolved event" do
    before do
      pending_event.update!(payload: pending_event.payload.merge("resolved" => true))
    end

    it "returns error: :not_found (resolved events are not routable)" do
      result = route("#alpha-1111 confirm")
      expect(result[:error]).to eq(:not_found)
    end
  end

  describe "invalid format" do
    it "returns error: :invalid_format for plain text" do
      expect(route("hello")[:error]).to eq(:invalid_format)
    end

    it "returns error: :invalid_format for a slash command" do
      expect(route("/disconnect @pito")[:error]).to eq(:invalid_format)
    end

    it "returns error: :invalid_format for wrong digit count" do
      expect(route("#alpha-12 confirm")[:error]).to eq(:invalid_format)
    end
  end
end
