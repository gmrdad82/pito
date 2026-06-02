# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::List do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw: "list videos"),
      conversation: Conversation.singleton
    )
  end

  describe "#call" do
    it "returns a Result::Ok" do
      expect(handler.call).to be_a(Pito::Chat::Result::Ok)
    end

    it "returns Ok with one system event" do
      result = handler.call
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "references the expected i18n key in the payload" do
      result = handler.call
      payload = result.events.first[:payload]
      expect(payload[:message_key]).to eq("pito.chat.list.fake_response")
      expect(payload[:message_args]).to eq({ count: 5, sample_title: "Sample video title" })
    end
  end
end
