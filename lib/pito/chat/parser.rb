# frozen_string_literal: true

module Pito
  module Chat
    class Parser
      # The set of opening words that trigger a new chat turn.
      # Extend this array as new verbs are added. This constant lives here
      # (not in Registry) so the parser can classify independently of
      # handler registration state.
      RECOGNIZED_VERBS = %i[list show find].freeze

      # Raised when a slash-prefixed input reaches the Chat parser.
      # Slash commands are routed upstream before reaching this parser.
      NotAChatMessage = Class.new(StandardError)

      # Parse a sequence of tokens into a Message.
      #
      # tokens       — Array of Pito::Lex::Token from the lexer.
      # raw:         — The original input string.
      # conversation — The Conversation record, needed to probe whether a
      #                refinement-eligible Turn exists.
      #
      # Returns a Pito::Chat::Message.
      # Raises NotAChatMessage if the input starts with a slash.
      def self.call(tokens, raw:, conversation:)
        new(tokens, raw, conversation).parse
      end

      private_class_method :new

      def initialize(tokens, raw, conversation)
        @tokens = tokens
        @raw = raw
        @conversation = conversation
        @pos = 0
      end

      def parse
        first = current_token

        # Guard: slash messages must never reach the Chat parser.
        raise NotAChatMessage, "input must not start with /" if first&.type == :slash

        # Read the first word token as the candidate verb.
        candidate_verb = first&.type == :word ? first.value.to_sym : nil
        advance if candidate_verb

        if candidate_verb && RECOGNIZED_VERBS.include?(candidate_verb)
          # Recognised verb → new turn.
          body_tokens = tokens_until_eof
          Message.new(verb: candidate_verb, body_tokens:, kind: :new_turn, raw: @raw)
        elsif refinement_eligible?
          # No recognised verb, but a recent Turn exists → refinement.
          body_tokens = tokens_until_eof
          Message.new(verb: nil, body_tokens:, kind: :refinement, raw: @raw)
        else
          # No recognised verb and no open Turn → unknown.
          Message.new(verb: nil, body_tokens: [], kind: :unknown, raw: @raw)
        end
      end

      private

      def current_token
        @tokens[@pos]
      end

      def advance
        @pos += 1
      end

      def eof?
        current_token&.type == :eof
      end

      def tokens_until_eof
        result = []
        until eof?
          result << current_token
          advance
        end
        result
      end

      # A Turn is "open" (refinement-eligible) when the conversation has a
      # most-recent Turn that was created within the last 30 minutes AND that
      # Turn has result events beyond the echo.  An echo-only Turn is still
      # being dispatched by ChatDispatchJob and must not be treated as a
      # refinement target for the incoming command.
      OPEN_TURN_TIMEOUT = 30.minutes

      def refinement_eligible?
        turn = Turn.last_for(@conversation)
        return false unless turn && turn.created_at >= OPEN_TURN_TIMEOUT.ago

        turn.events.where.not(kind: "echo").exists?
      end
    end
  end
end
