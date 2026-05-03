class Channel < ApplicationRecord
  # Raised when the locked channel_url is changed on update. Phase B's
  # controller layer rescues this and translates it to a 422 response.
  class UrlLockedError < ActiveRecord::ReadOnlyRecord; end

  CHANNEL_URL_REGEX = %r{\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z}

  belongs_to :tenant

  has_many :videos, dependent: :destroy
  has_many :playlists, dependent: :destroy
  has_many :video_uploads, dependent: :destroy

  validates :channel_url,
            presence: true,
            format: { with: CHANNEL_URL_REGEX },
            uniqueness: { case_sensitive: true }

  before_update :prevent_url_change

  after_create_commit :enqueue_initial_sync
  after_update_commit :enqueue_sync_on_star

  scope :starred, -> { where(star: true) }
  scope :connected, -> { where(connected: true) }
  scope :syncing, -> { where(syncing: true) }

  private

  def prevent_url_change
    raise UrlLockedError, "channel_url is locked and cannot be changed" if channel_url_changed?
  end

  def enqueue_initial_sync
    ChannelSync.perform_async(id)
  end

  def enqueue_sync_on_star
    ChannelSync.perform_async(id) if saved_change_to_star? && star?
  end
end
