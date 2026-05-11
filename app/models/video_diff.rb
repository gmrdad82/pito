# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Open-diff registry. Created / updated by the daily diff-check job
# (`VideoDiffCheckJob`) via `Youtube::VideoDiffPersister`; resolved by
# `Youtube::VideoDiffApply` when the user submits the per-field
# decision form.
#
# Per locked Q2: KEEP ALL resolved diffs as audit history. No expiry
# job ships in this phase.
class VideoDiff < ApplicationRecord
  belongs_to :video
  belongs_to :resolved_by_user,
             class_name: "User",
             optional: true

  validates :detected_at, presence: true
  validate :payload_is_hash
  validate :resolution_payload_is_hash_when_present

  scope :open,     -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :recent,   -> { order(detected_at: :desc) }

  # Convenience — the keys of `payload` (the differing fields).
  def fields
    Array(payload&.keys)
  end

  # Returns the `{ "pito" => ..., "youtube" => ... }` pair for one
  # field, or nil if the field isn't in the diff payload.
  def field_diff(name)
    raw = (payload || {})[name.to_s]
    return nil unless raw.is_a?(Hash)
    raw
  end

  def pito_value(field)
    field_diff(field)&.dig("pito")
  end

  def youtube_value(field)
    field_diff(field)&.dig("youtube")
  end

  def resolved?
    resolved_at.present?
  end

  def open?
    resolved_at.nil?
  end

  private

  def payload_is_hash
    unless payload.is_a?(Hash)
      errors.add(:payload, "must be a Hash")
    end
  end

  def resolution_payload_is_hash_when_present
    return if resolution_payload.nil?
    unless resolution_payload.is_a?(Hash)
      errors.add(:resolution_payload, "must be a Hash when present")
    end
  end
end
