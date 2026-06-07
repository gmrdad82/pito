# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Builds a plain-text payload — the simplest message type.
    #
    # Accepts either a Pito::Copy key (dotted i18n path) or a pre-rendered string.
    # If args are provided the key is rendered via Pito::Copy.render; otherwise
    # the value is used as-is if it does not look like a copy key, or rendered
    # with empty args if it does.
    #
    # == Usage
    #
    #   Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: "foo")
    #   # => { "text" => "I couldn't find foo..." }
    #
    #   Pito::MessageBuilder::Text.call("Something went wrong")
    #   # => { "text" => "Something went wrong" }
    module Text
      module_function

      # @param key_or_text [String] a Pito::Copy i18n key (dotted) or a plain string.
      # @param args        [Hash]   interpolation args passed to Pito::Copy.render.
      # @return [Hash] { "text" => String }
      def call(key_or_text, **args)
        text =
          if args.any? || copy_key?(key_or_text)
            Pito::Copy.render(key_or_text.to_s, args)
          else
            key_or_text.to_s
          end
        { "text" => text }
      end

      # Returns true when the string looks like a Pito::Copy key (dotted path
      # starting with "pito.").
      def copy_key?(str)
        str.to_s.start_with?("pito.")
      end
    end
  end
end
