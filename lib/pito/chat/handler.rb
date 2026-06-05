# frozen_string_literal: true

require_relative "../grammar/handler_dsl"

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
    #   - `Pito::Chat::Result::Ok`     — command handled, events ready.
    #   - `Pito::Chat::Result::Error`  — handler-level error.
    #   - `Pito::Chat::Result::Refine` — input is a refinement of an open turn.
    #
    # Unlike slash handlers, chat handlers do NOT receive an `authenticated` flag —
    # they are only reachable after the dispatcher confirms the message is not a
    # slash command and is not refinement input for an open turn.
    #
    # ## Instance accessors
    #
    # - `message` (`Pito::Chat::Message`) — parsed message (verb, body_tokens, raw).
    # - `conversation` (`Conversation`) — the active conversation record.
    #
    # ## `inherited` reset semantics
    #
    # Same as `Pito::Slash::Handler`: `@verb`, `@description_key`, and grammar ivars
    # are reset on every subclass to prevent cross-handler bleed.
    class Handler
      extend Pito::Grammar::HandlerDsl

      attr_reader :message, :conversation

      def initialize(message:, conversation:)
        @message = message
        @conversation = conversation
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
