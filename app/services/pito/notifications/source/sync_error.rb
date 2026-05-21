# Phase 16 §1 — Notifications data model + delivery channels.
#
# Source helper for sync-job failures. Caller supplies a stable
# `dedup_key` (e.g., `"channel-sync-#{channel.id}-#{Date.current}"`)
# so repeated retries within a window do not spam the inbox.
#
# Severity is `:urgent` — sync errors block analytics/derivations and
# almost always need operator attention.
module Pito
  module Notifications
    module Source
      module SyncError
        EVENT_TYPE = "sync_error"

        module_function

        # @param job [Class, String] the failing Sidekiq job class.
        # @param error [Exception] the raised error.
        # @param dedup_key [String] caller-supplied dedup window key.
        # @return [Notification]
        def report!(job:, error:, dedup_key:)
          job_name = job.is_a?(Class) ? job.name : job.to_s
          payload = Pito::Notifications::PayloadBuilder.build(
            event_type: EVENT_TYPE,
            overrides: {
              title: "sync error: #{job_name}",
              body: error.message.to_s.first(5000),
              url: nil,
              event_payload: {
                "job_class" => job_name,
                "error_class" => error.class.name,
                "error_message" => error.message.to_s
              }
            }
          )

          Notification.find_or_create_by!(
            event_type: EVENT_TYPE,
            dedup_key: dedup_key
          ) do |n|
            n.kind = :sync_error
            n.severity = :urgent
            n.title = payload[:title]
            n.body = payload[:body]
            n.url = payload[:url]
            n.event_payload = payload[:event_payload]
            n.fires_at = Time.current
          end
        end
      end
    end
  end
end
