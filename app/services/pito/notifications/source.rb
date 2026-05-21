# Phase 16 §1 — Notifications data model + delivery channels.
#
# Namespace for non-calendar notification sources. Each source's
# `report!(...)` helper is idempotent on `(event_type, dedup_key)` —
# the unique partial index on `notifications` enforces this at the DB
# layer, the model + service layer use `find_or_create_by!` to
# normalize the happy path.
module Pito
  module Notifications
    module Source
    end
  end
end
