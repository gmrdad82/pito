# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Unknown do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(verb: nil, body_tokens: [], kind: :unknown, raw: "boo!"),
      conversation: Conversation.singleton
    )
  end

  describe "#call" do
    it "returns a Result::Ok — unparseable input gets a witty reply, not an error" do
      expect(handler.call).to be_a(Pito::Chat::Result::Ok)
    end

    it "emits a single :system event with non-empty text" do
      result = handler.call
      expect(result.events.length).to eq(1)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload][:text]).to be_present
    end

    it "always nudges toward help" do
      expect(handler.call.events.first[:payload][:text].downcase).to include("help")
    end
  end
end
