# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::Stream::Broadcaster do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: "slash", input_text: "/help") }
  let(:broadcaster) { described_class.new(conversation:) }

  describe "#emit" do
    it "persists an event" do
      expect {
        broadcaster.emit(turn:, kind: "echo", payload: { text: "/help" })
      }.to change(Event, :count).by(1)
    end

    it "assigns the correct kind and payload to the event" do
      event = broadcaster.emit(turn:, kind: "echo", payload: { text: "/help" })
      expect(event.kind).to eq("echo")
      expect(event.payload).to eq("text" => "/help")
    end

    it "increments the position for each event" do
      first = broadcaster.emit(turn:, kind: "echo", payload: { text: "/help" })
      second = broadcaster.emit(turn:, kind: "assistant_text", payload: { message_key: "pito.slash.help.intro", message_args: { count: 2 } })
      expect(first.position).to eq(1)
      expect(second.position).to eq(2)
    end

    it "returns the persisted event" do
      event = broadcaster.emit(turn:, kind: "echo", payload: { text: "/help" })
      expect(event).to be_persisted
      expect(event.id).to be_present
    end

    it "broadcasts to the conversation stream" do
      stream = "pito:conversation:#{conversation.uuid}"
      expect {
        broadcaster.emit(turn:, kind: "echo", payload: { text: "/help" })
      }.to have_broadcasted_to(stream)
    end

    it "raises for an invalid event kind" do
      expect {
        broadcaster.emit(turn:, kind: "bogus", payload: {})
      }.to raise_error(Pito::Stream::EventPayload::ValidationError)
    end
  end

  describe "#broadcast_event turn grouping" do
    def broadcast_html(message)
      message.is_a?(Hash) ? message.values.join : message.to_s
    end

    it "wraps an echo in a #turn_<id> container appended to the scrollback" do
      echo = conversation.events.create!(turn:, position: 1, kind: "echo", payload: { text: "/help" })

      expect { broadcaster.broadcast_event(echo) }
        .to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
          html = broadcast_html(msg)
          expect(html).to include('target="pito-scrollback"')
          expect(html).to include(%(id="turn_#{turn.id}"))
        }
    end

    it "appends a non-echo event INTO its turn container" do
      result = conversation.events.create!(
        turn:, position: 2, kind: "assistant_text",
        payload: { message_key: "pito.slash.help.intro", message_args: { count: 1 } }
      )

      expect { broadcaster.broadcast_event(result) }
        .to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
          html = broadcast_html(msg)
          expect(html).to include(%(target="turn_#{turn.id}"))
        }
    end
  end
end
