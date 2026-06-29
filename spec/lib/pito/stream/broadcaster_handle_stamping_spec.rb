# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::Stream::Broadcaster, "handle stamping" do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(position: 1, input_kind: :chat, input_text: "hi")
  end
  let(:broadcaster) { described_class.new(conversation:) }

  describe "#emit — HANDLE_STAMPING_KINDS" do
    it "stamps reply_handle on :system events" do
      event = broadcaster.emit(turn:, kind: :system, payload: { message_key: "pito.slash.help.intro", message_args: { count: 1 } })
      expect(event.payload["reply_handle"]).to be_present
    end

    it "stamps reply_handle on :enhanced events" do
      event = broadcaster.emit(turn:, kind: :enhanced, payload: { message_key: "pito.slash.help.intro", message_args: { count: 1 } })
      expect(event.payload["reply_handle"]).to be_present
    end

    it "stamps reply_handle on :confirmation events" do
      payload = { "command" => "test", "body" => "Confirm?" }
      event = broadcaster.emit(turn:, kind: :confirmation, payload:)
      expect(event.payload["reply_handle"]).to be_present
    end

    it "does NOT stamp reply_handle on :echo events" do
      event = broadcaster.emit(turn:, kind: :echo, payload: { text: "hi" })
      expect(event.payload["reply_handle"]).to be_nil
    end

    it "does NOT stamp reply_handle on :error events" do
      event = broadcaster.emit(turn:, kind: :error, payload: { text: "oops" })
      expect(event.payload["reply_handle"]).to be_nil
    end

    it "does NOT double-stamp a payload already carrying reply_handle" do
      original_handle = "my-handle"
      payload = { message_key: "pito.slash.help.intro", message_args: { count: 1 }, "reply_handle" => original_handle }
      event = broadcaster.emit(turn:, kind: :system, payload:)
      expect(event.payload["reply_handle"]).to eq(original_handle)
    end
  end
end
