# Phase 22 §6.1 — Channel::ImportVideosJob.
#
# Sidekiq worker that drives one `Channel::VideoImporter` run per
# `ImportJob`. Flat naming pattern follows the existing `ChannelSync`
# precedent (see CLAUDE.md "Architecture notes"); using
# `Channel::ImportVideosJob` (namespaced under `Channel`) makes the
# job's host concept explicit while keeping the queue-name footprint
# unchanged.
#
# Status transitions:
#   queued -> running (perform start)
#   running -> completed (importer returned normally)
#   running -> failed   (importer raised a FatalError)
#
# Retry posture (mirrors `VideoSyncBack`):
#   - `Channel::VideoImporter::TransientError` re-raises to let
#     Sidekiq retry (default 3 attempts with exponential backoff).
#   - `Channel::VideoImporter::FatalError` marks the job `failed`,
#     captures `error_payload`, dispatches the completion notification,
#     and does NOT re-raise (suppress_retry).
#   - Channel deleted between enqueue and perform → no-op (cleanup).
class Channel::ImportVideosJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(channel_id, import_job_id)
    import_job = ImportJob.find_by(id: import_job_id)
    return unless import_job

    channel = Channel.find_by(id: channel_id)
    if channel.nil?
      mark_failed(import_job, code: :channel_missing, message: "channel deleted before import started")
      return
    end

    import_job.update!(status: :running)

    importer = build_importer
    importer.call(channel: channel, import_job: import_job) do |_progress|
      broadcast_progress(import_job)
    end

    import_job.update!(status: :completed)
    Pito::Notifications::Source::ImportJobCompleted.report!(import_job)
    broadcast_progress(import_job)
  rescue Channel::VideoImporter::FatalError => e
    mark_failed(import_job, code: e.code, message: e.message)
    raise unless e.suppress_retry?
  rescue Channel::VideoImporter::TransientError
    raise
  end

  private

  # Override seam — specs stub `Channel::ImportVideosJob#build_importer`
  # to inject a fake `Channel::VideoImporter`.
  def build_importer
    Channel::VideoImporter.new
  end

  def mark_failed(import_job, code:, message:)
    return unless import_job

    import_job.update!(
      status: :failed,
      error_payload: { "code" => code.to_s, "message" => message.to_s }
    )
    Pito::Notifications::Source::ImportJobCompleted.report!(import_job)
    broadcast_progress(import_job)
  end

  def broadcast_progress(import_job)
    Turbo::StreamsChannel.broadcast_replace_to(
      "import_jobs",
      target: ActionView::RecordIdentifier.dom_id(import_job, :progress),
      partial: "imports/channels/progress",
      locals: { import_job: import_job }
    )
  rescue StandardError => e
    Rails.logger.warn("Channel::ImportVideosJob: progress broadcast failed: #{e.class}: #{e.message}")
  end
end
