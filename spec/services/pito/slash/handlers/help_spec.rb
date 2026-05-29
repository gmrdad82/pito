# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Slash::Handlers::Help, type: :service do
  describe "#call" do
    it "returns a Result::Ok" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(
        position: 1,
        input_kind: "slash",
        input_text: "/help"
      )
      invocation = Pito::Slash::Invocation.new(
        verb: :help,
        args: [],
        kwargs: {},
        raw: "/help"
      )
      handler = described_class.new(invocation:, conversation:)

      result = handler.call

      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "produces N+1 events where N is the registry size" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(
        position: 1,
        input_kind: "slash",
        input_text: "/help"
      )
      invocation = Pito::Slash::Invocation.new(
        verb: :help,
        args: [],
        kwargs: {},
        raw: "/help"
      )
      handler = described_class.new(invocation:, conversation:)

      result = handler.call
      registry_size = Pito::Slash::Registry.size

      expect(result.events.size).to eq(registry_size + 1)
    end

    it "includes an intro event with the registry count" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(
        position: 1,
        input_kind: "slash",
        input_text: "/help"
      )
      invocation = Pito::Slash::Invocation.new(
        verb: :help,
        args: [],
        kwargs: {},
        raw: "/help"
      )
      handler = described_class.new(invocation:, conversation:)

      result = handler.call
      intro_event = result.events.first

      expect(intro_event[:kind]).to eq("assistant_text")
      expect(intro_event[:payload][:message_key]).to eq("pito.slash.help.intro")
      expect(intro_event[:payload][:message_args][:count]).to eq(Pito::Slash::Registry.size)
    end

    it "includes one entry event per registered handler" do
      conversation = Conversation.create!
      turn = conversation.turns.create!(
        position: 1,
        input_kind: "slash",
        input_text: "/help"
      )
      invocation = Pito::Slash::Invocation.new(
        verb: :help,
        args: [],
        kwargs: {},
        raw: "/help"
      )
      handler = described_class.new(invocation:, conversation:)

      result = handler.call
      entry_events = result.events[1..] # Skip intro

      entry_events.each do |event|
        expect(event[:kind]).to eq("assistant_text")
        expect(event[:payload][:message_key]).to eq("pito.slash.help.entry")
        expect(event[:payload][:message_args]).to have_key(:verb)
        expect(event[:payload][:message_args]).to have_key(:description)
      end
    end
  end
end
