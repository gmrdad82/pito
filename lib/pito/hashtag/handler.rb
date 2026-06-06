# frozen_string_literal: true

require_relative "../grammar/handler_dsl"

module Pito
  module Hashtag
    # Base class for all hashtag-input handlers.
    #
    # ## Contract
    #
    # Every concrete subclass MUST:
    # - Set `self.handle = :symbol` — the hashtag stem (e.g. `:reply`).
    #   The dispatcher resolves `#reply-1234` → stem `:reply` → this handler.
    # - Implement `#call` → returning one of:
    #   - `Pito::Hashtag::Result::Ok`    — handled successfully.
    #   - `Pito::Hashtag::Result::Error` — handler-level error.
    #
    # ## Instance accessors
    #
    # - `message` (`Pito::Hashtag::Message`) — parsed message (handle, body_tokens, raw).
    # - `conversation` (`Conversation`) — the active conversation record.
    #
    # Unlike slash handlers, hashtag handlers carry no `authenticated` flag —
    # authentication is enforced upstream by the chat controller before any
    # hashtag input reaches the dispatcher.
    #
    # ## `inherited` reset semantics
    #
    # `Handler.inherited` clears `@handle` and all grammar ivars on each subclass
    # to prevent cross-handler bleed.
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
        def handle
          @handle or raise NotImplementedError, "#{name} must define self.handle"
        end

        def handle=(value)
          @handle = value
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@handle, nil)
          subclass.reset_grammar_ivars!
        end
      end
    end
  end
end
