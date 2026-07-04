# frozen_string_literal: true

module Pito
  module Stream
    # The JSON face of a persisted scrollback event — EventRenderer's sibling:
    # same input, a wire-ready Hash instead of HTML. Non-browser clients
    # (pito-tui, and any future native client) receive exactly this shape on
    # the `pito:json:conversation:<uuid>` cable stream AND in the
    # GET /chat/:uuid.json backfill, so live and reloaded scrollbacks can
    # never drift apart.
    #
    # The payload travels verbatim: events persist structured jsonb (never
    # rendered HTML) by architecture invariant, which is what makes this
    # serializer a projection rather than a translation.
    module EventJson
      module_function

      def call(event)
        {
          id:         event.id,
          turn_id:    event.turn_id,
          kind:       event.kind,
          payload:    event.payload,
          position:   event.position,
          created_at: event.created_at.iso8601
        }
      end
    end
  end
end
