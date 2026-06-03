# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Hashtag::Dispatcher do
  let(:conversation) { Conversation.singleton }

  before do
    conversation.turns.destroy_all
    described_class # ensure autoload
  end

  before do
    stub_const("Pito::Hashtag::Handlers::ReplyTest", Class.new(Pito::Hashtag::Handler) do
      self.handle = :reply

      def call
        Pito::Hashtag::Result::Ok.new(events: [
          { kind: :system, payload: { text: "reply ok" } }
        ])
      end
    end)

    Pito::Hashtag::Registry.register(Pito::Hashtag::Handlers::ReplyTest)
  end

  after do
    Pito::Hashtag::Registry.instance_variable_get(:@registry)&.delete(:reply)
  end

  describe ".call" do
    it "returns Ok for a registered handle" do
      result = described_class.call(input: "#reply-1234 hello", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
      expect(result.events).to eq([ { kind: :system, payload: { text: "reply ok" } } ])
    end

    it "falls back to Reply when no specific handler is registered" do
      conf_turn = conversation.turns.create!(input_kind: :slash, input_text: "/test", position: 99)
      Event.create_with_position!(
        conversation:, turn: conf_turn,
        kind: "confirmation",
        payload: { command: "test", confirmation_handle: "alpha-1234", authenticated: true }
      )

      result = described_class.call(input: "#alpha-1234 hello", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Ok)
    end

    it "returns Error(parse_failed) for invalid input" do
      result = described_class.call(input: "#", conversation:)
      expect(result).to be_a(Pito::Hashtag::Result::Error)
      expect(result.message_key).to eq("pito.hashtag.errors.parse_failed")
    end
  end
end
