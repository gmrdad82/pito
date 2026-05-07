class VideoStat < ApplicationRecord
  include BelongsToTenant

  belongs_to :video

  validates :date, presence: true, uniqueness: { scope: :video_id }
end
