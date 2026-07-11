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
    # - Set `self.verb = :symbol` — the verb word that identifies this handler
    #   (e.g. `:list`, `:show`).
    # - Set `self.description_key = "pito.chat.<verb>.descriptions.<verb>"` — I18n key.
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
    # - `message` (`Pito::Chat::Message`) — parsed message (verb, body_tokens, raw).
    # - `conversation` (`Conversation`) — the active conversation record.
    # - `follow_up` (`Pito::Chat::FollowUpContext`, or nil) — present when this verb
    #   was reached via a `#<handle>` reply instead of free chat. Same verb logic
    #   runs either way; only reference resolution and result-wrapping
    #   consult it. `follow_up?` is the predicate.
    #
    # ## `inherited` reset semantics
    #
    # Same as `Pito::Slash::Handler`: `@verb`, `@description_key`, and grammar ivars
    # are reset on every subclass to prevent cross-handler bleed.
    class Handler
      extend Pito::Grammar::HandlerDsl
      include Pito::Chat::TargetResolution

      attr_reader :message, :conversation, :channel, :period, :follow_up, :viewport_width, :kwargs

      def initialize(message:, conversation:, channel: nil, period: nil, follow_up: nil, viewport_width: nil, kwargs: {})
        @message = message
        @conversation = conversation
        @channel = channel
        @period = period
        @follow_up = follow_up
        @viewport_width = viewport_width
        @kwargs = kwargs
      end

      # True when this verb was invoked from a `#<handle>` follow-up reply rather
      # than a free-chat message. The verb logic is identical; only resolution and
      # result-wrapping branch on it.
      def follow_up?
        !@follow_up.nil?
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      class << self
        # The uniform dispatch contract. Pito::Dispatch::Router
        # invokes EVERY chat verb through this single class-level entry:
        #
        #   * +context+ (Pito::Dispatch::Context) carries what handlers read today —
        #     message / conversation / follow_up / channel / period / viewport_width.
        #   * +kwargs+ carries the Router-bound arguments (a reply path's
        #     ReplyBinding output; empty for free chat).
        #
        # It simply unpacks the context into the existing keyword initializer and
        # runs the instance #call — so each concrete handler's body stays exactly
        # as written. This is the "add a verb by config + a handler" foundation:
        # any Pito::Chat::Handler subclass answers the contract for free.
        def call(kwargs:, context:)
          new(
            message:        context.message,
            conversation:   context.conversation,
            channel:        context.channel,
            period:         context.period,
            follow_up:      context.follow_up,
            viewport_width: context.viewport_width,
            kwargs:         kwargs
          ).call
        end

        def verb
          @verb or raise NotImplementedError, "#{name} must define self.verb"
        end

        def verb=(value)
          @verb = value
        end

        def description_key
          @description_key or raise NotImplementedError, "#{name} must define self.description_key"
        end

        def description_key=(value)
          @description_key = value
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@verb, nil)
          subclass.instance_variable_set(:@description_key, nil)
          subclass.reset_grammar_ivars!
        end
      end
    end
  end
end
