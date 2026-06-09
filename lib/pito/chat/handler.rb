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
    #   runs either way; only reference resolution (T18.2) and result-wrapping
    #   (T18.3) consult it. `follow_up?` is the predicate.
    #
    # ## `inherited` reset semantics
    #
    # Same as `Pito::Slash::Handler`: `@verb`, `@description_key`, and grammar ivars
    # are reset on every subclass to prevent cross-handler bleed.
    class Handler
      extend Pito::Grammar::HandlerDsl
      include Pito::Chat::TargetResolution

      attr_reader :message, :conversation, :channel, :follow_up

      def initialize(message:, conversation:, channel: nil, follow_up: nil)
        @message = message
        @conversation = conversation
        @channel = channel
        @follow_up = follow_up
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
