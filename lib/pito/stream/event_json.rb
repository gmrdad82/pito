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
    # TWO projection-time additions: payloads that carry only a
    # `message_key` (error events — the web I18n-renders the key at view
    # time) additionally get the server-rendered `text`, because a JSON
    # client has no locale files; and `thinking` payloads get the CURRENT
    # word pools (`words` + resolved `word`) so a client binary older than
    # the deployed copy can never show stale spinner verbs. Rendering
    # happens HERE, not at persist time, so stored payloads stay key-only
    # and re-rendering keeps yielding current translations on every
    # transport.
    module EventJson
      module_function

      def call(event)
        payload = payload_with_text(event.payload)
        payload = payload_with_thinking_words(payload) if event.kind == "thinking"

        {
          id:         event.id,
          turn_id:    event.turn_id,
          kind:       event.kind,
          payload:    payload,
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

      # Thinking events, plus the dictionary's word pools resolved from the
      # CURRENT locale files: `words` = the doing pool (the client cycles
      # `words[order[i]]` — exactly what the web embeds in its data
      # attributes), and — once resolved — `word` = the past-tense done word
      # at `word_index`. A retired dictionary leaves the payload untouched.
      def payload_with_thinking_words(payload)
        dictionary = payload["dictionary"].presence
        return payload if dictionary.nil?

        doing = I18n.t("pito.copy.thinking.#{dictionary}.doing", default: nil)
        return payload if doing.blank?

        enriched = payload.merge("words" => Array(doing).map(&:to_s))
        if payload["resolved"].to_s == "true"
          done = Array(I18n.t("pito.copy.thinking.#{dictionary}.done", default: nil))
          word = done[payload["word_index"].to_i]
          enriched = enriched.merge("word" => word.to_s) if word
        end
        enriched
      rescue StandardError
        payload
      end
    end
  end
end
