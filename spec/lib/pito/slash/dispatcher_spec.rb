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

  # ── Universal --help intercept ───────────────────────────────────────────────

  describe ".call — --help flag interception" do
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
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "intercepts -h shorthand" do
      result = described_class.call(input: "/ping -h", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    it "does NOT intercept when flag is absent (handler runs normally)" do
      result = described_class.call(input: "/ping", conversation:)
      expect(result.events.first[:payload][:text]).to eq("pong")
    end

    it "renders a man-page help block containing the verb name" do
      result = described_class.call(input: "/ping --help", conversation:)
      payload = result.events.first[:payload]
      expect(payload["html"]).to be true
      body = payload["body"]
      expect(body).to include("pito-help-block")
      expect(body).to include("ping")
    end

    context "with /config igdb --help" do
      before do
        # Re-register all real handlers so config is in the registry.
        Pito::Slash::Registry.register_all!
      end

      it "renders igdb keys in the man-page body" do
        result = described_class.call(input: "/config igdb --help", conversation:)
        expect(result).to be_a(Pito::Slash::Result::Ok)
        body = result.events.first[:payload]["body"]
        expect(body).to include("client_id=")
        expect(body).to include("client_secret=")
      end
    end

    # ── Subcommand --help (args before the flag) ─────────────────────────────

    context "with /config google --help (args before the flag)" do
      before { Pito::Slash::Registry.register_all! }

      it "intercepts --help and returns Ok" do
        result = described_class.call(input: "/config google --help", conversation:)
        expect(result).to be_a(Pito::Slash::Result::Ok)
      end

      it "returns a system event" do
        result = described_class.call(input: "/config google --help", conversation:)
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    # ── -h shorthand (explicit coverage) ────────────────────────────────────

    it "intercepts -h shorthand for a registered verb" do
      result = described_class.call(input: "/ping -h", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    # ── --help mid-arg (flag appears between args) ───────────────────────────

    it "intercepts --help even when it appears mid-input (between args)" do
      # e.g. "/ping --help extra" — the regex matches \s--help anywhere
      result = described_class.call(input: "/ping --help extra", conversation:)
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    # ── Unknown verb with --help (must not crash) ────────────────────────────

    it "intercepts --help for a completely unknown verb without crashing" do
      result = described_class.call(input: "/doesnotexist --help", conversation:)
      # Expected: Ok (help renderer handles unknown verbs gracefully)
      expect(result).to be_a(Pito::Slash::Result::Ok)
    end

    # ── Case sensitivity — --HELP and -H are NOT intercepted ────────────────
    #
    # The regex is /\s--help\b|\s-h\b/ which is case-sensitive.
    # --HELP / -H are therefore treated as regular arguments, not help flags.

    it "does NOT intercept --HELP (uppercase) — handler runs normally" do
      # /ping --HELP → not intercepted → executes the ping handler → returns "pong"
      result = described_class.call(input: "/ping --HELP", conversation:)
      expect(result.events.first[:payload][:text]).to eq("pong")
    end

    it "does NOT intercept -H (uppercase) — handler runs normally" do
      result = described_class.call(input: "/ping -H", conversation:)
      expect(result.events.first[:payload][:text]).to eq("pong")
    end
  end
end
