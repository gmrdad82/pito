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

  has_many :stats, as: :entity, dependent: :destroy
  has_many :achievements, as: :achievable, dependent: :destroy
  has_many :achievement_metrics, as: :achievable, dependent: :destroy

  has_one_attached :cover_art do |attachable|
    # :detail — 450px-wide portrait for the game detail card and the video
    # linked-game card cover box. resize_to_limit preserves aspect ratio and
    # never upscales below the natural size.
    attachable.variant :detail, resize_to_limit: [ 450, 600 ]
    # :strip — exact 180×240px fill for the similar-games strip card.
    # resize_to_fill crops to the exact display dimensions so the browser
    # performs no downscale (eliminates subpixel blur on the strip).
    attachable.variant :strip,  resize_to_fill:  [ 180, 240 ]
  end

  has_neighbors :summary_embedding

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
  # `synced`  → has been synced at least once from IGDB.
  # `stale`   → synced more than 7 days ago (due for a re-sync).
  scope :synced, -> { where.not(igdb_synced_at: nil) }
  scope :stale,  -> { where(igdb_synced_at: ..7.days.ago) }

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
    update!(score: Pito::Game::ScoreCalculator.call(self))
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
    new_score = Pito::Game::ScoreCalculator.call(self)
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
    Pito::Game::ReleaseDateMapper.call(
      year:    release_year,
      quarter: release_quarter,
      month:   release_month,
      day:     release_day
    )[:release_date]
  rescue Pito::Error::ReleaseDateInconsistent
    nil
  end
end
