# frozen_string_literal: true

module Pito
  module Chat
    class Dispatcher
      def self.call(input:, conversation:, channel: nil, follow_up: nil)
        new(input, conversation, channel, follow_up).dispatch
      end

      private_class_method :new

      def initialize(input, conversation, channel = nil, follow_up = nil)
        @input = input
        @conversation = conversation
        @channel = channel
        @follow_up = follow_up
      end

      def dispatch
        tokens = Pito::Lex::Lexer.call(@input)
        message = parse(tokens)
        return message if message.is_a?(Pito::Chat::Result::Error)

        case message.kind
        when :new_turn
          dispatch_new_turn(message)
        when :unknown
          dispatch_unknown(message)
        end
      end

      private

      def parse(tokens)
        Pito::Chat::Parser.call(tokens, raw: @input, conversation: @conversation)
      rescue Pito::Chat::Parser::NotAChatMessage
        Pito::Chat::Result::Error.new(
          message_key: "pito.chat.errors.misrouted_slash",
          message_args: { raw: @input }
        )
      end

      def dispatch_new_turn(message)
        handler_class = Pito::Chat::Registry.lookup(message.verb)

        if handler_class.nil?
          return Pito::Chat::Result::Error.new(
            message_key: "pito.chat.errors.verb_not_implemented",
            message_args: { verb: message.verb }
          )
        end

        if message.raw.match?(/(?:\A|\s)--help(?:\s|\z)/)
          if message.verb == :help
            payload = Pito::Slash::HelpRenderer.nonsense_payload
            return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
          end

          noun    = extract_noun(message)
          payload = Pito::MessageBuilder::CommandHelp.call(message.verb, noun:)
          return Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ]) if payload
        end

        handler = handler_class.new(message:, conversation: @conversation, channel: @channel, follow_up: @follow_up)
        handler.call
      end

      # Extract the noun token (first plain word after the verb) from the raw input,
      # skipping the `--help` / `-h` flags.  Returns a Symbol or nil.
      #
      # The lexer splits "--help" into :unknown(-) :unknown(-) :word("help"), so we
      # cannot rely on body_tokens alone.  Instead we scan the raw string for the
      # first word that is not preceded by one or more "-" dashes.
      #
      # Examples:
      #   "delete game --help"   → :game
      #   "delete --help"        → nil
      #   "import videos --help" → :videos
      def extract_noun(message)
        # Strip the verb from the front and look for the first bare word token.
        # A "bare word" starts a word char (no leading dash); we skip -flag tokens.
        raw_after_verb = message.raw.to_s.sub(/\A\s*\S+\s*/, "")

        # Split on whitespace; return the first token that is a plain word (no leading -)
        # and is not a number or a quoted arg (we only care about noun words like "game").
        raw_after_verb.split.each do |token|
          next if token.start_with?("-")
          next if token.match?(/\A\d+\z/)   # skip bare numbers
          next if token.start_with?('"')     # skip quoted strings

          return token.downcase.to_sym
        end

        nil
      end

      def dispatch_unknown(message)
        handler = Pito::Chat::Handlers::Unknown.new(message:, conversation: @conversation, channel: @channel, follow_up: @follow_up)
        handler.call
      end
    end
  end
end
