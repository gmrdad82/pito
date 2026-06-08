# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::ChatResultAdapter, type: :service do
  describe ".call" do
    it "maps Chat::Result::Ok events to a FollowUp::Result::Append (kinds preserved as symbols)" do
      events = [
        { kind: :system,   payload: { "a" => 1 } },
        { kind: :enhanced, payload: { "b" => 2 } }
      ]
      result = described_class.call(Pito::Chat::Result::Ok.new(events:))

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events).to eq(events)
    end

    it "passes a confirmation event straight through (Confirmable verbs)" do
      ok = Pito::Chat::Result::Ok.new(events: [
        { kind: :confirmation, payload: { "command" => "game_delete" } }
      ])

      result = described_class.call(ok)

      expect(result.events).to eq([ { kind: :confirmation, payload: { "command" => "game_delete" } } ])
    end

    it "maps Chat::Result::Error to FollowUp::Result::Error" do
      err = Pito::Chat::Result::Error.new(message_key: "pito.x", message_args: { a: 1 })

      result = described_class.call(err)

      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.x")
      expect(result.message_args).to eq({ a: 1 })
    end

    it "raises for anything else" do
      expect { described_class.call(:nope) }.to raise_error(ArgumentError, /cannot adapt/)
    end
  end
end
