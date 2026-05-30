# frozen_string_literal: true

class Game < ApplicationRecord
  belongs_to :primary_genre, class_name: "Genre", optional: true

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

  has_neighbors :summary_embedding

  attribute :release_precision, :integer
  enum :release_precision,
       { day: 0, month: 1, quarter: 2, year: 3, tba: 4 },
       prefix: true

  validates :title, presence: true

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
end
