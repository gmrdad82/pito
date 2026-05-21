# Phase 16 §1 — Notifications data model + delivery channels.
#
# Stub. Spec 02 ships per-kind templates that turn a calendar entry /
# event payload into a `{ title:, body:, url:, event_payload: }` hash.
# Spec 01 needs *something* in the seam so the scheduler can persist a
# valid Notification row (title is required; event_payload is NOT
# NULL); the minimal stub satisfies the contract while leaving the
# real templating to Spec 02.
module Pito
  module Notifications
    module PayloadBuilder
      module_function

      # Returns the four columns that vary per event:
      # { title:, body:, url:, event_payload: }.
      #
      # Stub posture: title falls back to the humanized event_type;
      # body / url default to nil; event_payload defaults to {}.
      # Callers may pass an override hash that wins over the defaults.
      def build(event_type:, calendar_entry: nil, overrides: {})
        base = {
          title: overrides[:title].presence || event_type.to_s.tr("_", " "),
          body: overrides[:body],
          url: overrides[:url],
          event_payload: overrides[:event_payload] || {}
        }

        if calendar_entry
          base[:event_payload] = base[:event_payload].merge(
            "calendar_entry_id" => calendar_entry.id,
            "calendar_entry_type" => calendar_entry.entry_type
          )
        end

        base
      end
    end
  end
end
