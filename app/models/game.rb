# Phase 14 §1 — Game model. IGDB-backed metadata + local-only fields.
#
# IGDB-sourced columns (overwritten by every re-sync, last-write-wins):
#   igdb_id, igdb_slug, igdb_checksum, title, summary, cover_image_id,
#   release_date, release_year, release_precision, igdb_rating,
#   igdb_rating_count, aggregated_rating, aggregated_rating_count,
#   total_rating, total_rating_count, external_steam_app_id,
#   ttb_main_seconds, ttb_extras_seconds, ttb_completionist_seconds,
#   igdb_synced_at, primary_genre_id (re-picked from the synced genre set).
#
# IGDB-sourced joins (replaced wholesale on every re-sync):
#   game_genres, game_developers, game_publishers.
#
# Local-only columns (NEVER touched by sync):
#   played_at, recorded, notes, hours_of_footage_manual,
#   hours_of_footage_cached, manual_date_override, last_sync_error,
#   version_parent_id, version_title.
#
# Phase 4 legacy:
#   `cover_art` (Active Storage attachment) — surfaces only on the
#     manual-override edit form; new code reads `cover_image_id` first.
class Game < ApplicationRecord
  # Phase 15 §1 — Calendar derivation hooks. Game derives a
  # `game_release` entry keyed on `release_date` (added in Phase 14).
  # `manual_date_override` blocks IGDB sync from overwriting a
  # user-set `starts_at`.
  include CalendarDerivable

  # Phase 34 (2026-05-18) — pgvector neighbor lookups on the Voyage
  # `summary_embedding` column. Powers `Game::SimilarGames` (similar
  # games by vector cosine distance). Distance is cosine (matches the
  # `vector_cosine_ops` HNSW index in `db/schema.rb`).
  has_neighbors :summary_embedding

  def to_param
    igdb_slug.presence || id&.to_s
  end

  # Phase 14 §1 — whitelist of IGDB cover-image size tokens.
  # Phase 27 01e adds `t_cover_small_2x` (180 × 256 native) as the
  # source token for the `:shelf` cover-art variant rendered by
  # `Game::CoverComponent`. It downsamples cleanly into the
  # 98 × 130 shelf tile slot (65% of the 150 × 200 grid tile).
  # `t_cover_big_2x` (~528 × 748 native) is the highest-resolution cover
  # variant IGDB serves. Retained for high-DPI surfaces that need it.
  COVER_SIZES = %w[
    t_thumb t_cover_small t_cover_small_2x t_cover_big t_cover_big_2x
    t_screenshot_med t_screenshot_big t_logo_med
  ].freeze

  # Phase 4 carryover. The Phase 4 ALLOWED_PLATFORMS allowlist is
  # retired in Phase 14 §1 — the `platforms` jsonb column is legacy
  # and no longer validated. Removed entirely (no validator) so the
  # legacy column can hold whatever Phase 4 wrote without raising.

  # Phase 27 follow-up (2026-05-17) — `belongs_to :collection` removed
  # along with the Collection model + `games.collection_id` column.
  # R1 (2026-05-25) — Bundle membership also removed.
  has_many :footages, dependent: :nullify
  # Phase 15 §1 — calendar entries cascade.
  has_many :calendar_entries, dependent: :destroy

  # Phase 14 §1 — IGDB-backed associations.
  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres

  # Phase 27 v2 spec 01 — single main genre per Game. Each game has
  # EXACTLY ONE canonical primary genre (or nil when IGDB reports
  # zero). Every UI surface renders `primary_genre.name` (or `"—"`)
  # — never a comma-joined list. The legacy multi-valued `game_genres`
  # join survives as the IGDB raw record so the picker can re-evaluate
  # the choice on each re-sync without re-fetching from IGDB.
  #
  # Picked by `Game::PrimaryGenrePicker` (LOWER(name) ASC, id ASC
  # tie-break). The `before_save` hook below sets the pointer when
  # blank; `Game::Igdb::SyncGame#call` writes it explicitly on every sync
  # (via `update_column`) so a re-sync that adds / drops genres keeps
  # the pointer current. FK is `on_delete: :nullify` (see
  # `BetaMigration3` — the column landed in the Phase 27 follow-up of
  # 2026-05-11) so deleting a genre frees the pointer without nuking
  # the game.
  belongs_to :primary_genre, class_name: "Genre", optional: true
  before_save :assign_primary_genre_if_blank

  # Phase 28 §01a — Multi-version game grouping. A `Game` may be either
  # a primary (`version_parent_id IS NULL`) or an edition pointing at a
  # primary. Editions cannot themselves parent another edition (single
  # level of nesting). `dependent: :nullify` on the editions
  # association — destroying a parent leaves its editions in place as
  # orphan primaries (locked decision #7 in the umbrella plan).
  belongs_to :version_parent, class_name: "Game", optional: true
  has_many :editions,
           class_name: "Game",
           foreign_key: :version_parent_id,
           inverse_of: :version_parent,
           dependent: :nullify

  before_save :derive_release_date_from_editions
  validate :version_parent_must_be_primary
  validate :cannot_be_parent_and_edition_simultaneously
  validate :no_self_reference

  has_many :game_developers, dependent: :destroy
  has_many :developers, through: :game_developers, source: :company
  has_many :game_publishers, dependent: :destroy
  has_many :publishers, through: :game_publishers, source: :company

  # Phase 14 §3 — video attribution. `dependent: :destroy` so the
  # `recompute_game_footage_cache` after_destroy_commit hook on
  # `VideoGameLink` fires for every cascaded row.
  has_many :video_game_links, dependent: :destroy
  has_many :videos, through: :video_game_links

  # 2026-05-19 — /games index live refresh. Every Game create / update /
  # destroy broadcasts a Turbo `refresh` signal to the `"games"` stream
  # so the /games shelves (recently-played + genres + bundles + letter
  # buckets) re-render without a manual page reload. The index view
  # subscribes via `<%= turbo_stream_from "games" %>`. Update is needed
  # in addition to create because the "add a game" flow stores a near-
  # empty row first, then `Game::Igdb::SyncGame#call` populates title /
  # genres / cover_image_id / primary_genre_id asynchronously — those
  # writes are `update!` / `save!` and must trigger a refresh too.
  # `turbo-refresh-method=morph` + `turbo-refresh-scroll=preserve` in
  # the layout make this a scroll-preserving in-place morph.
  after_create_commit  -> { broadcast_refresh_later_to("games") }
  after_update_commit  -> { broadcast_refresh_later_to("games") }
  after_destroy_commit -> { broadcast_refresh_to("games") }

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

  # Phase 28 §01a — multi-version grouping scopes.
  #
  #   .primaries           → rows with `version_parent_id IS NULL`.
  #   .editions_of(game)   → rows whose `version_parent_id` equals the
  #                          given game's id; returns an empty relation
  #                          gracefully when game / game.id is nil.
  #   .with_editions       → primaries that have at least one edition.
  scope :primaries, -> { where(version_parent_id: nil) }
  scope :editions_of, lambda { |game|
    if game&.id.nil?
      none
    else
      where(version_parent_id: game.id)
    end
  }
  scope :with_editions, lambda {
    where(version_parent_id: nil)
      .where(id: Game.where.not(version_parent_id: nil).select(:version_parent_id))
  }

  # Status scopes consumed by the filter row.
  #
  #   .recorded  → games with at least one linked Video.
  #   .released  → `release_date <= today`; nil dates excluded.
  #   .scheduled → `release_date > today`; nil dates excluded.
  #   .played    → games with `played_at` non-null.
  scope :recorded,  -> { where(id: VideoGameLink.select(:game_id).distinct) }
  scope :released,  -> { where("release_date <= ?", Date.current) }
  scope :scheduled, -> { where("release_date > ?", Date.current) }
  scope :played,    -> { where.not(played_at: nil) }

  # IGDB cover URL builder. The IGDB CDN serves directly to the
  # browser — pito does not proxy or cache image bytes for the show
  # page or the Steam shelf (Spec 02 introduces a separate cache for
  # composite covers). Returns nil when no `cover_image_id` is set.
  def cover_url(size: "t_cover_big")
    raise ArgumentError, "Unknown cover size #{size.inspect}" unless COVER_SIZES.include?(size.to_s)
    return nil if cover_image_id.blank?
    "https://images.igdb.com/igdb/image/upload/#{size}/#{cover_image_id}.jpg"
  end

  # Phase 27 follow-up (2026-05-17) — Normalized cover master accessors.
  #
  # The cover-art normalizer (`Game::CoverArt::Normalizer`) writes a
  # canonical 600×800 JPEG to
  # `<PITO_ASSETS_PATH>/covers/games/<game_id>/master.jpg`. `public/covers/`
  # is a symlink into the same volume so Rails' static-file middleware
  # serves the bytes at `/covers/games/<game_id>/master.jpg` with no
  # controller hop. The `covers/games/` sub-namespace pairs with
  # `covers/bundles/<id>/composite.jpg` (bundle composites) under the
  # unified `/covers/` namespace.
  #
  # `cover_master_url` returns the local master URL when the master
  # file is present on disk; otherwise falls back to the IGDB CDN URL
  # at the requested size token so unsynced / not-yet-normalized rows
  # still render. Returns nil when there's neither a master nor a
  # `cover_image_id` (truly coverless).
  #
  # `cover_master_path` returns the absolute filesystem path when the
  # master is present; otherwise nil. Used by libvips consumers that
  # benefit from the local fast path (composite tile builder, future
  # variants).
  def cover_master_url(fallback_size: "t_cover_big_2x")
    if cover_master_path
      "/covers/games/#{id}/master.jpg"
    elsif cover_image_id.present?
      cover_url(size: fallback_size)
    end
  end

  def cover_master_path
    path = Pito::AssetsRoot.path("covers", "games", id.to_s, "master.jpg")
    path.exist? ? path.to_s : nil
  end

  # Manual override beats the derived cache. `nil` for both means
  # "not yet computed" — the show page renders "—" in that case.
  def hours_of_footage
    hours_of_footage_manual.presence || hours_of_footage_cached
  end

  def synced?
    igdb_synced_at.present?
  end

  # Phase 28 §01a — version-grouping predicates.
  def primary?
    version_parent_id.nil?
  end

  def edition?
    version_parent_id.present?
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

    install_tz = Rails.application.config.x.pito.timezone
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
    md[:igdb_id] = igdb_id if igdb_id.present?
    md[:igdb_slug] = igdb_slug if igdb_slug.present?
    md
  end

  def mapped_release_precision
    return nil unless respond_to?(:release_precision)
    public_send(:release_precision)
  end

  # Phase 27 v2 spec 01 — set `primary_genre_id` when blank so the
  # Genres outer-shelf can file every saved game under exactly one
  # sub-shelf. Idempotent: a row that already has a primary is left
  # alone (the picker also honors the pin internally). The hook fires
  # on every save, not only `create`, so a row whose primary was
  # nullified (FK `on_delete: :nullify`) re-picks on the next save.
  #
  # `Game::Igdb::SyncGame#call` writes the column explicitly (via
  # `update_column`) after `sync_genres`, bypassing this hook so the
  # re-pick honors a re-shuffled IGDB genre set even when the existing
  # pointer is non-blank. This hook remains the safety net for non-sync
  # save paths (e.g. user updates the manual override, `play_at`, or
  # any local-only column on a row whose primary somehow drifted to
  # nil between syncs).
  def assign_primary_genre_if_blank
    return if primary_genre_id.present?
    pick = Game::PrimaryGenrePicker.new.pick(self)
    self.primary_genre_id = pick&.id
  end

  # Phase 28 §01a — derive a primary's `release_date` from the
  # earliest edition's date when the primary has none of its own
  # (architect lean #1 locked). Only runs for primaries (a row with a
  # `version_parent_id` is an edition and owns its own date). The hook
  # runs `before_save` so the derived date persists in the same write
  # and the calendar derivation hook (`after_save_commit`) picks it up
  # in the same transaction.
  #
  # Skips when `manual_date_override` is true — a user-pinned date wins
  # over any derived date (mirrors the IGDB re-sync override semantic).
  def derive_release_date_from_editions
    return if version_parent_id.present?
    return if release_date.present?
    return if manual_date_override
    return unless persisted?

    earliest = editions.where.not(release_date: nil).minimum(:release_date)
    return if earliest.blank?

    self.release_date = earliest
    self.release_year = earliest.year if respond_to?(:release_year)
  end

  # Phase 28 §01a — validation: `version_parent_id` must point at a
  # primary. Prevents two-level chains (an edition cannot itself be
  # parented by another edition).
  def version_parent_must_be_primary
    return if version_parent_id.blank?
    return if version_parent_id == id # caught by `no_self_reference`

    parent = Game.where(id: version_parent_id).select(:id, :version_parent_id).first
    return if parent.nil? # FK validation surfaces "must exist" via belongs_to
    return if parent.version_parent_id.nil?

    errors.add(:version_parent_id, "must be a primary (cannot point at an edition)")
  end

  # Phase 28 §01a — validation: a row that already has editions cannot
  # itself become an edition. Prevents flipping a parent into an
  # edition while it still has children.
  def cannot_be_parent_and_edition_simultaneously
    return if version_parent_id.blank?
    return unless persisted?
    return if Game.where(version_parent_id: id).none?

    errors.add(:version_parent_id, "cannot be set: this row already has editions")
  end

  # Phase 28 §01a — validation: no self-reference.
  def no_self_reference
    return if version_parent_id.blank?
    return unless persisted?
    return unless version_parent_id == id

    errors.add(:version_parent_id, "cannot reference itself")
  end
end
