class Channel < ApplicationRecord
  # Phase 15 §1 — Calendar derivation hooks. Channel derives a single
  # `channel_published` entry keyed on `created_at`.
  include CalendarDerivable

  # Phase 20 — friendly URLs. Channel URLs reuse the UC-id portion of
  # `channel_url` (the locked YouTube channel identifier). No new slug
  # column, no `:history` module per locked Phase 20 decision #3 — UC
  # ids are externally owned and the `channel_url` column is itself
  # immutable post-create (`prevent_url_change`).
  #
  # Lookup goes through a custom `Channel.friendly` finder (rather than
  # `friendly_id :col, use: :finders`) because the slug is derived from
  # a portion of the `channel_url` column rather than a dedicated slug
  # column — friendly_id's :finders module assumes a 1:1 column lookup.
  # The finder accepts either a slug (UC-id), a `channel-<id>` fallback
  # slug, or an integer id (backwards compat).
  def url_slug
    extracted = channel_url.to_s[%r{/channel/(UC[A-Za-z0-9_-]{22})}, 1]
    extracted.presence || (id ? "channel-#{id}" : nil)
  end

  def to_param
    url_slug.presence || id&.to_s
  end

  def self.friendly
    FriendlyFinder.new(self)
  end

  # Custom finder for Channel — slug is derived from the `channel_url`
  # column. Resolution order:
  #   1. Bare integer → `find_by(id:)` (backwards compat for legacy
  #      bookmarks).
  #   2. `channel-<n>` shape → resolve as integer id.
  #   3. UC-id slug → `find_by("channel_url LIKE %/<slug>")`.
  class FriendlyFinder
    def initialize(scope)
      @scope = scope
    end

    def find(input)
      str = input.to_s
      raise ActiveRecord::RecordNotFound, "Channel param can't be blank" if str.blank?

      if str.match?(/\A\d+\z/)
        record = @scope.find_by(id: str.to_i)
        return record if record
      end

      m = str.match(/\Achannel-(\d+)\z/)
      if m
        record = @scope.find_by(id: m[1].to_i)
        return record if record
      end

      record = @scope.find_by("channel_url LIKE ?", "%/channel/#{str}")
      return record if record

      raise ActiveRecord::RecordNotFound,
            "Couldn't find Channel with slug or id=#{input.inspect}"
    end
  end

  # Raised when the locked channel_url is changed on update. Phase B's
  # controller layer rescues this and translates it to a 422 response.
  class UrlLockedError < ActiveRecord::ReadOnlyRecord; end

  CHANNEL_URL_REGEX = %r{\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z}

  has_many :videos, dependent: :destroy
  has_many :playlists, dependent: :destroy
  has_many :video_uploads, dependent: :destroy
  # Phase 22 — Video Import Flow. ImportJob rows are the per-channel
  # ledger for the `[import]` modal; RejectedVideoImport rows are the
  # insert-only tombstones that block previously-rejected YouTube ids
  # from being re-imported on future runs. Both FKs are
  # `ON DELETE CASCADE` at the database level (see migrations); the
  # Rails-side `dependent:` mirrors that contract.
  has_many :import_jobs, dependent: :destroy
  has_many :rejected_video_imports, dependent: :destroy
  # Phase 7.5 §11a — append-only change history for the rate-limited
  # title / handle fields. `dependent: :delete_all` because
  # ChannelChangeLog is read-only at the model layer (raises
  # `ActiveRecord::ReadOnlyRecord` on `destroy`); the DB FK is
  # `ON DELETE CASCADE` so the rows still get cleaned up.
  has_many :channel_change_logs, dependent: :delete_all
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
  # Every channel is OAuth-linked in the post-cleanup world; the
  # placeholder `connected` boolean is gone and so is the derived
  # `connected` scope. Optional stays because the FK can be cleared
  # via the YouTube disconnect flow before the channel record is
  # destroyed.
  belongs_to :youtube_connection,
             optional: true,
             inverse_of: :channels

  validates :channel_url,
            presence: true,
            format: { with: CHANNEL_URL_REGEX },
            uniqueness: { case_sensitive: true }

  # Phase 7.5 §11a — Channel resource columns. All editable fields
  # allow blank because the columns are display-only placeholders until
  # ChannelSync populates them on the first successful API roundtrip.
  HANDLE_REGEX = /\A@[A-Za-z0-9._-]+\z/
  COUNTRY_REGEX = /\A[A-Z]{2}\z/
  # BCP-47 lite: primary subtag (2-3 lowercase letters) + optional
  # region subtag (2 uppercase letters). Covers the vast majority of
  # YouTube `defaultLanguage` values without pulling a full BCP-47
  # parser into the model.
  DEFAULT_LANGUAGE_REGEX = /\A[a-z]{2,3}(-[A-Z]{2})?\z/
  WATERMARK_TIMINGS = %w[always entire_video offset_from_start offset_from_end].freeze
  MAX_LINKS = 5
  LINK_TITLE_MIN = 1
  LINK_TITLE_MAX = 50
  LINK_URL_REGEX = %r{\Ahttps?://[^\s]+\z}

  validates :title,
            length: { maximum: 100 },
            allow_blank: true
  validates :handle,
            length: { minimum: 3, maximum: 30 },
            format: { with: HANDLE_REGEX },
            allow_blank: true
  validates :description,
            length: { maximum: 5000 },
            allow_blank: true
  validates :country,
            format: { with: COUNTRY_REGEX },
            allow_blank: true
  validates :default_language,
            format: { with: DEFAULT_LANGUAGE_REGEX },
            allow_blank: true
  validates :watermark_timing,
            inclusion: { in: WATERMARK_TIMINGS },
            allow_blank: true
  validates :watermark_offset_ms,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_blank: true
  validates :subscriber_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_blank: true
  validates :view_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_blank: true
  validates :video_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_blank: true

  validate :links_shape

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
  # Phase 22 — "connected" semantic post-Phase-9 rename. A channel is
  # treated as connected when it carries a `youtube_connection_id`
  # (Phase 9 dropped the legacy `connected` boolean — see ADR 0006).
  # The `[import]` modal lists channels in this scope.
  scope :connected, -> { where.not(youtube_connection_id: nil) }

  # Phase 22 — true when an `ImportJob` for this channel is currently
  # `queued` or `running`. Drives the channel-show in-flight badge and
  # the modal's "refuse second enqueue" branch (locked decision #1).
  def in_flight_import?
    import_jobs.in_flight.exists?
  end

  # Phase 22 — the single in-flight ImportJob for this channel, or nil
  # if none. Caller uses `.recent.first` so the most-recently-created
  # row wins when, somehow, more than one survives (defense in depth;
  # the `Imports::ChannelsController#create` action refuses concurrent
  # enqueues).
  def in_flight_import_job
    import_jobs.in_flight.recent.first
  end

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

  # Phase 7.5 §11a — `links` JSON shape validator. Required structure:
  # Array of Hashes with `title` (1..50) + `url` (https?://...); max 5
  # entries. Anything else is rejected with a single error on `:links`.
  def links_shape
    value = links
    return if value.blank? && value.is_a?(Array) # empty Array is valid

    unless value.is_a?(Array)
      errors.add(:links, "must be an array")
      return
    end

    if value.size > MAX_LINKS
      errors.add(:links, "may contain at most #{MAX_LINKS} entries")
      return
    end

    value.each_with_index do |entry, idx|
      unless entry.is_a?(Hash)
        errors.add(:links, "entry #{idx} must be an object")
        next
      end
      entry_title = entry["title"] || entry[:title]
      entry_url = entry["url"] || entry[:url]
      if entry_title.blank? || !entry_title.is_a?(String) ||
         entry_title.length < LINK_TITLE_MIN || entry_title.length > LINK_TITLE_MAX
        errors.add(:links, "entry #{idx} title must be 1..#{LINK_TITLE_MAX} characters")
      end
      if entry_url.blank? || !entry_url.is_a?(String) || !entry_url.match?(LINK_URL_REGEX)
        errors.add(:links, "entry #{idx} url must be a valid http(s) URL")
      end
    end
  end

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
