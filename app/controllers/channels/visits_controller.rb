# frozen_string_literal: true

module Channels
  # POST /channels/visit_consume
  #
  # Consumes a channel-visit event after its one-time auto-click. The
  # pito--auto-visit Stimulus controller POSTs `{ event_id: }` here once it has
  # fired the click. We flip the event to its :visited (follow-up) state:
  #   - rebuild the body via Pito::MessageBuilder::Channel::Visit(state: :visited)
  #   - change the kind to system_follow_up (the surface-background chrome)
  #   - persist + broadcast a replace so the live view updates in place.
  #
  # On every later page refresh the event renders in its :visited state (no
  # controller, no auto-click), so the link is never re-clicked automatically.
  #
  # Idempotent: a second POST (race / double-fire) is a no-op.
  class VisitsController < ApplicationController
    def consume
      event = Event.find(params[:event_id])

      if event.payload["visit_state"].to_s != "visited"
        channel = ::Channel.find_by(id: event.payload["channel_id"])
        if channel
          event.update!(
            kind:    "system_follow_up",
            payload: Pito::MessageBuilder::Channel::Visit.call(channel, state: :visited)
          )
          Pito::Stream::Broadcaster.new(conversation: event.conversation).replace_event(event)
        end
      end

      head :ok
    end
  end
end
