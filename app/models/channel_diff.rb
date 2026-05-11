# Phase 7.5 — Step 11i (Daily Channel Diff-Check + Resolution).
#
# Open-diff registry for channels. Mirrors the Phase 23 `VideoDiff`
# shape (per locked Q6 — MCP tool parity). Created / refreshed by the
# daily `ChannelDiffCheckJob` via `Channels::DiffPersister`; resolved
# by `Channels::DiffApply` when the user submits the per-field
# decision form.
#
# Per the resolution-history posture mirrored from VideoDiff: KEEP ALL
# resolved diffs as audit history. No expiry job ships in this phase.
class ChannelDiff < ApplicationRecord
  belongs_to :channel
  belongs_to :resolved_by_user,
             class_name: "User",
             optional: true

  validates :detected_at, presence: true
  validate :field_diffs_is_hash
  validate :resolution_payload_is_hash_when_present

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :open,       -> { where(resolved_at: nil) }
  scope :resolved,   -> { where.not(resolved_at: nil) }
  scope :recent,     -> { order(detected_at: :desc) }

  # Convenience — the keys of `field_diffs` (the differing fields),
  # sorted alphabetically so the resolution UI renders fields in a
  # stable order.
  def fields
    Array(field_diffs&.keys).sort
  end

  alias_method :diffing_fields, :fields

  # Returns the `{ "pito" => ..., "youtube" => ... }` pair for one
  # field, or nil if the field isn't in the diff payload.
  def field_diff(name)
    raw = (field_diffs || {})[name.to_s]
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

  def field_diffs_is_hash
    unless field_diffs.is_a?(Hash)
      errors.add(:field_diffs, "must be a Hash")
    end
  end

  def resolution_payload_is_hash_when_present
    return if resolution_payload.nil?
    unless resolution_payload.is_a?(Hash)
      errors.add(:resolution_payload, "must be a Hash when present")
    end
  end
end
