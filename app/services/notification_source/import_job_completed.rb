# Phase 22 §6.3 — ImportJob completion notification source.
#
# Fires once per ImportJob terminal transition (completed OR failed).
# Idempotency: dedup_key is `import-job-<id>` so repeated terminal
# transitions on the same job (operator manually flips status) do not
# double-post.
#
# Severity mirrors the outcome — `success` on `completed`, `warn` on
# `failed`. URL points at the modal's per-job show route so clicking
# the in-app notification reopens the keep/reject table (or the
# error detail when failed).
module NotificationSource
  module ImportJobCompleted
    EVENT_TYPE = "import_job_completed"

    module_function

    # @param import_job [ImportJob]
    # @return [Notification]
    def report!(import_job)
      channel = import_job.channel
      channel_label = channel.title.presence || channel.channel_url.to_s
      status_label = import_job.status

      title = if import_job.failed?
        "import failed: #{channel_label}"
      else
        "import complete: #{channel_label} (#{import_job.imported_videos} new)"
      end

      body_parts = [
        "channel: #{channel_label}",
        "status: #{status_label}",
        "imported: #{import_job.imported_videos}",
        "failed: #{import_job.failed_videos}"
      ]
      if import_job.failed? && import_job.error_payload.is_a?(Hash)
        body_parts << "error: #{import_job.error_payload['message'] || import_job.error_payload[:message]}"
      end

      severity = import_job.failed? ? :warn : :success
      payload = NotificationPayloadBuilder.build(
        event_type: EVENT_TYPE,
        overrides: {
          title: title,
          body: body_parts.compact.join(" | ").first(5000),
          url: "/imports/channels/#{import_job.id}",
          event_payload: {
            "import_job_id" => import_job.id,
            "channel_id" => channel.id,
            "status" => status_label.to_s,
            "imported_videos" => import_job.imported_videos,
            "failed_videos" => import_job.failed_videos
          }
        }
      )

      Notification.find_or_create_by!(
        event_type: EVENT_TYPE,
        dedup_key: "import-job-#{import_job.id}"
      ) do |n|
        n.kind = :import_job_completed
        n.severity = severity
        n.title = payload[:title]
        n.body = payload[:body]
        n.url = payload[:url]
        n.event_payload = payload[:event_payload]
        n.fires_at = Time.current
        n.created_by_user = import_job.enqueued_by
      end
    end
  end
end
