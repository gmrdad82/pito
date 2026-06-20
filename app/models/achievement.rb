# frozen_string_literal: true

# Polymorphic, unlock-once milestone record.
#
# One row per (achievable, metric, threshold) combination — each row is created
# exactly once when the threshold is first crossed and is never deleted.
# Polymorphic on achievable: Channel, Video, or Game.
#
# Metrics match the lifetime counters the channel owner cares about:
#   subs          — total subscriber count (Channel)
#   subs_gained   — subscribers gained (Channel, period-based)
#   views         — total view count (Channel / Video / Game)
#   watched_hours — total watch time in hours (Channel / Video)
#   likes         — total like count (Video)
#   comments      — total comment count (Video)
#
# Reads and writes go through Pito::Achievement::Evaluate rather than this
# model directly.
class Achievement < ApplicationRecord
  METRICS = %w[subs subs_gained views watched_hours likes comments].freeze

  belongs_to :achievable, polymorphic: true

  validates :metric,      presence: true, inclusion: { in: METRICS }
  validates :threshold,   presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :unlocked_at, presence: true
  validates :threshold,
            uniqueness: { scope: %i[achievable_type achievable_id metric] }
end
