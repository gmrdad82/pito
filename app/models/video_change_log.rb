# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Append-only audit row recording one applied field change from a
# resolved `VideoDiff`. Created exclusively by the apply orchestrator
# (`Youtube::VideoDiffApply`) after a successful per-field decision
# round-trip.
#
# Append-only enforcement: persisted rows are read-only at the model
# layer (`readonly?` returns true once `persisted?` is true), so
# `update!` / `destroy` raise `ActiveRecord::ReadOnlyRecord`. New rows
# can still be created normally. The DB does NOT carry a trigger; the
# constraint lives in code to mirror `ChannelChangeLog` shape.
class VideoChangeLog < ApplicationRecord
  # The full writable + display-only field set the diff dialog can
  # resolve. Centralized here so the validator + the diff computer +
  # the apply orchestrator all agree.
  FIELDS = %w[
    title description tags category_id
    privacy_status publish_at
    self_declared_made_for_kids contains_synthetic_media
    embeddable public_stats_viewable
    made_for_kids_effective
    view_count like_count comment_count
    duration_seconds published_at
    thumbnail_url
  ].freeze

  enum :source, {
    pito_apply:    0,
    youtube_pull:  1,
    initial_sync:  2
  }

  belongs_to :video
  belongs_to :changed_by_user,
             class_name: "User",
             optional: true

  validates :field, presence: true, inclusion: { in: FIELDS }
  validates :changed_at, presence: true
  validates :source, presence: true

  scope :recent, -> { order(changed_at: :desc).limit(20) }
  scope :for_field, ->(field) { where(field: field) }

  # Persisted rows are read-only. New (unpersisted) records remain
  # writable until the first `save!` so the create path is unaffected.
  def readonly?
    persisted?
  end
end
