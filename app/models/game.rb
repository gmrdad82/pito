# frozen_string_literal: true

class Game < ApplicationRecord
  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres

  has_many :game_developers, dependent: :destroy
  has_many :developer_companies, through: :game_developers, source: :company

  has_many :game_publishers, dependent: :destroy
  has_many :publisher_companies, through: :game_publishers, source: :company

  has_many :video_game_links, dependent: :destroy
  has_many :linked_videos, through: :video_game_links, source: :video

  # Per-platform release dates (Item 24) — one row per platform group.
  has_many :platform_releases, class_name: "GamePlatformRelease", dependent: :destroy

  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  has_one_attached :cover_art do |attachable|
    # Variants are 2× their CSS display size so hiDPI/retina screens (every
    # phone) render sharp; display boxes stay pinned in CSS.
    # :detail — displayed 450px wide (game detail card + the video linked-game
    # card cover box). resize_to_limit preserves aspect ratio and never
    # upscales below the natural size (t_1080p masters cover 2× comfortably).
    attachable.variant :detail, resize_to_limit: [ 900, 1200 ]
    # :strip — displayed exactly 180×240 (similar-games strip card).
    # resize_to_fill crops to 2× the display box; the CSS box + object-fit do
    # the clean 2:1 downscale on 1× screens.
    attachable.variant :strip,  resize_to_fill:  [ 360, 480 ]
  end

  has_neighbors :summary_embedding

  # Resolve a free-text title to a Game for the `search games like <title>` seed
  # (#8): exact case-insensitive match first, then a pg_trgm fuzzy fallback
  # (best match above the trigram threshold), backed by index_games_on_title_trigram.
  # Returns nil when nothing matches.
  def self.resolve_by_title(query)
    q = query.to_s.strip
    return nil if q.blank?

    exact = find_by("title ILIKE ?", q)
    return exact if exact

    where("title % ?", q)
      .order(Arel.sql("similarity(title, #{connection.quote(q)}) DESC"))
      .first
  end

  validates :title, presence: true

  # Price (EUR) has three meanings: nil = unset/unknown (renders "—"), an explicit
  # 0 = deliberately free (renders the star — genuine value), and > 0 = priced
  # (renders coin tiers; see Pito::Coin). So 0 is allowed and distinct from nil.
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # ── Release-date component validations ──────────────────────────
  validate :release_date_components_are_consistent

  before_save :recompute_release_date

  scope :released_in, ->(year) { where(release_year: year) }
  scope :tba, -> { where(release_year: nil) }
  scope :upcoming, -> { where("release_date > ? OR release_year IS NULL", Date.current) }

  # Nightly-refresh scopes — used by GameIgdbNightlyRefresh.
  # `synced`           → has been synced at least once from IGDB.
  # `awaiting_release` → still awaited SOMEWHERE (Item 51). A game (or one of
  #   its platform rows) is SETTLED only by a DAY-precision date in the past —
  #   "sync until a fixed clear date" (owner 2026-07-02): TBA, a future date,
  #   or a bare year/quarter/month (release_day NULL — the derived
  #   release_date is just the window's lower bound, so "past" proves nothing)
  #   all keep the game refreshing until IGDB supplies the concrete day.
  #   `upcoming` can't serve this: the game-level release_date is the EARLIEST
  #   across platforms, so it goes past as soon as the first platform ships.
  scope :synced, -> { where.not(igdb_synced_at: nil) }
  scope :awaiting_release, lambda {
    where(
      "(games.release_year IS NULL OR games.release_day IS NULL OR games.release_date > :today) OR EXISTS (
         SELECT 1 FROM game_platform_releases gpr
         WHERE gpr.game_id = games.id
           AND (gpr.release_year IS NULL OR gpr.release_day IS NULL OR gpr.release_date > :today)
       )",
      today: Date.current
    )
  }

  # ── Score (vote-weighted average of IGDB rating triplets) ─────
  RATING_FIELDS = %i[
    igdb_rating igdb_rating_count
    aggregated_rating aggregated_rating_count
    total_rating total_rating_count
  ].freeze

  # Maximum absolute drift allowed during auto-recompute. Prevents a
  # single glitched IGDB sync from wiping a well-established score.
  # Manual calls to `recompute_score!` bypass this guard.
  SCORE_DRIFT_THRESHOLD = 30

  before_save :auto_recompute_score, if: :rating_fields_changed?

  # Bypasses the drift guard — a deliberate action (e.g. backfill).
  def recompute_score!
    update!(score: Pito::Games::ScoreCalculator.call(self))
  end

  # A game has no native audience counters — its views/likes are MATERIALIZED
  # into its own Pito::Stats rows by Game::StatsRefresh (sum of linked vids;
  # recomputed on link edits + every stats pass, G28). Reads never live-sum.
  # `.to_i` → 0 before the first rollup (owner G26.2: 0 when unlinked).
  def view_count
    Pito::Stats.get(self, :views).to_i
  end

  def like_count
    Pito::Stats.get(self, :likes).to_i
  end

  def released?
    effective = release_date || derive_release_date
    return false if effective.nil?

    effective <= Date.current
  end

  def tba?
    igdb_synced_at.present? && release_year.nil?
  end

  def release_label
    Pito::Formatter::ReleaseDate.call(self)
  end

  private

  def rating_fields_changed?
    RATING_FIELDS.any? { |f| will_save_change_to_attribute?(f) }
  end

  def auto_recompute_score
    new_score = Pito::Games::ScoreCalculator.call(self)
    if score_drift_too_large?(new_score)
      raise Pito::Error::ScoreDrift.new(
        game: self, old_score: score, new_score: new_score
      )
    end
    self.score = new_score
  end

  def score_drift_too_large?(new_score)
    return false if score.nil?

    (new_score - score).abs > SCORE_DRIFT_THRESHOLD
  end

  def release_date_components_are_consistent
    if release_quarter.present? && release_month.present?
      errors.add(:release_quarter, "and month are mutually exclusive")
    end

    if release_day.present? && release_month.nil?
      errors.add(:release_day, "requires month")
    end

    if release_quarter.present? && !release_quarter.between?(1, 4)
      errors.add(:release_quarter, "out of range")
    end

    if release_month.present? && !release_month.between?(1, 12)
      errors.add(:release_month, "out of range")
    end

    if release_year.present? && release_month.present? && release_day.present?
      begin
        Date.new(release_year, release_month, release_day)
      rescue Date::Error
        errors.add(:base, "invalid date")
      end
    end
  end

  def recompute_release_date
    self.release_date = derive_release_date
  end

  def derive_release_date
    Pito::Games::ReleaseDateMapper.call(
      year:    release_year,
      quarter: release_quarter,
      month:   release_month,
      day:     release_day
    )[:release_date]
  rescue Pito::Error::ReleaseDateInconsistent
    nil
  end
end
