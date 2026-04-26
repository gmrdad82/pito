class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_stats, dependent: :destroy

  enum :privacy_status, { public_video: 0, unlisted: 1, private_video: 2 }

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true
end
