# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Unknown do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(verb: nil, body_tokens: [], kind: :unknown, raw: "hello world"),
      conversation: Conversation.singleton
    )
  end

  describe "#call" do
    it "returns a Result::Error" do
      expect(handler.call).to be_a(Pito::Chat::Result::Error)
    end

    it "returns Error with the unknown_input message_key" do
      result = handler.call
      expect(result.message_key).to eq("pito.chat.errors.unknown_input")
    end

    it "includes the raw input in message_args" do
      result = handler.call
      expect(result.message_args).to eq({ input: "hello world" })
    end
  end
end
