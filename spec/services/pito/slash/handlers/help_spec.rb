# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Help, type: :service do
  let(:conversation) { Conversation.create! }

  def build_handler(authenticated: true)
    invocation = Pito::Slash::Invocation.new(verb: :help, args: [], kwargs: {}, raw: "/help")
    described_class.new(invocation:, conversation:, authenticated:)
  end

  describe "#call — authenticated" do
    it "returns a Result::Ok with one event" do
      expect(build_handler.call).to be_a(Pito::Slash::Result::Ok)
    end

    it "returns exactly 1 event (consolidated expandable format)" do
      result = build_handler.call
      expect(result.events.size).to eq(1)
    end

    it "event is system with a text: intro" do
      event = build_handler.call.events.first
      expect(event[:kind]).to eq("system")
      expect(event[:payload][:text]).to include(Pito::Slash::Registry.size.to_s)
    end

    it "visible expand_lines covers up to VISIBLE_COUNT commands" do
      payload = build_handler.call.events.first[:payload]
      expect(payload[:expand_lines]).to be_an(Array)
      expect(payload[:expand_lines].size).to be <= described_class::VISIBLE_COUNT
    end

    it "overflow commands go into expand_detail" do
      total = Pito::Slash::Registry.size
      payload = build_handler.call.events.first[:payload]
      expected_overflow = [ total - described_class::VISIBLE_COUNT, 0 ].max
      expect(Array(payload[:expand_detail]).size).to eq(expected_overflow)
    end
  end

  describe "#call — unauthenticated" do
    it "returns a Result::Ok" do
      expect(build_handler(authenticated: false).call).to be_a(Pito::Slash::Result::Ok)
    end

    it "shows only the authentication instruction" do
      event = build_handler(authenticated: false).call.events.first
      expect(event[:payload][:text]).to include("/login")
    end

    it "does not include the full command list" do
      event = build_handler(authenticated: false).call.events.first
      expect(event[:payload][:expand_lines]).to be_nil
    end
  end
end
