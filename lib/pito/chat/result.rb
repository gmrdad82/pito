# frozen_string_literal: true

module Pito
  module Chat
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

      # Refinement of an existing open Turn. Appends events to the most
      # recent Turn instead of creating a new one.
      Refine = Data.define(:events) do
        # events — Array of { kind:, payload: } hashes
      end
    end
  end
end
