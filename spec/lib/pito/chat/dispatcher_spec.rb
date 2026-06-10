# frozen_string_literal: true

require "rails_helper"

# Test handler registered for :list in this spec's register block.
RSpec.describe Pito::Chat::Dispatcher do
  let(:conversation) { Conversation.singleton }

  before do
    conversation.turns.destroy_all

    # Register a test :list handler so the dispatcher can find it.
    # The handler is defined inline below.
    described_class # ensure autoload
  end

  # A minimal handler that returns Ok — used to test the :new_turn dispatch path.
  before do
    stub_const("Pito::Chat::Handlers::ListTest", Class.new(Pito::Chat::Handler) do
      self.verb = :list
      self.description_key = "pito.chat.test.descriptions.list_test"

      def call
        Pito::Chat::Result::Ok.new(events: [
          { kind: :system, payload: { text: "list ok" } }
        ])
      end
    end)

    Pito::Chat::Registry.register(Pito::Chat::Handlers::ListTest)
  end

  # Stub the unknown handler (doesn't exist yet in C3).
  before do
    unless Pito::Chat::Handlers.const_defined?(:Unknown)
      stub_const("Pito::Chat::Handlers::Unknown", Class.new(Pito::Chat::Handler) do
        def call
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.errors.unknown_input",
            message_args: { input: message.raw }
          )
        end
      end)
    end
  end

  after do
    # Clean up the test handler from the registry so other specs aren't affected.
    Pito::Chat::Registry.instance_variable_get(:@registry)&.delete(:list_test)
  end

  describe ".call" do
    it "returns Ok for a recognised and registered verb" do
      result = described_class.call(input: "list videos", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events).to eq([ { kind: :system, payload: { text: "list ok" } } ])
    end

    it "returns Error(verb_not_implemented) for a recognised but unregistered verb" do
      # :find has a chat grammar spec but no handler registered.
      result = described_class.call(input: "find something", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.verb_not_implemented")
      expect(result.message_args).to eq({ verb: :find })
    end

    it "returns Error(unknown_input) for unrecognised input with no open turn" do
      result = described_class.call(input: "hello", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.unknown_input")
      expect(result.message_args).to eq({ input: "hello" })
    end

    it "returns Error(unknown_input) for no-verb input even when an open turn exists" do
      # Refinement machinery has been removed — no-verb messages always fall through to :unknown.
      turn = conversation.turns.create!(
        input_text: "list videos",
        input_kind: :chat,
        position: 1,
        created_at: 5.minutes.ago
      )
      conversation.events.create!(
        turn:, position: 1,
        kind: :system,
        payload: { message_key: "pito.chat.list.descriptions.list", message_args: {} }
      )

      result = described_class.call(input: "more stuff", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.unknown_input")
    end

    it "returns Error(misrouted_slash) for slash-prefixed input" do
      result = described_class.call(input: "/help", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.misrouted_slash")
      expect(result.message_args).to eq({ raw: "/help" })
    end

    # ── --help interception ────────────────────────────────────────────────────

    describe "--help interception" do
      it "returns a system event with an html man page for 'show --help'" do
        result = described_class.call(input: "show --help", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        event = result.events.first
        expect(event[:kind]).to eq(:system)
        expect(event[:payload]["html"]).to be(true)
      end

      it "the show --help body includes 'Usage:'" do
        result = described_class.call(input: "show --help", conversation:)
        body = result.events.first[:payload]["body"]
        expect(body).to include("Usage:")
      end

      it "the show --help body includes the show usage line" do
        result = described_class.call(input: "show --help", conversation:)
        body = result.events.first[:payload]["body"]
        expect(body).to include("show")
      end

      it "routes 'delete game --help' to the delete-game noun page" do
        result = described_class.call(input: "delete game --help", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        body = result.events.first[:payload]["body"]
        # Noun page for delete game uses id-only wording, not title
        expect(body).to include("delete game")
        expect(body).not_to include("title")
      end

      it "routes 'show game --help' to the show-game noun page (title|id)" do
        result = described_class.call(input: "show game --help", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        body = result.events.first[:payload]["body"]
        expect(body).to include("show game")
        expect(body).to include("title")
      end

      it "routes 'delete --help' (no noun) to the delete verb-level page (lists forms)" do
        result = described_class.call(input: "delete --help", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        body = result.events.first[:payload]["body"]
        # Verb-level page must mention both noun forms
        expect(body).to include("game")
        expect(body).to include("video")
      end

      it "routes 'list --help' (no noun) to the list noun-index page (Forms group)" do
        result = described_class.call(input: "list --help", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        body = result.events.first[:payload]["body"]
        expect(body).to include("Forms")
        expect(body).to include("list games")
        expect(body).to include("list videos")
        expect(body).to include("list channels")
        expect(body).to include("--help")
        # Must NOT be the Game::ListHelp noun page (which has Columns:)
        expect(body).not_to include("Columns:")
      end

      it "routes 'list games --help' to the Game::ListHelp noun page" do
        result = described_class.call(input: "list games --help", conversation:)
        expect(result).to be_a(Pito::Chat::Result::Ok)
        body = result.events.first[:payload]["body"]
        games_body = Pito::MessageBuilder::Game::ListHelp.call["body"]
        expect(body).to eq(games_body)
      end
    end
  end
end
