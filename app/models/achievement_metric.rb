# frozen_string_literal: true

# The system's own latest lifetime value per (achievable, metric).
#
# One row per (achievable, metric) pair — upserted by AchievementsRefreshJob.
# Drives the Evaluate service: compare `value` against each Achievement
# threshold and unlock any that haven't been recorded yet.
# Polymorphic on achievable: Channel, Video, or Game.
class AchievementMetric < ApplicationRecord
  belongs_to :achievable, polymorphic: true

  validates :metric, presence: true, inclusion: { in: Achievement::METRICS }
  validates :value,  presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :metric,
            uniqueness: { scope: %i[achievable_type achievable_id] }
end
