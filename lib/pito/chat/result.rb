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
      #
      # `nl_fallback:` (default false) marks the SOFT-FAIL variant — "tool
      # recognized, body not actionable, and the body looks like free text".
      # Pito::Dispatch::Router#route_verb intercepts the marker and re-runs the
      # ORIGINAL utterance through the NL gate (Handlers::Unknown) instead of
      # surfacing this error — except on an NL-retry dispatch (the loop guard),
      # where the marker returns to the mapped-command caller to degrade.
      # `message_key`/`message_args` still carry the crisp local error, so any
      # consumer that renders the marker un-fallen-back shows a plain error.
      Error = Data.define(:message_key, :message_args, :nl_fallback) do
        # message_key  — String i18n key (or pre-rendered text; see Finalizer.error_payload)
        # message_args — Hash of interpolation args
        # nl_fallback  — Boolean; true = soft-fail marker (NL-gate fallback requested)
        def initialize(message_key:, message_args:, nl_fallback: false) = super
      end
    end
  end
end
