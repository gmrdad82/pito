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
    end
  end
end
