class VideoStat < ApplicationRecord
  belongs_to :video

  validates :date, presence: true, uniqueness: { scope: :video_id }
end
