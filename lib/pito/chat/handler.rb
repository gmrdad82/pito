# frozen_string_literal: true

require_relative "../grammar/handler_dsl"
require_relative "follow_up_context"
require_relative "target_resolution"

module Pito
  module Chat
    # Base class for all chat-input handlers.
    #
    # ## Contract
    #
    # Every concrete subclass MUST:
    # - Set `self.tool = :symbol` — the tool word that identifies this handler
    #   (e.g. `:list`, `:show`).
    # - Set `self.description_key = "pito.chat.<tool>.descriptions.<tool>"` — I18n key.
    # - Implement `#call` → returning one of:
    #   - `Pito::Chat::Result::Ok`    — command handled, events ready.
    #   - `Pito::Chat::Result::Error` — handler-level error.
    #
    # Unlike slash handlers, chat handlers do NOT receive an `authenticated` flag —
    # they are only reachable after the dispatcher confirms the message is not a
    # slash command.
    #
    # ## Instance accessors
    #
    # - `message` (`Pito::Chat::Message`) — parsed message (tool, body_tokens, raw).
    # - `conversation` (`Conversation`) — the active conversation record.
    # - `follow_up` (`Pito::Chat::FollowUpContext`, or nil) — present when this tool
    #   was reached via a `#<handle>` reply instead of free chat. Same tool logic
    #   runs either way; only reference resolution and result-wrapping
    #   consult it. `follow_up?` is the predicate.
    #
    # ## `inherited` reset semantics
    #
    # Same as `Pito::Slash::Handler` (also `@tool` since the rename): `@tool`,
    # `@description_key`, and grammar ivars are reset on every subclass to
    # prevent cross-handler bleed.
    class Handler
      extend Pito::Grammar::HandlerDsl
      include Pito::Chat::TargetResolution

      attr_reader :message, :conversation, :channel, :period, :follow_up, :viewport_width, :kwargs

      def initialize(message:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil, kwargs: {}, nl_eligible: true)
        @message = message
        @conversation = conversation
        @channel = channel
        @period = period
        @follow_up = follow_up
        @viewport_width = viewport_width
        @kwargs = kwargs
        @nl_eligible = nl_eligible
      end

      # True when this tool was invoked from a `#<handle>` follow-up reply rather
      # than a free-chat message. The tool logic is identical; only resolution and
      # result-wrapping branch on it.
      def follow_up?
        !@follow_up.nil?
      end

      # True (the default) when this dispatch's body may be soft-failed into the
      # NL gate (Pito::Chat::Result::Error#nl_fallback, 3.0.1 P7) if a handler
      # can't act on it. False only on a RECONSTRUCTED follow-up re-dispatch
      # (Pito::Dispatch::Router#call nl_eligible: false — see its class header)
      # — the body was built by pito, not typed by the owner, so a title-ladder
      # miss there must stay the crisp not-found, never be treated as free
      # text. Distinct from follow_up?: that ALSO turns off resolve_title/
      # ordinal resolution; nl_eligible? leaves those untouched and gates
      # ONLY the soft-fail marker.
      def nl_eligible?
        @nl_eligible
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      class << self
        # The uniform dispatch contract. Pito::Dispatch::Router
        # invokes EVERY chat tool through this single class-level entry:
        #
        #   * +context+ (Pito::Dispatch::Context) carries what handlers read today —
        #     message / conversation / follow_up / channel / period / viewport_width.
        #   * +kwargs+ carries the Router-bound arguments (a reply path's
        #     ReplyBinding output; empty for free chat).
        #
        # It simply unpacks the context into the existing keyword initializer and
        # runs the instance #call — so each concrete handler's body stays exactly
        # as written. This is the "add a tool by config + a handler" foundation:
        # any Pito::Chat::Handler subclass answers the contract for free.
        def call(kwargs:, context:)
          new(
            message:        context.message,
            conversation:   context.conversation,
            channel:        context.channel,
            period:         context.period,
            follow_up:      context.follow_up,
            viewport_width: context.viewport_width,
            kwargs:         kwargs,
            nl_eligible:    context.nl_eligible
          ).call
        end

        def tool
          @tool or raise NotImplementedError, "#{name} must define self.tool"
        end

        def tool=(value)
          @tool = value
        end

        def description_key
          @description_key or raise NotImplementedError, "#{name} must define self.description_key"
        end

        def description_key=(value)
          @description_key = value
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@tool, nil)
          subclass.instance_variable_set(:@description_key, nil)
          subclass.reset_grammar_ivars!
        end
      end
    end
  end
end
