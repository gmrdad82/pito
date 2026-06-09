# frozen_string_literal: true

module Pito
  module Chat
    class Parser
      # Raised when a slash-prefixed input reaches the Chat parser.
      # Slash commands are routed upstream before reaching this parser.
      NotAChatMessage = Class.new(StandardError)

      # Parse a sequence of tokens into a Message.
      #
      # tokens       — Array of Pito::Lex::Token from the lexer.
      # raw:         — The original input string.
      # conversation — The Conversation record (reserved for future use).
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

        spec = candidate_verb && Pito::Grammar::Registry.specs_for_alias(namespace: :chat, token: candidate_verb)
        if spec
          # Recognised verb → new turn. Canonicalize the verb to the spec's name
          # so aliases dispatch correctly (e.g. `rm` → :delete, `ls` → :list);
          # the handler registry only knows canonical verbs.
          body_tokens = tokens_until_eof
          Message.new(verb: spec.name, body_tokens:, kind: :new_turn, raw: @raw)
        else
          # No recognised verb → unknown.
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
    end
  end
end
