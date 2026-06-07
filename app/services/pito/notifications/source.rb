# Phase 16 §1 — Notifications data model + delivery channels.
#
# Namespace for non-calendar notification sources.
#
# Each concrete source module (SyncError, YoutubeReauthNeeded,
# …) exposes a single `module_function`:
#
#   report!(…domain args…) → Notification
#
# CONTRACT:
#   • Idempotent on `(event_type, dedup_key)` — the unique partial
#     index on `notifications(event_type, dedup_key)` enforces this at
#     the DB layer; the source layer uses `find_or_create_by!` so
#     repeated calls within a dedup window do not spam the inbox.
#   • The caller supplies a stable `dedup_key` string (e.g.
#     `"youtube-reauth-#{connection.id}"`, `"import-job-#{job.id}"`,
#     or a date-scoped key for sync errors).
#   • On the create path the block populates all notification columns
#     (`kind`, `severity`, `title`, `body`, `url`, `event_payload`,
#     `fires_at`). On the find path the block is skipped — the existing
#     row is returned unchanged.
#   • `report!` never enqueues delivery jobs — that responsibility
#     belongs to the caller or the `Notifications::Scheduler`. Sources
#     are pure data helpers.
module Pito
  module Notifications
    module Source
    end
  end
end
