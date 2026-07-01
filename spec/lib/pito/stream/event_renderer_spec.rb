# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Stream::EventRenderer do
  let(:conversation) { Conversation.create! }
  let(:turn) { conversation.turns.create!(position: 1, input_kind: :slash, input_text: "/help") }

  # Helper: build an unsaved event stub with the given kind and payload.
  def event_for(kind, payload = {})
    Event.new(
      conversation:,
      turn:,
      kind:,
      payload:,
      position: 1
    )
  end

  # ── COMPONENT_CLASSES map ──────────────────────────────────────────────────

  describe "COMPONENT_CLASSES" do
    it "is frozen" do
      expect(described_class::COMPONENT_CLASSES).to be_frozen
    end

    it "maps every registered kind to a Class" do
      described_class::COMPONENT_CLASSES.each do |kind, klass|
        expect(klass).to be_a(Class), "expected #{kind} to map to a Class, got #{klass.inspect}"
      end
    end
  end

  # ── component_for / build_component ───────────────────────────────────────

  describe ".component_for" do
    it "returns an EchoComponent for kind 'echo'" do
      event = event_for("echo", text: "/help")
      expect(described_class.component_for(event)).to be_a(Pito::Event::EchoComponent)
    end

    it "returns a ThinkingComponent for kind 'thinking'" do
      event = event_for("thinking", dictionary: "slash", word_index: 0, started_at: Time.current.iso8601)
      expect(described_class.component_for(event)).to be_a(Pito::Event::ThinkingComponent)
    end

    it "returns a SystemComponent for kind 'system'" do
      event = event_for("system", message_key: "pito.slash.help.intro", message_args: { count: 1 })
      expect(described_class.component_for(event)).to be_a(Pito::Event::SystemComponent)
    end

    it "returns an EnhancedComponent for kind 'enhanced'" do
      event = event_for("enhanced", content: "hello")
      expect(described_class.component_for(event)).to be_a(Pito::Event::EnhancedComponent)
    end

    it "returns a SystemFollowUpComponent for kind 'system_follow_up'" do
      event = event_for("system_follow_up", message_key: "pito.slash.help.intro", message_args: { count: 1 })
      expect(described_class.component_for(event)).to be_a(Pito::Event::SystemFollowUpComponent)
    end

    it "returns an EnhancedFollowUpComponent for kind 'enhanced_follow_up'" do
      event = event_for("enhanced_follow_up", content: "hello")
      expect(described_class.component_for(event)).to be_a(Pito::Event::EnhancedFollowUpComponent)
    end

    it "returns a ConfirmationComponent for kind 'confirmation'" do
      event = event_for("confirmation", prompt: "Continue?", action: "confirm")
      expect(described_class.component_for(event)).to be_a(Pito::Event::ConfirmationComponent)
    end

    it "returns a ConfirmationFollowUpComponent for kind 'confirmation_follow_up'" do
      event = event_for("confirmation_follow_up", prompt: "Continue?", action: "confirm")
      expect(described_class.component_for(event)).to be_a(Pito::Event::ConfirmationFollowUpComponent)
    end

    it "returns an ErrorComponent for kind 'error'" do
      event = event_for("error", text: "something went wrong")
      expect(described_class.component_for(event)).to be_a(Pito::Event::ErrorComponent)
    end

    it "keeps the reply_handle by default (repliable message)" do
      event = event_for("system", body: "hi", reply_handle: "xy-1234", reply_target: "game_detail")
      component = described_class.component_for(event)
      expect(component.reply_handle).to eq("xy-1234")
    end

    it "strips reply_handle/reply_target when suppress_reply: true (public share page)" do
      event = event_for("system", body: "hi", reply_handle: "xy-1234", reply_target: "game_detail")
      component = described_class.component_for(event, suppress_reply: true)
      expect(component.reply_handle).to be_nil
      # non-destructive: a default render of the same event still carries the handle
      expect(described_class.component_for(event).reply_handle).to eq("xy-1234")
    end
  end

  describe ".build_component" do
    it "raises ArgumentError for an unregistered kind" do
      expect {
        described_class.build_component("bogus", {})
      }.to raise_error(ArgumentError, /No component registered for event kind: "bogus"/)
    end

    it "raises ArgumentError for nil kind" do
      expect {
        described_class.build_component(nil, {})
      }.to raise_error(ArgumentError)
    end

    it "accepts kind as a Symbol (stringified via to_s)" do
      expect {
        described_class.build_component(:echo, { text: "/help" })
      }.not_to raise_error
    end
  end

  # ── indifferent_payload ───────────────────────────────────────────────────

  describe ".indifferent_payload" do
    it "converts a String-keyed Hash to HashWithIndifferentAccess" do
      event = event_for("echo", "text" => "/help")
      result = described_class.indifferent_payload(event)
      expect(result).to be_a(HashWithIndifferentAccess)
      expect(result[:text]).to eq("/help")
      expect(result["text"]).to eq("/help")
    end

    it "passes a non-Hash payload through unchanged" do
      # Event#payload is always a Hash in practice, but the renderer is defensive.
      event = event_for("echo", {})
      allow(event).to receive(:payload).and_return("raw string")
      result = described_class.indifferent_payload(event)
      expect(result).to eq("raw string")
    end
  end

  # ── render ────────────────────────────────────────────────────────────────

  describe ".render" do
    it "returns a non-empty HTML string for a persisted echo event" do
      event = Event.create!(
        conversation:, turn:, position: 1,
        kind: :echo, payload: { text: "/help" }
      )
      html = described_class.render(event)
      expect(html).to be_a(String)
      expect(html).not_to be_empty
    end

    it "returns a non-empty HTML string for a persisted thinking event" do
      event = Event.create!(
        conversation:, turn:, position: 1,
        kind: :thinking,
        payload: {
          dictionary: "slash",
          word_index: 0,
          started_at: Time.current.iso8601
        }
      )
      html = described_class.render(event)
      expect(html).to be_a(String)
      expect(html).not_to be_empty
    end

    it "returns a non-empty HTML string for a persisted error event" do
      event = Event.create!(
        conversation:, turn:, position: 1,
        kind: :error, payload: { text: "oops" }
      )
      html = described_class.render(event)
      expect(html).to be_a(String)
      expect(html).not_to be_empty
    end
  end
end
