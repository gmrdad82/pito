# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handler do
  # A throwaway concrete subclass — the base class is abstract.
  let(:handler_class) do
    Class.new(described_class) do
      self.tool = :test
      self.description_key = "pito.chat.test.descriptions.test"
      def call = Pito::Chat::Result::Ok.new(events: [])
    end
  end

  let(:message)      { instance_double(Pito::Chat::Message) }
  let(:conversation) { instance_double(Conversation) }

  describe "free-chat entry (no follow-up context)" do
    subject(:handler) { handler_class.new(message:, conversation:) }

    it "exposes message + conversation and reports follow_up? false" do
      expect(handler.message).to eq(message)
      expect(handler.conversation).to eq(conversation)
      expect(handler.follow_up).to be_nil
      expect(handler.follow_up?).to be(false)
    end

    it "defaults period to nil" do
      expect(handler.period).to be_nil
    end
  end

  describe "period threading" do
    it "exposes a period passed at construction" do
      handler = handler_class.new(message:, conversation:, period: "28d")
      expect(handler.period).to eq("28d")
    end

    it "accepts any period token from the cycle" do
      %w[7d 28d 3m 1y lifetime].each do |token|
        handler = handler_class.new(message:, conversation:, period: token)
        expect(handler.period).to eq(token)
      end
    end
  end

  describe "follow-up entry (with a FollowUpContext)" do
    let(:source_event) { instance_double(Event) }
    let(:context)      { Pito::Chat::FollowUpContext.new(source_event:, rest: "5") }

    subject(:handler) { handler_class.new(message:, conversation:, follow_up: context) }

    it "reports follow_up? true and exposes the context" do
      expect(handler.follow_up?).to be(true)
      expect(handler.follow_up).to eq(context)
      expect(handler.follow_up.rest).to eq("5")
      expect(handler.follow_up.source_event).to eq(source_event)
    end

    it "still serves the same message + conversation accessors" do
      expect(handler.message).to eq(message)
      expect(handler.conversation).to eq(conversation)
    end
  end

  describe Pito::Chat::FollowUpContext do
    it "carries source_event + rest" do
      ctx = described_class.new(source_event: :evt, rest: "show 5")
      expect(ctx.source_event).to eq(:evt)
      expect(ctx.rest).to eq("show 5")
    end
  end
end
