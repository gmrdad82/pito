# frozen_string_literal: true

module Pito
  module Chat
    class Parser
      # Raised when a slash-prefixed input reaches the Chat parser.
      # Slash commands are routed upstream before reaching this parser.
      NotAChatMessage = Class.new(StandardError)

      # Conversational hellos/goodbyes, matched against the WHOLE normalized input
      # (see #normalized_phrase) — case-insensitive, punctuation-tolerant, single
      # or multi-word. They short-circuit to the :greet / :farewell verbs before
      # command parsing.
      GREETINGS = Set.new([
        "hi", "hii", "hiya", "hey", "heya", "hello", "helloo", "hello there",
        "hey there", "hi there", "hola", "yo", "sup", "howdy", "greetings",
        "good morning", "good afternoon", "good evening", "morning", "evening",
        "whats up", "what's up", "wassup"
      ]).freeze

      FAREWELLS = Set.new([
        "bye", "byebye", "bye bye", "goodbye", "good bye", "cya", "see ya",
        "see you", "see'ya", "seeya", "see you later", "see ya later", "later",
        "laters", "ttyl", "talk later", "ciao", "adios", "adiós", "hasta luego",
        "hasta la vista", "peace", "peace out", "farewell", "good night",
        "goodnight", "gn", "take care", "toodles"
      ]).freeze

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

        # Conversational greetings / farewells: match the WHOLE input as a phrase
        # (single OR multi-word) before command parsing, so "Hi", "good bye", and
        # "hasta luego!" all route to a friendly reply.
        phrase = normalized_phrase
        return Message.new(verb: :greet,    body_tokens: [], kind: :new_turn, raw: @raw) if GREETINGS.include?(phrase)
        return Message.new(verb: :farewell, body_tokens: [], kind: :new_turn, raw: @raw) if FAREWELLS.include?(phrase)

        # Read the first word token as the candidate verb. An "@"-fused verb
        # ("@ai" in any case — the lexer emits the bare "@" plus the word) is
        # fused HERE, only when the word is adjacent (no space: "@ ai" stays
        # two tokens) and the fused, downcased token is a registered verb —
        # channel handles like @all keep their two-token shape for their own
        # consumers.
        candidate_verb = first&.type == :word ? first.value.to_sym : nil
        if candidate_verb
          advance
        elsif (fused = fused_at_verb(first))
          candidate_verb = fused
          advance
          advance
        end

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

      # The whole input, normalized for phrase matching: downcased, trailing
      # punctuation stripped ("Hi!" → "hi"), inner whitespace collapsed.
      def normalized_phrase
        @raw.to_s.strip.downcase.gsub(/[[:punct:]]+\z/, "").strip.gsub(/\s+/, " ")
      end

      def current_token
        @tokens[@pos]
      end

      # ":@ai" from ["@", "ai"] — nil unless the shape matches AND the fused
      # token is a registered chat verb (downcased, so @AI/@Ai/@aI all fuse).
      def fused_at_verb(first)
        follower = @tokens[@pos + 1]
        return nil unless first&.type == :at && follower&.type == :word && !follower.preceded_by_space

        fused = :"@#{follower.value.downcase}"
        Pito::Grammar::Registry.specs_for_alias(namespace: :chat, token: fused) ? fused : nil
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
