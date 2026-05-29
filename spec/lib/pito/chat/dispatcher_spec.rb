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
          { kind: :assistant_text, payload: { text: "list ok" } }
        ])
      end
    end)

    Pito::Chat::Registry.register(Pito::Chat::Handlers::ListTest)
  end

  # Stub the refinement demo handler (doesn't exist yet in C3 but is needed
  # for the :refinement branch).
  before do
    unless Pito::Chat::Handlers.const_defined?(:RefineDemo)
      stub_const("Pito::Chat::Handlers::RefineDemo", Class.new(Pito::Chat::Handler) do
        def call
          Pito::Chat::Result::Refine.new(events: [
            { kind: :assistant_text, payload: { text: "refine ok" } }
          ])
        end
      end)
    end
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
      expect(result.events).to eq([ { kind: :assistant_text, payload: { text: "list ok" } } ])
    end

    it "returns Error(verb_not_implemented) for a recognised but unregistered verb" do
      # :show is in RECOGNIZED_VERBS but no handler is registered for it.
      result = described_class.call(input: "show something", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.verb_not_implemented")
      expect(result.message_args).to eq({ verb: :show })
    end

    it "returns Error(unknown_input) for unrecognised input with no open turn" do
      result = described_class.call(input: "hello", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.unknown_input")
      expect(result.message_args).to eq({ input: "hello" })
    end

    it "returns a Refine result for refinement input when an open turn exists" do
      conversation.turns.create!(
        input_text: "list videos",
        input_kind: "chat",
        position: 1,
        created_at: 5.minutes.ago
      )

      result = described_class.call(input: "more stuff", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Refine)
      expect(result.events).to eq([ { kind: :assistant_text, payload: { text: "refine ok" } } ])
    end

    it "returns Error(misrouted_slash) for slash-prefixed input" do
      result = described_class.call(input: "/help", conversation:)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.misrouted_slash")
      expect(result.message_args).to eq({ raw: "/help" })
    end
  end
end
