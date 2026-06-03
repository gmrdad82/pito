# frozen_string_literal: true

module Pito
  module Slash
    # Parser: converts a slash-command token stream (from Pito::Lex::Lexer) into a
    # Pito::Slash::Invocation.
    #
    # Design — normalizer-backed adapter:
    #
    # 1. LEGACY GENERIC SLURP (always runs, always produces the Invocation).
    #    Positional args and keyword args are extracted by the generic positional/kwarg
    #    slurp implemented in #parse.  This is the sole source of Invocation#args and
    #    Invocation#kwargs.  URLs, dotted ids, /publish 42, /disconnect @x-y, quoted
    #    strings, and numeric coercion all behave identically to the original parser.
    #
    # 2. GRAMMAR REGISTRY HOOK (layered on top, conservative no-op for Invocation).
    #    After building the Invocation, #grammar_spec_for looks up a registered
    #    Pito::Grammar::Spec via Pito::Grammar::Registry.specs_for_alias.  The spec,
    #    when present, is available for callers (autocomplete, validation) to inspect
    #    slot definitions and enum constraints.
    #
    #    WHY NO MUTATION: Invocation has no :slots field.  Mutating args/kwargs to
    #    apply enum canonicalisation would break the frozen parser_spec contract for
    #    inputs that are already correctly typed by the legacy slurp.  Therefore the
    #    grammar hook is intentionally a pass-through — it does NOT change the
    #    Invocation for any tested input.  When the Invocation shape gains a :spec or
    #    :slots field in a future step, this hook is the right place to populate it.
    #
    # 3. SAFE WHEN REGISTRY IS EMPTY.
    #    The registry is populated at app boot (to_prepare / register_all!).  In unit
    #    specs the registry may be empty.  grammar_spec_for always returns nil in that
    #    case; the Invocation is unaffected.  Do NOT call register_all! from here.
    class Parser
      NotASlashCommand = Class.new(StandardError)
      MissingVerb       = Class.new(StandardError)

      def self.call(tokens, raw:)
        new(tokens, raw).parse
      end

      private_class_method :new

      def initialize(tokens, raw)
        @tokens = tokens
        @raw = raw
        @pos = 0
      end

      def parse
        raise NotASlashCommand, "input must start with /" unless current_token&.type == :slash
        advance

        raise MissingVerb, "expected a verb after /" unless current_token&.type == :word
        verb = current_token.value.to_sym
        advance

        args   = []
        kwargs = {}

        until eof?
          if kwarg_key?
            key = current_token.value.to_sym
            advance # skip the key word
            advance # skip colon/equals
            value = read_value
            kwargs[key] = value
          else
            args << read_value
          end
        end

        invocation = Invocation.new(verb:, args:, kwargs:, raw: @raw)

        # Grammar hook: look up a registered spec for optional use by callers.
        # Returns nil when no spec is registered — never mutates the Invocation.
        grammar_spec_for(verb)

        invocation
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

      # A word followed by :colon or :equals signals a keyword argument
      def kwarg_key?
        return false unless current_token&.type == :word

        next_tok = @tokens[@pos + 1]
        next_tok && (next_tok.type == :colon || next_tok.type == :equals)
      end

      def read_value
        tok = current_token

        # Quoted strings are already complete — return immediately.
        if tok.type == :string
          advance
          return tok.value
        end

        # Slurp consecutive tokens until we hit a kwarg boundary
        # (word followed by colon or equals) or EOF.
        parts = []
        loop do
          break if eof?
          break if kwarg_boundary?

          parts << current_token.value.to_s
          advance
        end

        joined = parts.join

        # Preserve numeric return type when the result is a pure number.
        return joined.to_i if joined.match?(/\A\d+\z/)
        return joined.to_f if joined.match?(/\A\d+\.\d+\z/)

        joined
      end

      # True when the current token marks the start of a new kwarg key
      # (word followed by :colon or :equals).
      def kwarg_boundary?
        current_token.type == :word &&
          @tokens[@pos + 1]&.type.in?([ :colon, :equals ])
      end

      # Returns the Pito::Grammar::Spec registered for this verb (canonical name or
      # alias) in the :slash namespace, or nil if no spec is registered.
      # Safe to call when the registry is empty (returns nil).
      def grammar_spec_for(verb)
        Pito::Grammar::Registry.specs_for_alias(namespace: :slash, token: verb)
      rescue NameError
        # Grammar::Registry may not be defined in very early load contexts.
        nil
      end
    end
  end
end
