# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::RefineDemo do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(verb: nil, body_tokens: [], kind: :refinement, raw: "add ctr"),
      conversation: Conversation.singleton
    )
  end

  describe "#call" do
    it "returns a Result::Refine" do
      expect(handler.call).to be_a(Pito::Chat::Result::Refine)
    end

    it "returns Refine with one system event" do
      result = handler.call
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "references the acknowledged i18n key" do
      result = handler.call
      payload = result.events.first[:payload]
      expect(payload[:message_key]).to eq("pito.chat.refine_demo.acknowledged")
      expect(payload[:message_args]).to eq({ input: "add ctr" })
    end
  end
end
