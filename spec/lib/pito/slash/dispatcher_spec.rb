# frozen_string_literal: true

require "rails_helper"

class DispatcherTestHandler < Pito::Slash::Handler
  self.verb = :ping
  self.description_key = "pito.slash.help.descriptions.ping"

  def call
    Pito::Slash::Result::Ok.new(events: [ { kind: "assistant_text", payload: { text: "pong" } } ])
  end
end

RSpec.describe Pito::Slash::Dispatcher do
  let(:conversation) { Conversation.create! }

  before do
    Pito::Slash::Registry.register(DispatcherTestHandler)
  end

  after do
    Pito::Slash::Registry.instance_variable_set(:@registry, {})
  end

  describe ".call" do
    it "returns Result::Ok for a registered verb" do
      result = described_class.call(input: "/ping", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events).to eq([ { kind: "assistant_text", payload: { text: "pong" } } ])
    end

    it "returns Result::Error for an unknown verb" do
      result = described_class.call(input: "/nonexistent", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.unknown_verb")
      expect(result.message_args[:verb]).to eq(:nonexistent)
    end

    it "returns Result::Error for malformed input (no slash)" do
      result = described_class.call(input: "hello", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.parse_failed")
    end

    it "returns Result::Error for malformed input (slash only)" do
      result = described_class.call(input: "/", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Error)
      expect(result.message_key).to eq("pito.slash.errors.parse_failed")
    end
  end
end
