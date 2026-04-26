class Playlist < ApplicationRecord
  belongs_to :channel

  has_many :playlist_items, dependent: :destroy
  has_many :videos, through: :playlist_items

  enum :privacy_status, { public_playlist: 0, unlisted: 1, private_playlist: 2 }

  validates :youtube_playlist_id, presence: true, uniqueness: true
  validates :title, presence: true
end
