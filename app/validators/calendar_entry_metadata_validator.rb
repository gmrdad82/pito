# Phase 15 §1 — per-type metadata schema validator.
#
# Each `entry_type` declares the keys allowed in `metadata`. Unknown keys
# are stripped on save. The `user_overrides` sub-key is allowed on every
# type. The validator strips unknown keys in-place (mutating
# `record.metadata`) before the row hits the database; this is the
# documented behavior per the spec ("Unknown keys on save are stripped").
class CalendarEntryMetadataValidator < ActiveModel::Validator
  ALLOWED_KEYS = {
    "channel_published"  => %w[user_overrides],
    "video_published"    => %w[user_overrides],
    "video_scheduled"    => %w[user_overrides],
    "game_release"       => %w[platforms release_window igdb_id igdb_slug user_overrides],
    "purchase_planned"   => %w[
      purchase_kind storefront storefront_name storefront_url
      amount currency ordered_at confirmation_ref user_overrides
    ],
    "milestone_manual"   => %w[user_overrides],
    "milestone_auto"     => %w[metric_value_at_fire user_overrides],
    "custom"             => %w[tags user_overrides]
  }.freeze

  def validate(record)
    return if record.metadata.nil?
    return if record.entry_type.blank?

    allowed = ALLOWED_KEYS[record.entry_type] || []
    metadata = record.metadata
    return unless metadata.is_a?(Hash)

    # Strip unknown keys in-place. Symbol keys round-trip through the
    # `metadata.to_a.map(&:first)` enumeration as strings via jsonb,
    # so we normalize comparison to string keys.
    sanitized = metadata.each_with_object({}) do |(k, v), acc|
      key = k.to_s
      acc[key] = v if allowed.include?(key)
    end

    record.metadata = sanitized unless sanitized == metadata
  end
end
