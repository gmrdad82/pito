# frozen_string_literal: true

require "rails_helper"

# Unit spec for the agnostic Router (plan-0.9.5 T8.10) — the single
# config-driven execution path for chat verbs + hashtag verb-replies.
#
# Coverage: config-driven dispatch (the verb→handler map now lives in
# verbs.yml `chat.dispatch`, not Ruby), alias canonicalization, chat-surface
# availability gating, kwarg binding (a reply's FollowUpContext#bound consumed
# into the contract), the uniform `call(kwargs:, context:)` invocation, Result
# passthrough, unknown-verb + misrouted-slash + --help behaviour.
RSpec.describe Pito::Dispatch::Router, type: :dispatch do
  let(:conversation) { Conversation.singleton }

  before { conversation.turns.destroy_all }

  # An echo handler that records what the Router handed it and returns a
  # sentinel Ok — stubbed in for a verb's configured dispatch class so we can
  # observe routing + binding without running the real handler.
  def echo_handler
    Class.new do
      class << self
        attr_reader :last_kwargs, :last_context, :sentinel

        def call(kwargs:, context:)
          @last_kwargs  = kwargs
          @last_context = context
          @sentinel     = Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: { text: "echo" } } ])
        end
      end
    end
  end

  # ── config-driven dispatch + alias canonicalization ──────────────────────────

  describe "config-driven dispatch (verbs.yml chat.dispatch)" do
    it "routes a recognised verb to the class declared in config" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::List", fake)

      result = described_class.call(input: "list videos", conversation:)

      expect(fake.last_context).to be_a(Pito::Dispatch::Context)
      expect(result).to equal(fake.sentinel) # Result passthrough — unchanged
    end

    it "canonicalizes a verb alias before the config lookup (ls → list)" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::List", fake)

      described_class.call(input: "ls games", conversation:)

      expect(fake.last_context).to be_a(Pito::Dispatch::Context)
    end

    # Table-driven: every chat verb the config declares a dispatch for is reached
    # through the Router with zero per-verb Router code (the add-a-verb foundation).
    Pito::Dispatch::Config.reload!
    chat_verbs = Pito::Dispatch::Config.data[:verbs].filter_map do |verb, body|
      dispatch = body.dig(:chat, :dispatch)
      { verb:, class_string: dispatch } if dispatch.is_a?(String)
    end

    it "declares a dispatch class for every implemented chat verb (sanity)" do
      expect(chat_verbs.map { |r| r[:verb] }).to include(:list, :show, :analyze, :help, :greet)
    end

    chat_verbs.each do |row|
      it "resolves verbs.#{row[:verb]}.chat.dispatch to a handler answering the contract" do
        klass = "Pito::#{row[:class_string]}".constantize
        params = klass.method(:call).parameters
        expect(params).to include([ :keyreq, :kwargs ], [ :keyreq, :context ])
      end
    end
  end

  # ── context threading ────────────────────────────────────────────────────────

  describe "context threading" do
    it "carries channel / period / viewport_width / conversation into the context" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::List", fake)

      described_class.call(
        input: "list videos", conversation:,
        channel: "@xyz", period: "28d", viewport_width: "1024"
      )

      ctx = fake.last_context
      expect(ctx.conversation).to eq(conversation)
      expect(ctx.channel).to eq("@xyz")
      expect(ctx.period).to eq("28d")
      expect(ctx.viewport_width).to eq("1024")
      expect(ctx.follow_up).to be_nil
      expect(ctx.follow_up?).to be(false)
    end
  end

  # ── kwarg binding (reply bound → contract kwargs) ────────────────────────────

  describe "kwarg binding" do
    it "delivers no bound kwargs on the typed free-chat path" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::List", fake)

      described_class.call(input: "list videos", conversation:)

      expect(fake.last_kwargs).to eq({})
    end

    it "consumes FollowUpContext#bound into the contract kwargs on a reply path" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::Show", fake)
      source_event = instance_double(Event, payload: { "reply_target" => "game_list" })
      bound        = { ref: "sentinel-ref" }
      context      = Pito::Chat::FollowUpContext.new(source_event:, rest: "5", bound:)

      described_class.call(input: "show 5", conversation:, follow_up: context)

      expect(fake.last_kwargs).to eq(bound)
      expect(fake.last_context.follow_up).to equal(context)
      expect(fake.last_context.follow_up?).to be(true)
    end
  end

  # ── availability gating (chat surface) ───────────────────────────────────────

  describe "chat-surface availability" do
    it "returns verb_not_implemented for a recognised verb with no chat dispatch (find)" do
      result = described_class.call(input: "find something", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.verb_not_implemented")
      expect(result.message_args).to eq({ verb: :find })
    end
  end

  # ── unknown / misrouted ──────────────────────────────────────────────────────

  describe "non-verb input" do
    it "returns a witty :system reply for unrecognised input" do
      result = described_class.call(input: "boo!", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:kind]).to eq(:system)
      expect(result.events.first[:payload][:text]).to be_present
    end

    it "returns Error(misrouted_slash) for slash-prefixed input" do
      result = described_class.call(input: "/help", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.errors.misrouted_slash")
      expect(result.message_args).to eq({ raw: "/help" })
    end
  end

  # ── --help interception (byte-parity with the retired Dispatcher) ────────────

  describe "--help interception" do
    it "renders the verb man page for 'show --help'" do
      result = described_class.call(input: "show --help", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      event = result.events.first
      expect(event[:kind]).to eq(:system)
      expect(event[:payload]["html"]).to be(true)
      expect(event[:payload]["body"]).to include("Usage:")
    end

    it "routes 'show game --help' to the show-game noun page (id-only)" do
      result = described_class.call(input: "show game --help", conversation:)
      body   = result.events.first[:payload]["body"]

      expect(body).to include("show game")
      expect(body).not_to include("title")
    end

    it "routes 'help --help' to the nonsense easter-egg page" do
      result = described_class.call(input: "help --help", conversation:)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["html"]).to be(true)
      expect(result.events.first[:payload]["body"]).to include("manual")
    end

    it "plain 'help' (no flag) renders the verb catalogue" do
      result = described_class.call(input: "help", conversation:)
      body   = result.events.first[:payload]["body"]

      expect(body).to include("GAMES")
      expect(body).to include("VIDEOS")
      expect(body).to include("CHANNELS")
    end

    # ── verb-level fallback (extracted noun isn't a real noun page) ────────────
    #
    # extract_noun grabs the first plain word after the verb, ref tokens (#id)
    # aside — for a dual-ref connective form that word is the connector itself
    # ("to"), which has no `pito.chat_help.link.to` page. help_page must fall
    # back to the verb-level page rather than returning nil and letting the
    # Router dispatch a --help message into the handler.

    it "falls back to the verb-level page for 'link #1 to game #1 --help' (extracted noun :to has no page) and never dispatches the handler" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::Link", fake)

      result = described_class.call(input: "link #1 to game #1 --help", conversation:)
      body   = result.events.first[:payload]["body"]

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["html"]).to be(true)
      expect(body).to include("Usage:")
      expect(body).to include("link game")
      expect(body).to include("link video")
      expect(fake.last_kwargs).to be_nil  # handler never invoked
      expect(fake.last_context).to be_nil
    end

    it "falls back to the verb-level page for a nonsense noun ('delete bogus --help') and never dispatches the handler" do
      fake = echo_handler
      stub_const("Pito::Chat::Handlers::Delete", fake)

      result = described_class.call(input: "delete bogus --help", conversation:)
      body   = result.events.first[:payload]["body"]

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(body).to include("Usage:")
      expect(body).to include("delete game")
      expect(body).to include("delete video")
      expect(fake.last_kwargs).to be_nil  # handler never invoked
      expect(fake.last_context).to be_nil
    end

    it "still routes 'delete game --help' to the delete-game noun page (real noun, unaffected by the fallback)" do
      result = described_class.call(input: "delete game --help", conversation:)
      body   = result.events.first[:payload]["body"]

      expect(body).to include("delete game")
      expect(body).to include("#id")
    end
  end
end
