# frozen_string_literal: true

module Pito
  module Chat
    module Result
      # Command succeeded. Creates a new Turn containing the events.
      #
      # `consume:` (default true) only matters when this result is the answer to a
      # `#<handle>` reply: it decides whether the source event is marked
      # reply_consumed afterwards. A "soft" success that didn't actually act —
      # e.g. a not-found ("Don't have 23.") — sets `consume: false` so the source
      # list stays repliable and the user can retry without repeating it. The typed
      # path ignores `consume` entirely (it only reads `events`).
      Ok = Data.define(:events, :consume) do
        # events  — Array of { kind:, payload: } hashes
        # consume — Boolean; forwarded to FollowUp::Result::Append on reply.
        def initialize(events:, consume: true) = super
      end

      # Command failed. Creates a new Turn containing echo + error events.
      Error = Data.define(:message_key, :message_args) do
        # message_key  — String i18n key
        # message_args — Hash of interpolation args
      end
    end
  end
end
