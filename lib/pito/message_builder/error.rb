# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Builds an error-event payload.
    #
    # Error events carry a message_key (Pito::Copy i18n path) and optional
    # message_args. The dispatch job resolves the key to human-readable text
    # via Pito::Copy.render before persisting the event.
    #
    # == Usage
    #
    #   Pito::MessageBuilder::Error.call(
    #     message_key:  "pito.chat.show.needs_ref",
    #     message_args: {}
    #   )
    #   # => { "message_key" => "pito.chat.show.needs_ref", "message_args" => {} }
    module Error
      module_function

      # @param message_key  [String] a Pito::Copy i18n key.
      # @param message_args [Hash]   interpolation args for the key.
      # @return [Hash] string-keyed error payload.
      def call(message_key:, message_args: {})
        {
          "message_key"  => message_key.to_s,
          "message_args" => message_args
        }
      end
    end
  end
end
