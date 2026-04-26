class Channel < ApplicationRecord
  encrypts :oauth_access_token
  encrypts :oauth_refresh_token

  has_many :videos, dependent: :destroy

  scope :owned, -> { where(owned: true) }
  scope :public_only, -> { where(owned: false) }

  validates :youtube_channel_id, presence: true, uniqueness: true
  validates :title, presence: true
end
