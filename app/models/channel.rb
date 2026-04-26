class Channel < ApplicationRecord
  encrypts :oauth_access_token
  encrypts :oauth_refresh_token

  has_many :videos, dependent: :destroy

  scope :connected, -> { where(connected: true) }
  scope :public_only, -> { where(connected: false) }

  validates :youtube_channel_id, presence: true, uniqueness: true
  validates :title, presence: true
end
