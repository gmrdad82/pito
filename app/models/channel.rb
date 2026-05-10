class Channel < ApplicationRecord
  # Phase 15 §1 — Calendar derivation hooks. Channel derives a single
  # `channel_published` entry keyed on `created_at`.
  include CalendarDerivable

  # Phase 20 — friendly URLs. Channel URLs reuse the UC-id portion of
  # `channel_url` (the locked YouTube channel identifier). No new slug
  # column, no `:history` module per locked Phase 20 decision #3 — UC
  # ids are externally owned and the `channel_url` column is itself
  # immutable post-create (`prevent_url_change`). `:finders` lets
  # `Channel.friendly.find(slug_or_id)` accept either a slug or an
  # integer ID for backwards compat. `to_param` falls back to
  # `"channel-<id>"` when no UC-id is extractable (master decision #1
  # in the Phase 20 spec).
  extend FriendlyId
  friendly_id :url_slug, use: :finders

  def url_slug
    extracted = channel_url.to_s[%r{/channel/(UC[A-Za-z0-9_-]{22})}, 1]
    extracted.presence || (id ? "channel-#{id}" : nil)
  end

  def to_param
    url_slug.presence || id&.to_s
  end

  # Raised when the locked channel_url is changed on update. Phase B's
  # controller layer rescues this and translates it to a 422 response.
  class UrlLockedError < ActiveRecord::ReadOnlyRecord; end

  CHANNEL_URL_REGEX = %r{\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z}

  has_many :videos, dependent: :destroy
  has_many :playlists, dependent: :destroy
  has_many :video_uploads, dependent: :destroy
  # Phase 15 §1 — calendar entries cascade. The FK is also ON DELETE
  # CASCADE at the database level.
  has_many :calendar_entries, dependent: :destroy

  # Phase 13.1 — analytics tables. Cascade is delete_all because the
  # rows are derived from the YouTube Analytics API; deleting the
  # Channel wipes them. Each FK is also ON DELETE CASCADE at the DB
  # level (belt-and-suspenders).
  has_many :channel_dailies,           dependent: :delete_all
  has_many :channel_window_summaries,  dependent: :delete_all
  has_many :top_videos_windows,        dependent: :delete_all

  # Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
  # After Path A2's literal full retract, "connected" means
  # `youtube_connection_id IS NOT NULL`; the placeholder `connected`
  # boolean is gone. Optional because seeded channels and disconnected
  # channels carry NULL here.
  belongs_to :youtube_connection,
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

  # Phase 15 §1 — Calendar derivation. Always derives once per channel
  # (keyed on `created_at`). The Calendar::Derivation upsert is
  # idempotent (no-ops when the existing row matches), so we fire the
  # hook on every save / touch — that way `Channel.first.touch` from
  # the manual playbook reliably brings up a derived entry on
  # pre-existing seed rows.
  #
  # Single `after_save_commit` declaration: registering the same filter
  # via two `after_*_commit` lines merges them in Rails 8.1.
  after_save_commit :sync_calendar_entry
  after_touch :sync_calendar_entry

  scope :starred,   -> { where(star: true) }
  scope :connected, -> { where.not(youtube_connection_id: nil) }

  # Phase 15 §1 — CalendarDerivable contract.

  def calendar_entry_type
    :channel_published
  end

  def calendar_entry_attributes
    {
      title: "channel joined: #{channel_url}",
      starts_at: created_at,
      all_day: true,
      channel_id: id,
      state: CalendarEntry.states[:occurred],
      metadata: {}
    }
  end

  def calendar_entry_source_ref
    { channel_id: id }
  end

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
