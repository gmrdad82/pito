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
    #
    # ONE projection-time addition: payloads that carry only a
    # `message_key` (error events — the web I18n-renders the key at view
    # time) additionally get the server-rendered `text`, because a JSON
    # client has no locale files. Rendering happens HERE, not at persist
    # time, so the stored payload stays key-only and re-rendering keeps
    # yielding current translations on every transport.
    module EventJson
      module_function

      def call(event)
        {
          id:         event.id,
          turn_id:    event.turn_id,
          kind:       event.kind,
          payload:    payload_with_text(event.payload),
          position:   event.position,
          created_at: event.created_at.iso8601
        }
      end

      # The payload, plus rendered `text` when only a message_key is present.
      # A failed render (retired key inside an old event) leaves the payload
      # untouched rather than failing the whole serialization.
      def payload_with_text(payload)
        key = payload["message_key"].presence
        return payload if key.nil? || payload["text"].present?

        args = (payload["message_args"] || {}).symbolize_keys
        payload.merge("text" => Pito::Copy.render(key, args))
      rescue StandardError
        payload
      end
    end
  end
end
