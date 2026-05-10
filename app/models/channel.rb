class Channel < ApplicationRecord
  # Raised when the locked channel_url is changed on update. Phase B's
  # controller layer rescues this and translates it to a 422 response.
  class UrlLockedError < ActiveRecord::ReadOnlyRecord; end

  CHANNEL_URL_REGEX = %r{\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z}

  has_many :videos, dependent: :destroy
  has_many :playlists, dependent: :destroy
  has_many :video_uploads, dependent: :destroy

  # Phase 7 — Channel <-> GoogleIdentity link. After Path A2's literal
  # full retract, "connected" means `oauth_identity_id IS NOT NULL`;
  # the placeholder `connected` boolean is gone. Optional because
  # seeded channels and disconnected channels carry NULL here.
  belongs_to :oauth_identity,
             class_name: "GoogleIdentity",
             optional: true,
             inverse_of: :channels

  validates :channel_url,
            presence: true,
            format: { with: CHANNEL_URL_REGEX },
            uniqueness: { case_sensitive: true }

  before_update :prevent_url_change

  # Phase 7 Path A2 (literal full retract). The original Phase 4
  # placeholder ChannelSync stub flipped a `syncing` boolean; Path A2
  # drops that boolean and the stub becomes a `last_synced_at` stamp.
  # The create / star callbacks survive as a smoke surface so the
  # job wiring stays exercised end-to-end. Phase 8+ swaps the stub
  # for real YouTube sync.
  after_create_commit :enqueue_initial_sync
  after_update_commit :enqueue_sync_on_star

  scope :starred,   -> { where(star: true) }
  scope :connected, -> { where.not(oauth_identity_id: nil) }

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
