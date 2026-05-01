class Channel < ApplicationRecord
  include Searchable

  encrypts :oauth_access_token
  encrypts :oauth_refresh_token

  has_many :videos, dependent: :destroy
  has_many :playlists, dependent: :destroy
  has_many :video_uploads, dependent: :destroy

  scope :connected, -> { where(connected: true) }
  scope :public_only, -> { where(connected: false) }

  validates :youtube_channel_id, presence: true, uniqueness: { case_sensitive: false }
  validates :title, presence: true

  searchable :title, :description
  filterable :connected
end
