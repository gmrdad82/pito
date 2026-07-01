# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Compact do
  let(:conversation) { create(:conversation) }
  let(:authenticated) { true }
  let(:invocation) { instance_double(Pito::Slash::Invocation, raw: "/compact", args: [], kwargs: {}, verb: :compact) }
  subject(:handler) { described_class.new(invocation:, conversation:, authenticated:) }

  describe "#call" do
    it "returns a confirmation event" do
      result = handler.call
      expect(result).to be_a(Pito::Slash::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:confirmation)
    end

    it "the confirmation payload carries command 'compact'" do
      result = handler.call
      payload = result.events.first[:payload]
      expect(payload["command"]).to eq("compact")
    end

    context "when --help flag is present" do
      let(:invocation) { instance_double(Pito::Slash::Invocation, raw: "/compact --help", args: [], kwargs: {}, verb: :compact) }

      it "returns a system help event" do
        allow(handler).to receive(:help?).and_return(true)
        result = handler.call
        expect(result).to be_a(Pito::Slash::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["body"]).to include("/compact")
      end
    end
  end
end
