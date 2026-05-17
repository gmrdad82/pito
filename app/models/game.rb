# Phase 14 §1 — Game model. IGDB-backed metadata + local-only fields.
#
# Phase 27 v2 spec 03 — field partition LOCKED. The sync job
# (`GameIgdbSync` → `Igdb::SyncGame#call`) is last-write-wins on the
# IGDB-sourced columns / joins; the ownership-sourced columns / joins
# are NEVER touched by sync. The partition is enforced in two places:
#   - `Igdb::SyncGame#call` only writes IGDB columns.
#   - `GamesController#local_only_params` only permits ownership /
#     notes / footage / version inputs.
# The model spec `Game spec — sync field partition` runs a sync against
# a row with every ownership field set and asserts the post-sync
# attribute hash is unchanged for the ownership set.
#
# IGDB-sourced columns (overwritten by every re-sync, last-write-wins):
#   igdb_id, igdb_slug, igdb_checksum, title, summary, cover_image_id,
#   release_date, release_year, release_precision, igdb_rating,
#   igdb_rating_count, aggregated_rating, aggregated_rating_count,
#   total_rating, total_rating_count, external_steam_app_id,
#   ttb_main_seconds, ttb_extras_seconds, ttb_completionist_seconds,
#   igdb_synced_at, primary_genre_id (re-picked from the synced genre
#   set).
#
#   Phase 27 v2 spec 06 (2026-05-17 collapse) — the legacy
#   `external_gog_id` and `external_epic_id` columns are GONE. PC
#   distribution stores are now represented exclusively by the
#   Steam Platform row + `external_steam_app_id`; IGDB GoG / Epic
#   external-game rows are dropped by `Igdb::GameMapper` instead of
#   being mapped onto their own columns.
#
# IGDB-sourced joins (replaced wholesale on every re-sync):
#   game_genres, game_platforms, game_developers, game_publishers.
#
# Ownership-sourced columns (NEVER touched by sync):
#   played_at, recorded (single boolean per game — NOT per-platform;
#   spec 08 confirmed defer-permanently), notes, hours_of_footage_manual,
#   hours_of_footage_cached, manual_date_override, last_sync_error,
#   version_parent_id, version_title.
#
# Phase 27 follow-up (2026-05-17) — `collection_id` was dropped along
# with the entire `Collection` model. Bundle membership (M2M through
# `bundle_members`) replaces the single-pointer "collection" pattern.
#
# Ownership-sourced joins (NEVER touched by sync):
#   game_platform_ownerships (per-platform ownership join — see
#   `#owned_platforms` and the `.owned` / `.not_owned` /
#   `.owned_on(slug)` scopes), bundle_members, video_game_links.
#
# The single-valued `platform_owned_id` column is gone (Phase 27 §1a).
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

  # Phase 27 follow-up (2026-05-17) — `belongs_to :collection` removed
  # along with the Collection model + `games.collection_id` column.
  # Bundle membership (M2M through `bundle_members`) replaces the
  # single-pointer "collection" pattern.
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
  # Picked by `Games::PrimaryGenrePicker` (LOWER(name) ASC, id ASC
  # tie-break). The `before_save` hook below sets the pointer when
  # blank; `Igdb::SyncGame#call` writes it explicitly on every sync
  # (via `update_column`) so a re-sync that adds / drops genres keeps
  # the pointer current. FK is `on_delete: :nullify` (see
  # `BetaMigration3` — the column landed in the Phase 27 follow-up of
  # 2026-05-11) so deleting a genre frees the pointer without nuking
  # the game.
  belongs_to :primary_genre, class_name: "Genre", optional: true
  before_save :assign_primary_genre_if_blank

  # Played-on platform — single (1:1, not 1:N). Reflects WHERE the user
  # played the game (single canonical platform), distinct from
  # `owned_platforms` (where the user owns it, can be many) and
  # `platforms_available` (where IGDB says it's released, metadata only).
  # `played_at` remains a global "when did I play it" timestamp; this FK
  # is the orthogonal "on what" pointer. Most games start nil; user sets
  # manually. FK is nullable; no backfill.
  belongs_to :played_platform, class_name: "Platform", optional: true

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

  # Phase 27 follow-up (2026-05-17) — fire a rebuild for every bundle
  # touched by a sync / destroy event on this game. The orchestrator
  # (`Bundles::CompositeRebuildQueue`) sorts inputs alphabetically by
  # `Bundle.name` (case-insensitive) and enqueues a sequential
  # `BundleCoverBuild` chain — predictable order is load-bearing for
  # UX (which bundle is rebuilding next) and for tests (deterministic
  # enqueue order).
  #
  # Two hooks cover the two trigger surfaces this model owns:
  #   - `after_save_commit` — game re-synced from IGDB (`igdb_synced_at`
  #     changed). Rebuilds every bundle the game is currently in.
  #   - `before_destroy` + `after_destroy_commit` — game deleted.
  #     Rebuilds every bundle the game WAS in (captured pre-destroy
  #     because the after_destroy hook sees the post-cascade state).
  #
  # The add / move / remove surface is owned by `BundleMember`'s own
  # `after_commit` (single-bundle rebuilds — no chain needed) so a
  # membership change does not need a `Game`-side hook.
  after_save_commit    :rebuild_bundle_composites_on_resync
  before_destroy       :capture_pre_destroy_bundles
  after_destroy_commit :rebuild_bundle_composites_on_destroy

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
  scope :owned_on, lambda { |slug_or_slugs|
    # `where(platforms: { slug: ... })` would conflict with the legacy
    # `games.platforms` jsonb column (ActiveRecord treats the hash key
    # as a column on `games`). The raw `"platforms"."slug"` SQL is
    # safe — slug values flow through bind parameters.
    #
    # Accepts a single slug or an Array. The Array form is what the
    # filter query object (`Games::Filter`) uses when a chip token
    # like `switch2` maps to multiple DB slugs (`switch` + `switch-2`)
    # or `steam` collapses the PC family (`win` / `linux` / `mac` /
    # `dos` / `web` / `steam`). The single-slug form is preserved for
    # any callers that pass one slug directly.
    slugs = Array(slug_or_slugs)
    joins(game_platform_ownerships: :platform)
      .where('"platforms"."slug" IN (?)', slugs)
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
  scope :on_platform, lambda { |slug_or_slugs|
    # Accepts a single slug or an Array. See the parallel comment on
    # `.owned_on` for the chip-token-to-DB-slug expansion rationale
    # (`switch2` → %w[switch switch-2], `steam` → the PC family).
    slugs = Array(slug_or_slugs)
    joins(game_platforms: :platform)
      .where('"platforms"."slug" IN (?)', slugs)
      .distinct
  }
  scope :released_on,  ->(slug) { released.on_platform(slug) }
  scope :scheduled_on, ->(slug) { scheduled.on_platform(slug) }

  # Phase 27 v2 spec 06 — `played` and `wishlist` scopes for the
  # revamped filter row.
  #
  #   .played    → games with `played_at` non-null. The column was
  #                introduced in Phase 14 §1; the scope is new.
  #   .wishlist  → games with ZERO ownership rows. Orthogonal to release
  #                status — a scheduled (future) game the user has added
  #                to the library but doesn't own anywhere IS in
  #                wishlist; a released game the user doesn't own
  #                anywhere IS in wishlist. Aliases the existing
  #                `.not_owned` scope so both lexicons survive.
  scope :played,   -> { where.not(played_at: nil) }
  scope :wishlist, -> { not_owned }

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

  # Phase 27 follow-up (2026-05-17) — bundle composite rebuild hook for
  # the re-sync surface. Fires whenever `igdb_synced_at` was just
  # written (a fresh IGDB sync). Skips when the row belongs to zero
  # bundles. The `BundleMember`-side `after_commit` already covers the
  # add/remove case; this hook ONLY handles the "membership unchanged
  # but cover bytes may now point at a new IGDB asset" case.
  def rebuild_bundle_composites_on_resync
    return unless saved_change_to_igdb_synced_at?

    Bundles::CompositeRebuildQueue.new.enqueue_for_game_resync(self)
  end

  # Phase 27 follow-up (2026-05-17) — capture the game's bundles BEFORE
  # destroy so the after_destroy_commit hook can rebuild composites for
  # the bundles the game WAS in. By the time after_destroy_commit
  # fires the row is gone and the `bundle_members` rows have CASCADED
  # away — the bundle set has to be cached during the destroy
  # transaction.
  def capture_pre_destroy_bundles
    @pre_destroy_bundles = bundles.to_a
    true
  end

  # Phase 27 follow-up (2026-05-17) — bundle composite rebuild hook for
  # the destroy surface. Reads the captured pre-destroy bundle set and
  # hands it to the orchestrator. A standalone game (no bundles before
  # destroy) is a no-op.
  def rebuild_bundle_composites_on_destroy
    targets = Array(@pre_destroy_bundles).compact
    return if targets.empty?

    Bundles::CompositeRebuildQueue.new
                                  .enqueue_for_game_destroy(self, was_in: targets)
  end

  # Phase 27 v2 spec 01 — set `primary_genre_id` when blank so the
  # Genres outer-shelf can file every saved game under exactly one
  # sub-shelf. Idempotent: a row that already has a primary is left
  # alone (the picker also honors the pin internally). The hook fires
  # on every save, not only `create`, so a row whose primary was
  # nullified (FK `on_delete: :nullify`) re-picks on the next save.
  #
  # `Igdb::SyncGame#call` writes the column explicitly (via
  # `update_column`) after `sync_genres`, bypassing this hook so the
  # re-pick honors a re-shuffled IGDB genre set even when the existing
  # pointer is non-blank. This hook remains the safety net for non-sync
  # save paths (e.g. user updates the manual override, `play_at`, or
  # any local-only column on a row whose primary somehow drifted to
  # nil between syncs).
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
