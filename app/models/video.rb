class Video < ApplicationRecord
  include Searchable
  # Phase 15 §1 — Calendar derivation hooks. Video derives a
  # `video_published` entry when public/unlisted with `published_at`,
  # and a `video_scheduled` entry when private with a future
  # `publish_at`. See §"Services: derivation".
  include CalendarDerivable

  # Phase 12 — video schema expansion + edit surface + pre-publish
  # checklist. The Path A2 thin retract is reversed: Video carries the
  # YouTube Data API v3 writable subset (title, description, tags,
  # category_id, privacy_status, publish_at, ...) plus the four
  # pre-publish-checklist booleans + completion timestamp. Project
  # relation is direct via `project_id` (Timeline intermediary stays
  # dropped per realignment Resolved ambiguity #1).
  belongs_to :channel
  belongs_to :project, optional: true
  belongs_to :youtube_connection, optional: true

  has_many :video_stats, dependent: :destroy
  has_many :playlist_videos, dependent: :destroy
  has_many :playlists, through: :playlist_videos

  # Phase 13.1 — analytics tables. Cascade is delete_all because the
  # rows are derived from the YouTube Analytics API; deleting the
  # Video wipes them. Each FK is also ON DELETE CASCADE at the DB
  # level (belt-and-suspenders).
  has_many :video_dailies,                       dependent: :delete_all
  has_many :video_daily_by_countries,            dependent: :delete_all
  has_many :video_daily_by_device_types,         dependent: :delete_all
  has_many :video_daily_by_operating_systems,    dependent: :delete_all
  has_many :video_daily_by_traffic_sources,      dependent: :delete_all
  has_many :video_daily_by_subscribed_statuses,  dependent: :delete_all
  has_many :video_daily_by_age_group_genders,    dependent: :delete_all
  has_many :video_window_summaries,              dependent: :delete_all
  has_many :video_retentions,                    dependent: :delete_all

  # Phase 15 §1 — calendar entries cascade on host destroy. The FK is
  # ON DELETE CASCADE on the database level too (calendar_entries
  # migration), so this is documentation; Rails-side cascade is
  # superfluous on a CASCADE FK but harmless.
  has_many :calendar_entries, dependent: :destroy

  # Convenience reach-through. Video hits YouTube via the channel's
  # YoutubeConnection (Q4 lock). The connection is reached transitively;
  # there is no direct `youtube_connection_id` on Video for OAuth purposes
  # (the legacy column survives unrelated to the sync-back path).
  has_one :channel_youtube_connection,
          through: :channel, source: :youtube_connection

  WRITABLE_FIELDS = %i[
    title description tags category_id
    self_declared_made_for_kids contains_synthetic_media
    privacy_status publish_at project_id
  ].freeze

  # Q12 lock — switch to case-sensitive uniqueness. YouTube IDs are
  # case-sensitive on the URL side; the prior case-insensitive
  # uniqueness was semantically wrong.
  validates :youtube_video_id,
            presence: true,
            uniqueness: { case_sensitive: true }

  validates :title, length: { maximum: 100 }
  validate  :title_no_brackets
  validate  :title_required_for_publish_transition

  validate :description_no_brackets
  validate :description_byte_length

  validate :tags_total_api_length
  validate :tags_array_of_strings

  validates :category_id,
            format: { with: /\A\d+\z/, allow_blank: true,
                      message: "is not a number" }
  validate  :category_required_for_publish_transition

  validate :publish_at_must_be_in_future
  validate :publish_at_only_when_private

  enum :privacy_status,
       { private: 0, public: 1, unlisted: 2 },
       prefix: :privacy

  # Search hooks. The Searchable concern keeps this declarative-only:
  # Meilisearch indexing is a separate follow-up.
  searchable :title, :description
  filterable :privacy_status, :category_id, :channel_id, :project_id

  scope :starred, -> { where(star: true) }
  scope :published, -> { where(privacy_status: %i[public unlisted]) }
  scope :draft,
        -> { where(privacy_status: :private, publish_at: nil) }
  scope :scheduled,
        -> { where(privacy_status: :private).where.not(publish_at: nil) }
  scope :pre_publish_complete,
        -> {
          where(
            pre_publish_game_ok: true,
            pre_publish_age_ok: true,
            pre_publish_paid_promotion_ok: true,
            pre_publish_end_screen_ok: true
          ).where.not(pre_publish_checked_at: nil)
        }

  # Triggered on the controller-level update path; does NOT fire when
  # only the system-managed columns (last_synced_at, etag,
  # made_for_kids_effective, last_sync_error) or the pre_publish_*
  # booleans change.
  after_update_commit :enqueue_sync_back, if: :writable_field_changed?

  # Phase 15 §1 — Calendar derivation. Re-derives on the relevant
  # attribute changes only (gating per §"Models / hooks"). The hook
  # runs after the row commits so the `Calendar::Derivation` upsert
  # always sees the persisted state.
  CALENDAR_DERIVATION_FIELDS = %w[
    title published_at publish_at privacy_status
  ].freeze

  after_save_commit :sync_calendar_entry, if: :calendar_attributes_changed?

  # Returns true when all four checklist booleans are set AND the
  # `pre_publish_checked_at` timestamp has been stamped.
  def pre_publish_complete?
    pre_publish_game_ok? &&
      pre_publish_age_ok? &&
      pre_publish_paid_promotion_ok? &&
      pre_publish_end_screen_ok? &&
      pre_publish_checked_at.present?
  end

  # YouTube Studio deep-link for the four Studio-only fields.
  def studio_url
    "https://studio.youtube.com/video/#{youtube_video_id}/edit"
  end

  # "imported" semantic = a public/unlisted video that has never gone
  # through the pito publish flow (a pre-pito row pulled in by sync).
  # The pre-publish checklist surface keys on this — imported videos
  # never trigger the modal.
  def imported?
    pre_publish_checked_at.nil? &&
      (privacy_public? || privacy_unlisted?)
  end

  # Public for VideoSyncBack / VideoPublish to call after they have
  # synced or, on failure, surfaced the error. Distinct from the
  # private `enqueue_sync_back` hook so the job and the model don't
  # need to share any indirection.
  def writable_field_changed?
    saved_changes.keys.any? { |k| WRITABLE_FIELDS.include?(k.to_sym) }
  end

  # Phase 15 §1 — CalendarDerivable contract.

  # The entry_type the host should derive RIGHT NOW based on its state.
  # Returns nil when no derivation should exist (the
  # Derivation service flips any prior derived entry to :superseded).
  def calendar_entry_type
    if (privacy_public? || privacy_unlisted?) && published_at.present?
      :video_published
    elsif privacy_private? && publish_at.present? && publish_at > Time.current
      :video_scheduled
    end
  end

  # The attribute hash to upsert on the derived calendar entry. Returns
  # nil to signal "no derived entry should exist for the host's current
  # state."
  def calendar_entry_attributes
    case calendar_entry_type
    when :video_published
      {
        title: "video published: #{title.presence || youtube_video_id}",
        starts_at: published_at,
        all_day: false,
        video_id: id,
        state: CalendarEntry.states[:occurred],
        metadata: {}
      }
    when :video_scheduled
      {
        title: "scheduled: #{title.presence || youtube_video_id}",
        starts_at: publish_at,
        all_day: false,
        video_id: id,
        state: CalendarEntry.states[:scheduled],
        metadata: {}
      }
    end
  end

  # Source-ref pointer used for the (entry_type, source_ref) upsert
  # lookup. Two distinct refs (`kind: published` vs `kind: scheduled`)
  # so the published <-> scheduled transition does not collide on the
  # partial unique index.
  def calendar_entry_source_ref
    case calendar_entry_type
    when :video_published
      { video_id: id, kind: "published" }
    when :video_scheduled
      { video_id: id, kind: "scheduled" }
    end
  end

  # Helper: gate the after_save_commit hook on relevant attribute
  # changes only. Saves on irrelevant columns (last_synced_at, etag,
  # the pre_publish_* booleans) do NOT re-derive.
  def calendar_attributes_changed?
    saved_changes.keys.any? { |k| CALENDAR_DERIVATION_FIELDS.include?(k) }
  end

  private

  def enqueue_sync_back
    # The job is responsible for read-modify-write semantics + audit
    # logging + last_sync_error stamping. The model just enqueues.
    VideoSyncBack.perform_async(id)
  end

  def title_no_brackets
    return if title.blank?
    return unless title.match?(/[<>]/)
    errors.add(:title, "cannot contain `<` or `>`")
  end

  def title_required_for_publish_transition
    return unless will_save_change_to_privacy_status?
    return unless privacy_public? || privacy_unlisted?
    errors.add(:title, "can't be blank") if title.blank?
  end

  def description_no_brackets
    return if description.blank?
    return unless description.match?(/[<>]/)
    errors.add(:description, "cannot contain `<` or `>`")
  end

  def description_byte_length
    return if description.blank?
    return unless description.to_s.bytesize > 5000
    errors.add(:description, "is too long (max 5000 bytes)")
  end

  def tags_array_of_strings
    return if tags.nil?
    unless tags.is_a?(Array) && tags.all? { |t| t.is_a?(String) }
      errors.add(:tags, "must be an array of strings")
    end
  end

  # YouTube counts the total tags string after tags-with-spaces are
  # quoted and joined with commas. Match that semantics exactly so the
  # local validation prevents 4xx surprises from the API.
  def tags_total_api_length
    return if tags.blank?
    return unless tags.is_a?(Array)
    return unless tags.all? { |t| t.is_a?(String) }

    api_length = tags.sum do |tag|
      base = tag.length
      base += 2 if tag.include?(" ") # quotes around space-bearing tags
      base
    end
    api_length += [ tags.size - 1, 0 ].max # commas between tags

    errors.add(:tags, "are too long (max 500 API-side chars)") if api_length > 500
  end

  def category_required_for_publish_transition
    return if category_id.present?
    publishing = will_save_change_to_privacy_status? &&
                 (privacy_public? || privacy_unlisted?)
    scheduling = will_save_change_to_publish_at? && publish_at.present?
    return unless publishing || scheduling
    errors.add(:category_id, "is required when publishing")
  end

  def publish_at_must_be_in_future
    return if publish_at.blank?
    return unless will_save_change_to_publish_at?
    return if publish_at > Time.current
    errors.add(:publish_at, "must be in the future")
  end

  # API semantics — a scheduled publish keeps `privacyStatus=private` and
  # uses `publishAt`. Setting both `privacy_status=public` and
  # `publish_at` at the same time is contradictory; reject it locally
  # to make the user's intent explicit.
  def publish_at_only_when_private
    return if publish_at.blank?
    return if privacy_private?
    errors.add(:publish_at, "can only be set when privacy_status is private")
  end
end
