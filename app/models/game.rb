# Phase 14 §1 — Game model. IGDB-backed metadata + local-only fields.
#
# IGDB-sourced columns (overwritten by every re-sync, last-write-wins):
#   igdb_id, igdb_slug, igdb_checksum, summary, cover_image_id,
#   release_date, release_year, igdb_rating, igdb_rating_count,
#   aggregated_rating, aggregated_rating_count, total_rating,
#   total_rating_count, external_steam_app_id, external_gog_id,
#   external_epic_id, ttb_main_seconds, ttb_extras_seconds,
#   ttb_completionist_seconds, title, igdb_synced_at.
#
# Local-only columns (NEVER touched by sync):
#   platform_owned_id, played_at, notes, hours_of_footage_manual,
#   hours_of_footage_cached, manual_date_override, last_sync_error.
#
# Phase 4 legacy columns (DEPRECATED — Phase 14 polish drops them):
#   `publisher` (string)  — superseded by Company + GamePublisher join.
#   `platforms` (jsonb)   — superseded by Platform + GamePlatform join.
#   `cover_art` (Active Storage attachment) — surfaces only on the
#     manual-override edit form; new code reads `cover_image_id` first.
class Game < ApplicationRecord
  # Phase 15 §1 — Calendar derivation hooks. Game derives a
  # `game_release` entry keyed on `release_date` (added in Phase 14).
  # `manual_date_override` blocks IGDB sync from overwriting a
  # user-set `starts_at`.
  include CalendarDerivable

  # Phase 14 §1 — whitelist of IGDB cover-image size tokens.
  COVER_SIZES = %w[
    t_thumb t_cover_small t_cover_big t_screenshot_med t_screenshot_big
    t_logo_med
  ].freeze

  # Phase 4 carryover. The Phase 4 ALLOWED_PLATFORMS allowlist is
  # retired in Phase 14 §1 — the `platforms` jsonb column is legacy
  # and no longer validated. Removed entirely (no validator) so the
  # legacy column can hold whatever Phase 4 wrote without raising.

  belongs_to :collection, optional: true
  has_many :footages, dependent: :nullify
  # Phase 15 §1 — calendar entries cascade.
  has_many :calendar_entries, dependent: :destroy

  # Phase 14 §1 — IGDB-backed associations.
  belongs_to :platform_owned, class_name: "Platform", optional: true,
                              foreign_key: :platform_owned_id, inverse_of: :games_owning

  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres
  has_many :game_platforms, dependent: :destroy
  has_many :platforms_available, through: :game_platforms, source: :platform
  has_many :game_developers, dependent: :destroy
  has_many :developers, through: :game_developers, source: :company
  has_many :game_publishers, dependent: :destroy
  has_many :publishers, through: :game_publishers, source: :company

  # Phase 14 §2 — Bundle membership. A Game can belong to many
  # Bundles. Cascade-on-delete from games removes the join rows;
  # `BundleCoverInvalidate` is enqueued from `after_update_commit`
  # below when `cover_image_id` changes so every bundle the game
  # belongs to gets its composite cover regenerated.
  has_many :bundle_members, dependent: :destroy
  has_many :bundles, through: :bundle_members

  # Phase 14 §2 — fire `BundleCoverInvalidate` when `cover_image_id`
  # changes. The job evicts the cached tile (so the next build
  # re-downloads the new IGDB cover bytes) and enqueues a rebuild for
  # every bundle the game belongs to.
  after_update_commit :invalidate_bundle_covers_if_image_changed

  # Phase 4 legacy — kept for one phase, dropped in polish window.
  has_one_attached :cover_art

  validates :title, presence: true, length: { maximum: 255 }
  validates :igdb_id, uniqueness: { allow_nil: true },
                      numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validates :igdb_slug, uniqueness: { allow_nil: true }
  validates :hours_of_footage_manual,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }

  attribute :title, :string, default: "Untitled game"

  scope :synced,    -> { where.not(igdb_synced_at: nil) }
  scope :unsynced,  -> { where(igdb_synced_at: nil) }
  scope :stale,     -> { where("igdb_synced_at < ?", 7.days.ago) }
  scope :with_steam, -> { where.not(external_steam_app_id: nil) }

  # IGDB cover URL builder. The IGDB CDN serves directly to the
  # browser — pito does not proxy or cache image bytes for the show
  # page or the Steam shelf (Spec 02 introduces a separate cache for
  # composite covers). Returns nil when no `cover_image_id` is set.
  def cover_url(size: "t_cover_big")
    raise ArgumentError, "Unknown cover size #{size.inspect}" unless COVER_SIZES.include?(size.to_s)
    return nil if cover_image_id.blank?
    "https://images.igdb.com/igdb/image/upload/#{size}/#{cover_image_id}.jpg"
  end

  # Manual override beats the derived cache. `nil` for both means
  # "not yet computed" — the show page renders "—" in that case.
  def hours_of_footage
    hours_of_footage_manual.presence || hours_of_footage_cached
  end

  def synced?
    igdb_synced_at.present?
  end

  # Phase 4 legacy variant helpers — kept for the polish window.
  # New views read `cover_url` first, fall back to these only when
  # IGDB has no `cover_image_id` for the game.
  def cover_art_thumbnail
    cover_art.variant(resize_to_limit: [ 100, 100 ])
  end

  def cover_art_card
    cover_art.variant(resize_to_limit: [ 300, 300 ])
  end

  def cover_art_full
    cover_art.variant(resize_to_limit: [ 4096, 4096 ])
  end

  # Phase 15 §1 — Calendar derivation contract. The `release_date`
  # column is added by Phase 14 §1 (this spec). Until both phases ship
  # together, the `respond_to?` guards keep boot resilient.
  CALENDAR_DERIVATION_FIELDS = %w[
    title release_date release_precision manual_date_override
  ].freeze

  after_save_commit :sync_calendar_entry, if: :calendar_attributes_changed?

  def calendar_entry_type
    :game_release
  end

  # Returns the upsert attribute hash for the derived calendar entry,
  # or nil when there's nothing to derive (no release_date).
  #
  # Re-syncs respect `games.manual_date_override`: when true, the
  # upsert skips `starts_at` and `release_precision` so an IGDB sync
  # cannot overwrite a user-pinned date. Manual UI edits to
  # `release_date` still flow through (the override is specifically
  # about IGDB re-sync — see master agent decision #2 in spec 01).
  def calendar_entry_attributes
    return nil unless respond_to?(:release_date)
    return nil if release_date.blank?

    install_tz = AppSetting.first&.timezone || "UTC"
    starts_at = release_date.in_time_zone(install_tz).beginning_of_day

    attrs = {
      title: "released: #{title}",
      all_day: true,
      game_id: id,
      state: starts_at <= Time.current ? CalendarEntry.states[:occurred]
                                        : CalendarEntry.states[:scheduled],
      metadata: build_release_metadata,
      manual_date_override: manual_date_override
    }

    attrs[:starts_at] = starts_at
    attrs[:release_precision] = mapped_release_precision if respond_to?(:release_precision)

    attrs
  end

  def calendar_entry_source_ref
    { game_id: id }
  end

  def calendar_attributes_changed?
    saved_changes.keys.any? { |k| CALENDAR_DERIVATION_FIELDS.include?(k) }
  end

  private

  # Pull the IGDB / metadata fields the calendar entry's metadata
  # surfaces.
  def build_release_metadata
    md = {}
    md[:platforms] = platforms.map { |p| (p["platform"] || p[:platform]) }.compact if platforms.present?
    md[:igdb_id] = igdb_id if igdb_id.present?
    md[:igdb_slug] = igdb_slug if igdb_slug.present?
    md
  end

  def mapped_release_precision
    return nil unless respond_to?(:release_precision)
    public_send(:release_precision)
  end

  # Phase 14 §2 — bundle cover invalidation hook. Passes the previous
  # `cover_image_id` explicitly so the invalidator job (running in a
  # separate Sidekiq process) can evict the now-stale tile from the
  # cache without relying on `previous_changes`.
  def invalidate_bundle_covers_if_image_changed
    return unless saved_change_to_cover_image_id?
    previous_cover_image_id = saved_change_to_cover_image_id.first
    BundleCoverInvalidate.perform_async(id, previous_cover_image_id)
  end
end
