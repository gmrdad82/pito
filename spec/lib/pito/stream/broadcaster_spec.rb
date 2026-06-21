# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe Pito::Stream::Broadcaster do
  include ActionCable::TestHelper

  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :slash, input_text: "/help") }
  let(:broadcaster) { described_class.new(conversation:) }

  def broadcast_html(message)
    message.is_a?(Hash) ? message.values.join : message.to_s
  end

  describe "#emit" do
    it "persists an event" do
      expect {
        broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })
      }.to change(Event, :count).by(1)
    end

    it "assigns the correct kind and payload to the event" do
      event = broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })
      expect(event.kind).to eq("echo")
      expect(event.payload).to eq("text" => "/help")
    end

    it "increments the position for each event" do
      first = broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })
      second = broadcaster.emit(turn:, kind: :system, payload: { message_key: "pito.slash.help.intro", message_args: { count: 2 } })
      expect(first.position).to eq(1)
      expect(second.position).to eq(2)
    end

    it "returns the persisted event" do
      event = broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })
      expect(event).to be_persisted
      expect(event.id).to be_present
    end

    it "broadcasts to the conversation stream" do
      stream = "pito:conversation:#{conversation.uuid}"
      expect {
        broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })
      }.to have_broadcasted_to(stream)
    end

    it "raises for an invalid event kind" do
      expect {
        broadcaster.emit(turn:, kind: "bogus", payload: {})
      }.to raise_error(Pito::Stream::EventPayload::ValidationError)
    end
  end

  describe "#replace_event" do
    it "broadcasts a Turbo Stream replace targeting event_<id>" do
      event = broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })

      expect { broadcaster.replace_event(event) }
        .to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
          html = broadcast_html(msg)
          expect(html).to include('action="replace"')
          expect(html).to include(%(target="event_#{event.id}"))
        }
    end

    it "returns the event" do
      event = broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })
      result = broadcaster.replace_event(event)
      expect(result).to eq(event)
    end
  end

  describe "#broadcast_auth_update" do
    before do
      allow(Channel).to receive(:order).with(:handle).and_return([])
      allow(Notification).to receive_message_chain(:unread, :count).and_return(0)
    end

    it "broadcasts to the conversation stream" do
      expect {
        broadcaster.broadcast_auth_update(authenticated: true)
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}")
    end

    it "broadcasts a replace for pito-auth-gate" do
      expect {
        broadcaster.broadcast_auth_update(authenticated: true)
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include("pito-auth-gate")
        expect(html).to include('data-authenticated="true"')
      }
    end

    it "broadcasts a replace for pito-chatbox" do
      expect {
        broadcaster.broadcast_auth_update(authenticated: false)
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include("pito-chatbox")
      }
    end

    it "broadcasts a replace for pito-mini-status" do
      expect {
        broadcaster.broadcast_auth_update(authenticated: true)
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include("pito-mini-status")
      }
    end
  end

  describe "#broadcast_settings_update" do
    it "broadcasts a replace for pito-settings to the conversation stream" do
      allow(AppSetting).to receive(:sound_enabled?).and_return(true)
      allow(AppSetting).to receive(:fx_enabled?).and_return(false)

      expect {
        broadcaster.broadcast_settings_update
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include('action="replace"')
        expect(html).to include("pito-settings")
        expect(html).to include('data-sound="true"')
        expect(html).to include('data-fx="false"')
      }
    end
  end

  describe "#broadcast_event turn grouping" do
    it "wraps an echo in a #turn_<id> container appended to the scrollback" do
      echo = conversation.events.create!(turn:, position: 1, kind: :echo, payload: { text: "/help" })

      expect { broadcaster.broadcast_event(echo) }
        .to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
          html = broadcast_html(msg)
          expect(html).to include('target="pito-scrollback"')
          expect(html).to include(%(id="turn_#{turn.id}"))
        }
    end

    it "appends a non-echo event INTO its turn container when a preceding event exists" do
      # The echo occupies position 1 (lower), so the system event at position 2
      # is NOT the first event in the turn — it appends into the existing container.
      conversation.events.create!(turn:, position: 1, kind: :echo, payload: { text: "/help" })
      result = conversation.events.create!(
        turn:, position: 2, kind: :system,
        payload: { message_key: "pito.slash.help.intro", message_args: { count: 1 } }
      )

      expect { broadcaster.broadcast_event(result) }
        .to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
          html = broadcast_html(msg)
          expect(html).to include(%(target="turn_#{turn.id}"))
        }
    end

    it "opens a #turn_<id> container for a lone :system event with no preceding echo (async summary case)" do
      # This reproduces the echo-less async-job turn: SyncVideosJob creates a new
      # turn and emits only a :system summary. Without the fix the append targeted a
      # missing DOM id; now the first event in the turn always opens its container.
      system_event = conversation.events.create!(
        turn:, position: 1, kind: :system,
        payload: { message_key: "pito.slash.help.intro", message_args: { count: 0 } }
      )

      expect { broadcaster.broadcast_event(system_event) }
        .to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
          html = broadcast_html(msg)
          expect(html).to include('target="pito-scrollback"')
          expect(html).to include(%(id="turn_#{turn.id}"))
        }
    end
  end

  describe "#emit_thinking" do
    it "creates a thinking event with a shuffled cycling order over the dictionary" do
      words = I18n.t("pito.copy.thinking.slash.doing")
      event = broadcaster.emit_thinking(turn:, dictionary: "slash")

      expect(event.kind).to eq("thinking")
      expect(event.payload).to include("dictionary" => "slash")
      expect(event.payload).to have_key("started_at")
      # order is a permutation of every index into the doing array, so the verb
      # can cycle through all of them without repeating mid-rotation.
      expect(event.payload["order"]).to match_array(0...words.length)
    end

    it "broadcasts the thinking event into the turn container" do
      # In real flows an echo opens the turn container first; emit_thinking comes
      # second so its broadcast appends INTO the existing #turn_<id> container.
      broadcaster.emit(turn:, kind: :echo, payload: { text: "/help" })

      expect {
        broadcaster.emit_thinking(turn:, dictionary: "chat")
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include(%(target="turn_#{turn.id}"))
        expect(html).to include("pito-thinking")
      }
    end
  end

  describe "#resolve_thinking" do
    it "updates the thinking event payload and broadcasts a replace" do
      thinking = broadcaster.emit_thinking(turn:, dictionary: "slash")

      expect {
        broadcaster.resolve_thinking(turn:)
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include("action=\"replace\"")
        expect(html).to include(%(target="event_#{thinking.id}"))
      }

      thinking.reload
      expect(thinking.payload["resolved"]).to eq(true)
      expect(thinking.payload["elapsed_seconds"]).to be >= 0
    end

    it "resolves word_index to the verb cycled last (order + elapsed)" do
      thinking = broadcaster.emit_thinking(turn:, dictionary: "slash")
      order    = thinking.payload["order"]
      thinking.update!(payload: thinking.payload.merge("started_at" => 12.seconds.ago.iso8601))

      broadcaster.resolve_thinking(turn:)

      thinking.reload
      interval = Pito::Event::ThinkingComponent::INTERVAL_SECONDS
      step     = thinking.payload["elapsed_seconds"] / interval
      expect(thinking.payload["word_index"]).to eq(order[step % order.length])
    end

    it "is a no-op when no thinking event exists" do
      expect {
        broadcaster.resolve_thinking(turn:)
      }.not_to have_broadcasted_to("pito:conversation:#{conversation.uuid}")
    end
  end

  describe "#complete_turn" do
    it "marks the turn complete and broadcasts pito:done" do
      expect {
        broadcaster.complete_turn(turn:)
      }.to have_broadcasted_to("pito:conversation:#{conversation.uuid}").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include("action=\"append\"")
        expect(html).to include("pito--done-dispatch")
      }

      turn.reload
      expect(turn.completed_at).to be_present
    end
  end

  # ── class-level global broadcasts ────────────────────────────────────────────

  describe ".broadcast_global_mini_status" do
    it "broadcasts a pito-mini-status replace to pito:global" do
      expect {
        described_class.broadcast_global_mini_status
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include('action="replace"')
        expect(html).to include("pito-mini-status")
      }
    end

    it "does not raise even if ActionCable is unavailable" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to).and_raise(StandardError, "boom")
      expect { described_class.broadcast_global_mini_status }.not_to raise_error
    end
  end

  describe ".broadcast_global_conversation_row" do
    it "broadcasts a conversation_row replace to pito:global" do
      expect {
        described_class.broadcast_global_conversation_row(conversation:)
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include('action="replace"')
        expect(html).to include("conversation_row_#{conversation.uuid}")
      }
    end

    it "does not raise even if ActionCable is unavailable" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to).and_raise(StandardError, "boom")
      expect { described_class.broadcast_global_conversation_row(conversation:) }.not_to raise_error
    end
  end

  describe ".broadcast_global_settings_update" do
    it "broadcasts a pito-settings replace to pito:global" do
      # Stub AppSetting flags — avoids requiring encryption in pure unit tests.
      allow(AppSetting).to receive(:sound_enabled?).and_return(true)
      allow(AppSetting).to receive(:fx_enabled?).and_return(true)

      expect {
        described_class.broadcast_global_settings_update
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include('action="replace"')
        expect(html).to include("pito-settings")
        expect(html).to include('data-sound="true"')
      }
    end

    it "reflects the current AppSetting values in the broadcast" do
      allow(AppSetting).to receive(:sound_enabled?).and_return(false)
      allow(AppSetting).to receive(:fx_enabled?).and_return(false)

      expect {
        described_class.broadcast_global_settings_update
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = broadcast_html(msg)
        expect(html).to include('data-sound="false"')
        expect(html).to include('data-fx="false"')
      }
    end

    it "does not raise even if ActionCable is unavailable" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to).and_raise(StandardError, "boom")
      expect { described_class.broadcast_global_settings_update }.not_to raise_error
    end
  end
end
