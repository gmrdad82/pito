# Phase 22 §4.1 — ImportJob ledger.
#
# One per-channel import attempt. Tracks status, counters, and the
# user who enqueued it. Status is a Rails enum (integer-backed for
# storage, serialized as a string at every JSON boundary).
#
# Lifecycle:
#   queued    — row created, Sidekiq job not yet picked.
#   running   — `Channel::ImportVideosJob` started; `started_at` stamped.
#   completed — successful pagination + persist; `completed_at` stamped.
#   failed    — fatal error from the importer; `completed_at` stamped
#               and `error_payload` populated.
#
# Retention is forever (per locked decision #3 — audit trail; volume
# trivial). No cron sweep, no soft-delete column.
#
# `dependent: :destroy` on Channel cascades these rows when the parent
# channel is destroyed, via the database FK (`ON DELETE CASCADE`); the
# Rails-side association mirrors that contract.
class ImportJob < ApplicationRecord
  belongs_to :channel
  belongs_to :enqueued_by, class_name: "User"

  enum :status, {
    queued: 0,
    running: 1,
    completed: 2,
    failed: 3
  }

  validates :total_videos,    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :imported_videos, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :failed_videos,   numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :in_flight,          -> { where(status: %i[queued running]) }
  scope :for_channel,        ->(channel) { where(channel: channel) }
  scope :recent,             -> { order(created_at: :desc) }

  before_save :stamp_started_at
  before_save :stamp_completed_at

  # Fraction of imported_videos / total_videos, capped at 1.0. Returns
  # 0.0 when total_videos is 0 (no rows discovered yet).
  def progress_fraction
    return 0.0 if total_videos.to_i <= 0

    fraction = imported_videos.to_f / total_videos
    fraction > 1.0 ? 1.0 : fraction
  end

  def in_flight?
    queued? || running?
  end

  # Videos belonging to this channel that were created during the job's
  # run window. Used by `Imports::ChannelsController#update` to
  # enumerate the candidate set for the keep/reject form.
  def candidate_videos
    scope = channel.videos
    scope = scope.where("videos.created_at >= ?", started_at) if started_at
    scope = scope.where("videos.created_at <= ?", completed_at) if completed_at
    scope.order(:id)
  end

  private

  def stamp_started_at
    return unless status_changed?
    return unless running?
    return if started_at.present?

    self.started_at = Time.current
  end

  def stamp_completed_at
    return unless status_changed?
    return unless completed? || failed?
    return if completed_at.present?

    self.completed_at = Time.current
  end
end
