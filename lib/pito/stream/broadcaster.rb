# frozen_string_literal: true

module Pito
  module Stream
    class Broadcaster
      def initialize(conversation:)
        @conversation = conversation
      end

      # Create an event, persist it, then immediately broadcast it.
      # Used by sync paths (auth, unauthenticated error) where persist + broadcast
      # happen together in the same controller action.
      def emit(turn:, kind:, payload:)
        Pito::Stream::EventPayload.validate!(kind:, payload:)

        event = @conversation.events.create!(
          turn:,
          position: ::Event.next_position_for(@conversation),
          kind:,
          payload:
        )

        broadcast_event(event)
        event
      end

      # Broadcast an already-persisted event over the cable.
      #
      # Events are grouped by TURN so a turn's result lands directly under its
      # echo even when many commands are dispatched concurrently (each async job
      # finishes at its own pace). The echo (always a turn's first event) opens a
      # `#turn_<id>` container appended to the scrollback; every later event in
      # the turn appends INTO that container, not at the end of the scrollback.
      def broadcast_event(event)
        html   = Pito::Stream::EventRenderer.render(event)
        helper = ApplicationController.helpers

        content =
          if event.kind == "echo"
            helper.turbo_stream.append(
              "pito-scrollback",
              %(<div id="turn_#{event.turn_id}" class="pito-turn">#{html}</div>).html_safe
            )
          else
            helper.turbo_stream.append("turn_#{event.turn_id}", html)
          end

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        event
      end
    end
  end
end
