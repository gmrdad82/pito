# frozen_string_literal: true

require "rails_helper"

class DispatcherTestHandler < Pito::Slash::Handler
  self.verb = :ping
  self.description_key = "pito.slash.help.descriptions.ping"

  def call
    Pito::Slash::Result::Ok.new(events: [ { kind: :system, payload: { text: "pong" } } ])
  end
end

RSpec.describe Pito::Slash::Dispatcher do
  let(:conversation) { Conversation.create! }

  around do |example|
    old_registry = Pito::Slash::Registry.instance_variable_get(:@registry)&.dup || {}
    Pito::Slash::Registry.instance_variable_set(:@registry, {})
    Pito::Slash::Registry.register(DispatcherTestHandler)
    example.run
    Pito::Slash::Registry.instance_variable_set(:@registry, old_registry)
  end

  describe ".call" do
    it "returns Result::Ok for a registered verb" do
      result = described_class.call(input: "/ping", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events).to eq([ { kind: :system, payload: { text: "pong" } } ])
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

  # ── P56 — Universal --help intercept ─────────────────────────────────────────

  describe ".call — --help flag interception (P56)" do
    it "intercepts --help for registered verbs and returns Ok (not the handler's output)" do
      result = described_class.call(input: "/ping --help", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      # The handler would return "pong"; help returns a system event with body/table_rows.
      events = result.events
      expect(events.first[:payload][:text]).not_to eq("pong")
    end

    it "intercepts --help for unregistered verbs (no unknown_verb error)" do
      result = described_class.call(input: "/connect --help", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
      expect(result.events.first[:kind]).to eq("system")
    end

    it "intercepts -h shorthand" do
      result = described_class.call(input: "/ping -h", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "does NOT intercept when flag is absent (handler runs normally)" do
      result = described_class.call(input: "/ping", conversation:)
      expect(result.events.first[:payload][:text]).to eq("pong")
    end

    it "renders per-command body containing the verb name" do
      result = described_class.call(input: "/ping --help", conversation:)
      body = result.events.first[:payload][:body]
      expect(body).to include("ping")
    end

    context "with /config igdb --help" do
      before do
        # Re-register all real handlers so config is in the registry.
        Pito::Slash::Registry.register_all!
      end

      it "renders igdb key table rows" do
        result = described_class.call(input: "/config igdb --help", conversation:)
        expect(result).to be_a(Pito::Slash::Result::Ok)
        rows = result.events.first[:payload][:table_rows]
        keys = rows.map { |r| r[:key] }
        expect(keys).to include("client_id=", "client_secret=")
      end
    end
  end
end
