class Video < ApplicationRecord
  belongs_to :channel

  has_many :video_stats, dependent: :destroy
  has_one :production, dependent: :nullify

  validates :youtube_video_id, presence: true, uniqueness: true
  validates :title, presence: true
end
