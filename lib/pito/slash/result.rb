# frozen_string_literal: true

module Pito
  module Slash
    module Result
      Ok = Data.define(:events) do
        # events — Array of { kind:, payload: } hashes
      end

      Error = Data.define(:message_key, :message_args) do
        # message_key  — String i18n key
        # message_args — Hash of interpolation args
      end

      NeedsConfirmation = Data.define(:prompt_key, :prompt_args, :command_text) do
        # prompt_key   — String i18n key for the confirmation prompt
        # prompt_args  — Hash of interpolation args
        # command_text — String, the original command text
      end
    end
  end
end
