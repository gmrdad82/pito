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
#   played_at, notes, hours_of_footage_manual, hours_of_footage_cached,
#   manual_date_override, last_sync_error.
#
# Per-platform ownership (Phase 27 §1a) is carried by the
# `game_platform_ownerships` join table — see `#owned_platforms` and
# the `.owned` / `.not_owned` / `.owned_on(slug)` scopes. The
# single-valued `platform_owned_id` column is gone.
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

  # Phase 20 — friendly URLs. Game URLs reuse the existing `igdb_slug`
  # column (no new slug column, no `:history` module per locked Phase
  # 20 decision #3 — IGDB owns the slug, so it never changes
  # locally). `:finders` lets `Game.friendly.find(slug_or_id)` accept
  # either a slug or an integer ID for backwards compat. `to_param`
  # falls back to `id.to_s` when `igdb_slug` is missing (legacy / not
  # yet synced rows) so the route helpers always emit a usable URL.
  extend FriendlyId
  friendly_id :igdb_slug, use: :finders

  def to_param
    igdb_slug.presence || id&.to_s
  end

  # Phase 14 §1 — whitelist of IGDB cover-image size tokens.
  # Phase 27 01e adds `t_cover_small_2x` (180 × 256 native) as the
  # source token for the `:shelf` cover-art variant rendered by
  # `Games::CoverComponent`. It downsamples cleanly into the
  # 98 × 130 shelf tile slot (65% of the 150 × 200 grid tile).
  COVER_SIZES = %w[
    t_thumb t_cover_small t_cover_small_2x t_cover_big t_screenshot_med
    t_screenshot_big t_logo_med
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
  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres

  # Phase 27 follow-up (2026-05-11) — primary-genre pointer. Each game
  # picks ONE canonical genre so the `/games` Genres outer-shelf lists
  # the game in exactly one sub-shelf instead of every genre it joins.
  # Picked by `Games::PrimaryGenrePicker` on save when blank; FK is
  # `on_delete: :nullify` (see migration) so deleting a genre frees the
  # pointer without nuking the game.
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

  has_many :game_platforms, dependent: :destroy
  has_many :platforms_available, through: :game_platforms, source: :platform
  has_many :game_developers, dependent: :destroy
  has_many :developers, through: :game_developers, source: :company
  has_many :game_publishers, dependent: :destroy
  has_many :publishers, through: :game_publishers, source: :company

  # Phase 27 §1a — per-platform ownership join. Replaces the
  # single-valued `platform_owned_id` pointer with a multi-valued set.
  # Cascade-on-delete so destroying a Game removes its ownership rows
  # (Platform deletion is restricted; see `Platform` model).
  has_many :game_platform_ownerships, dependent: :destroy
  has_many :owned_platforms, through: :game_platform_ownerships, source: :platform

  # Phase 27 §01f — nested attributes for the per-platform ownership
  # editor (`Games::PlatformOwnershipsController#update`). `allow_destroy`
  # lets the controller mark un-ticked rows for deletion via `_destroy`.
  # `reject_if` skips blank in-memory rows the editor scaffolds for
  # not-yet-owned platforms when the user leaves them unticked.
  accepts_nested_attributes_for :game_platform_ownerships,
                                allow_destroy: true,
                                reject_if: :all_blank

  # Phase 14 §2 — Bundle membership. A Game can belong to many
  # Bundles. Cascade-on-delete from games removes the join rows;
  # `BundleCoverInvalidate` is enqueued from `after_update_commit`
  # below when `cover_image_id` changes so every bundle the game
  # belongs to gets its composite cover regenerated.
  has_many :bundle_members, dependent: :destroy
  has_many :bundles, through: :bundle_members

  # Phase 14 §3 — video attribution. `dependent: :destroy` so the
  # `recompute_game_footage_cache` after_destroy_commit hook on
  # `VideoGameLink` fires for every cascaded row.
  has_many :video_game_links, dependent: :destroy
  has_many :videos, through: :video_game_links

  # Phase 14 §2 — fire `BundleCoverInvalidate` when `cover_image_id`
  # changes. The job evicts the cached tile (so the next build
  # re-downloads the new IGDB cover bytes) and enqueues a rebuild for
  # every bundle the game belongs to.
  after_update_commit :invalidate_bundle_covers_if_image_changed

  # Phase 27 §01h — fire `CollectionCoverRebuildJob` when the game's
  # `collection_id` changes (add / move / remove). The job evicts the
  # on-disk composite for BOTH the old and new collection ids so the
  # next page render re-derives them via `Collections::CoverComposer`.
  # The fingerprint catches the same change as a fallback; eviction
  # makes the next render faster (no need to re-hash 6 ids to discover
  # the cache is stale — the file literally is not there).
  after_update_commit :evict_collection_composite_on_collection_change

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

  # Phase 28 §01a — ownership rollup scope. A primary appears in
  # `owned_rollup` when EITHER the primary itself OR ANY of its editions
  # has at least one `game_platform_ownership` row. Editions appear when
  # they themselves have an ownership row. The 01b `Games::Filter`
  # `owned` token swaps to this scope so the primaries-only listing
  # respects rollup semantics (architect lean #7 locked yes).
  #
  # SQL shape: a row qualifies when its id is in the owned set OR when
  # it is a primary whose `id` matches the `version_parent_id` of any
  # owned edition. Both branches are subqueries (no joins) so the
  # resulting relation stays composable with downstream `where` chains.
  scope :owned_rollup, lambda {
    owned_ids_subquery = Game.joins(:game_platform_ownerships).select(:id)
    parents_of_owned   = Game.joins(:game_platform_ownerships)
                             .where.not(version_parent_id: nil)
                             .select(:version_parent_id)
    where(id: owned_ids_subquery)
      .or(where(id: parents_of_owned))
      .distinct
  }

  # Phase 27 §1a — ownership scopes consumed by `01b`'s filter row.
  #
  #   .owned         → at least one ownership row (DISTINCT to dedupe
  #                    games owned on multiple platforms).
  #   .not_owned     → zero ownership rows.
  #   .owned_on(sl)  → ownership row whose platform matches the slug.
  scope :owned, -> { joins(:game_platform_ownerships).distinct }
  scope :not_owned, lambda {
    left_joins(:game_platform_ownerships)
      .where(game_platform_ownerships: { id: nil })
  }
  scope :owned_on, lambda { |slug|
    # `where(platforms: { slug: ... })` would conflict with the legacy
    # `games.platforms` jsonb column (ActiveRecord treats the hash key
    # as a column on `games`). The raw `"platforms"."slug"` SQL is
    # safe — `slug` flows through bind parameters.
    joins(game_platform_ownerships: :platform)
      .where('"platforms"."slug" = ?', slug)
      .distinct
  }

  # Phase 27 §01b — status + IGDB-platform scopes consumed by the
  # filter row.
  #
  #   .recorded            → games with at least one linked Video.
  #   .released            → `release_date <= today` (boundary inclusive
  #                          on the past side; nil dates excluded).
  #   .scheduled           → `release_date > today`; nil dates excluded.
  #   .on_platform(slug)   → games released/scheduled on the IGDB-reported
  #                          platform (rides on `:platforms_available`, NOT
  #                          the per-platform-ownership join). "Available
  #                          on" is metadata; "owned on" is the library.
  #   .released_on(slug)   → `released.on_platform(slug)`.
  #   .scheduled_on(slug)  → `scheduled.on_platform(slug)`.
  #
  # The spec was authored against an imagined `first_release_date`
  # datetime column; the actual schema (Phase 14 §1) stores `release_date`
  # as a `date`. The day-granular comparison is identical semantically:
  # a release scheduled for today is "released"; tomorrow is "scheduled".
  #
  # The raw `"platforms"."slug" = ?` SQL mirrors the `owned_on` pattern
  # for the same `games.platforms` jsonb collision reason; the slug is
  # bound (no SQL injection risk).
  scope :recorded, -> { where(id: VideoGameLink.select(:game_id).distinct) }
  scope :released, -> { where("release_date <= ?", Date.current) }
  scope :scheduled, -> { where("release_date > ?", Date.current) }
  scope :on_platform, lambda { |slug|
    joins(game_platforms: :platform)
      .where('"platforms"."slug" = ?', slug)
      .distinct
  }
  scope :released_on,  ->(slug) { released.on_platform(slug) }
  scope :scheduled_on, ->(slug) { scheduled.on_platform(slug) }

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

  # Phase 28 §01a — version-grouping predicates.
  def primary?
    version_parent_id.nil?
  end

  def edition?
    version_parent_id.present?
  end

  # Phase 28 §01a — ownership rollup helpers. The base `owned_platforms`
  # association is preserved as-is (per-row ownership through the join);
  # these helpers add the rollup semantics specific to the multi-version
  # listing surfaces.
  #
  # `owned_platforms_with_editions` for a primary unions the primary's
  # own ownerships with every edition's ownerships, deduped. For an
  # edition it is equivalent to `owned_platforms` (an edition has no
  # editions of its own — single-level nesting locked).
  def owned_platforms_with_editions
    return owned_platforms unless primary?

    ids = [ id, *editions.ids ]
    Platform.joins(:game_platform_ownerships)
            .where(game_platform_ownerships: { game_id: ids })
            .distinct
            .order(:name)
  end

  # Returns the editions you own on the given platform. Empty for a
  # primary with no editions, and empty for an edition (no recursion).
  def owned_editions(platform)
    return Game.none unless primary?
    return Game.none if platform.nil?

    editions.joins(:game_platform_ownerships)
            .where(game_platform_ownerships: { platform_id: platform.id })
            .distinct
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

  # Phase 27 §01h — collection composite eviction hook. Enqueues
  # `CollectionCoverRebuildJob` with both the previous and current
  # `collection_id` so the job sweeps stale files on both sides of
  # the move. Sidekiq runs in a separate process, so the in-memory
  # `saved_changes` from the originating after_update_commit is gone
  # by the time the job executes — the args are passed explicitly.
  def evict_collection_composite_on_collection_change
    return unless saved_change_to_collection_id?
    previous_id, current_id = saved_change_to_collection_id
    CollectionCoverRebuildJob.perform_async(previous_id, current_id)
  end

  # Phase 27 follow-up (2026-05-11) — set `primary_genre_id` when blank
  # so the Genres outer-shelf can file every saved game under exactly
  # one sub-shelf. Idempotent: a row that already has a primary is left
  # alone (the picker also honors the pin internally). The hook fires
  # on every save, not only `create`, so a row whose primary was
  # nullified (FK `on_delete: :nullify`) re-picks on the next save.
  def assign_primary_genre_if_blank
    return if primary_genre_id.present?
    pick = Games::PrimaryGenrePicker.new.pick(self)
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
