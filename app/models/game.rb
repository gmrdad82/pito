# frozen_string_literal: true

class Game < ApplicationRecord
  has_many :game_genres, dependent: :destroy
  has_many :genres, through: :game_genres

  has_many :game_developers, dependent: :destroy
  has_many :developer_companies, through: :game_developers, source: :company

  has_many :game_publishers, dependent: :destroy
  has_many :publisher_companies, through: :game_publishers, source: :company

  has_many :game_platform_ownerships, dependent: :destroy
  has_many :video_game_links, dependent: :destroy
  has_many :linked_videos, through: :video_game_links, source: :video

  has_many :footages, dependent: :destroy
  has_many :stats, as: :entity, dependent: :destroy

  has_one_attached :cover_art

  # The single canonical cover-art display variant. There is ONE version: the
  # detail message, the enhanced message, and any future surface all render this
  # size (the larger 600×800 variant was dropped). The 600×800 master stays the
  # source of truth; only this variant is ever generated.
  COVER_VARIANT = { resize_to_limit: [ 450, 600 ] }.freeze

  has_neighbors :summary_embedding

  validates :title, presence: true

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
    if release_year.nil?
      return I18n.t("pito.game.release_label.month_day_unknown_year",
                    month: Date::MONTHNAMES[release_month],
                    day:   release_day) if release_month.present? && release_day.present?

      return I18n.t("pito.game.release_label.tba")
    end

    if release_month.present? && release_day.present?
      I18n.t("pito.game.release_label.day", date: I18n.l(release_date, format: :long))
    elsif release_month.present?
      I18n.t("pito.game.release_label.month_year",
              month: Date::MONTHNAMES[release_month],
              year:  release_year)
    elsif release_quarter.present?
      I18n.t("pito.game.release_label.quarter_year",
              quarter: release_quarter,
              year:    release_year)
    else
      I18n.t("pito.game.release_label.year", year: release_year)
    end
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
