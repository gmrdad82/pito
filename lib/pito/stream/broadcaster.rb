# frozen_string_literal: true

module Pito
  module Stream
    class Broadcaster
      def initialize(conversation:)
        @conversation = conversation
      end

      def emit(turn:, kind:, payload:)
        Pito::Stream::EventPayload.validate!(kind:, payload:)

        event = @conversation.events.create!(
          turn:,
          position: ::Event.next_position_for(@conversation),
          kind:,
          payload:
        )

        html = Pito::Stream::EventRenderer.render(event)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.id}",
          content: ApplicationController.helpers.turbo_stream.append("pito-scrollback", html)
        )

        event
      end
    end
  end
end
