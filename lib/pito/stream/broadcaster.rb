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
        event = ::Event.create_with_position!(conversation: @conversation, turn:, kind:, payload:)
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

      # Create and broadcast a thinking indicator for a turn.
      # The word_index is chosen once and frozen in the payload.
      def emit_thinking(turn:, dictionary:)
        words = I18n.t("pito.event.thinking.#{dictionary}.doing")
        payload = { dictionary:, word_index: rand(words.length) }
        emit(turn:, kind: "thinking", payload:)
      end

      # Resolve a thinking indicator: update its payload with the resolved state
      # and elapsed time, then broadcast a Turbo Stream replace.
      def resolve_thinking(turn:, elapsed_seconds:)
        event = turn.events.find_by(kind: "thinking")
        return unless event

        event.update!(
          payload: event.payload.merge(resolved: true, elapsed_seconds: elapsed_seconds)
        )

        html    = Pito::Stream::EventRenderer.render(event)
        helper  = ApplicationController.helpers
        content = helper.turbo_stream.replace("event_#{event.id}", html)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        event
      end
    end
  end
end
