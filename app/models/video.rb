class Video < ApplicationRecord
  include Searchable

  belongs_to :channel

  has_many :video_stats, dependent: :destroy
  has_many :playlist_items, dependent: :destroy
  has_many :playlists, through: :playlist_items

  enum :privacy_status, { public_video: 0, unlisted: 1, private_video: 2 }

  validates :youtube_video_id, presence: true, uniqueness: { case_sensitive: false }
  validates :title, presence: true

  searchable :title, :description, :tags, :category_id, :default_language
  filterable :channel_id, :privacy_status
end
