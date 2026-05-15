# Phase 24 — cascade-delete job for the `[revoke]` flow.
#
# Given `(channel_id, connection_id_snapshot)`, the job destroys the
# Channel (which triggers the Rails-side `dependent:` cascade across
# every dependent table — videos, playlists, video_uploads, import_jobs,
# rejected_video_imports, channel_change_logs, calendar_entries,
# channel analytics tables; and transitively every video's analytics,
# diffs, change-logs, links, calendar entries) and
# then — only when the captured connection has zero remaining channels
# AND zero remaining videos — destroys the `YoutubeConnection` itself.
#
# The connection cleanup branch is gated on BOTH guards because
# `YoutubeConnection has_many :videos, dependent: :nullify` per the
# Phase 7C disconnect-lifecycle decision — Videos can outlive their
# Channel and still reference the connection. Destroying the connection
# while videos still point at it would leave orphan FK references
# (nullify-ed at the AR level, but the FK column would re-point at a
# missing row on the next save).
#
# Idempotency: re-running the job on an already-gone channel is a
# no-op for the channel side; the connection-cleanup branch still runs
# against `connection_id_snapshot` if provided, so a missed branch on
# the first run gets caught on a manual retry.
#
# Authorization happens at the controller layer (per `Sessions::
# AuthConcern`). The job runs in the background and assumes the caller
# vetted the request.
#
# **Schema-mismatch note (per umbrella spec open question #2):** Notes
# belong to Project, not Channel/Video. They do NOT cascade through a
# channel revoke. The umbrella spec's user-facing copy mentions
# "calendar entries" but NOT notes; this job intentionally does not
# touch the notes tree.
class DeleteChannelDataJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(channel_id, connection_id_snapshot = nil)
    channel = Channel.find_by(id: channel_id)

    if channel
      # Capture the connection id at execute time when the caller did
      # not snapshot it. The channel still has its FK; reading it now
      # before destroying the row is the safe path.
      connection_id_snapshot ||= channel.youtube_connection_id

      # Channel#destroy triggers the cascade. Every dependent table
      # listed on the model (`dependent: :destroy` and
      # `dependent: :delete_all`) gets cleaned up; the underlying DB
      # FKs use ON DELETE CASCADE as a belt-and-suspenders fence so
      # forgotten Rails-side declarations still cleanup at the
      # storage layer.
      Channel.transaction do
        channel.destroy!
      end
    end

    cleanup_orphan_connection(connection_id_snapshot) if connection_id_snapshot
  end

  private

  # Destroy the YoutubeConnection only when nothing else references it.
  # Both guards must hold:
  #
  #   - `connection.channels.exists?` → false (no surviving channels)
  #   - `connection.videos.exists?`   → false (no orphan videos that
  #     still carry the connection id from before their channel was
  #     destroyed)
  #
  # If either guard holds, the connection survives — orphan videos
  # under it can still be re-attached when the user re-connects. A
  # manual retry of the job after the orphan videos are destroyed will
  # cleanly pick up the connection.
  def cleanup_orphan_connection(connection_id)
    connection = YoutubeConnection.find_by(id: connection_id)
    return unless connection
    return if connection.channels.exists?
    return if connection.videos.exists?

    connection.destroy!
  end
end
