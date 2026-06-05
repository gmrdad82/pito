# frozen_string_literal: true

module Pito
  module Hashtag
    module Result
      # Command succeeded. Creates a new Turn containing the events.
      Ok = Data.define(:events) do
        # events — Array of { kind:, payload: } hashes
      end

      # Command failed. Creates a new Turn containing echo + error events.
      Error = Data.define(:message_key, :message_args) do
        # message_key  — String i18n key
        # message_args — Hash of interpolation args
      end
    end
  end
end
