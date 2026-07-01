# frozen_string_literal: true

# One release date per platform GROUP for a game (Item 24).
#
# IGDB reports a release date per platform; pito stores one row per platform
# GROUP (token — ps / switch / steam / xbox) with the same component shape as
# Game (year + quarter/month/day) plus a derived lower-bound `release_date`.
#
# Distinct rows are kept even when several platforms share the same date — the
# same-date collapse happens only at RENDER (owner: "keep distinct values per
# platform, clobber them when rendering"). The single games.release_* columns
# remain a derived "earliest across platforms" for scopes/sorting.
class GamePlatformRelease < ApplicationRecord
  belongs_to :game

  # Single source of truth for the valid tokens: Pito::Game::PlatformTokens.
  PLATFORM_TOKENS = Pito::Game::PlatformTokens::ORDER

  validates :platform_token,
            presence:   true,
            inclusion:  { in: PLATFORM_TOKENS },
            uniqueness: { scope: :game_id }
  validate :release_date_components_are_consistent

  # Keep the derived date in step with the components (mirrors Game).
  before_save :recompute_release_date

  private

  # Mirrors Game#release_date_components_are_consistent — model validations are
  # UX; the DB enforces the (game_id, platform_token) uniqueness.
  def release_date_components_are_consistent
    if release_quarter.present? && release_month.present?
      errors.add(:release_quarter, "and month are mutually exclusive")
    end

    errors.add(:release_day, "requires month") if release_day.present? && release_month.nil?

    if release_quarter.present? && !release_quarter.between?(1, 4)
      errors.add(:release_quarter, "out of range")
    end

    if release_month.present? && !release_month.between?(1, 12)
      errors.add(:release_month, "out of range")
    end

    return unless release_year.present? && release_month.present? && release_day.present?

    begin
      Date.new(release_year, release_month, release_day)
    rescue Date::Error
      errors.add(:base, "invalid date")
    end
  end

  def recompute_release_date
    self.release_date = Pito::Game::ReleaseDateMapper.call(
      year:    release_year,
      quarter: release_quarter,
      month:   release_month,
      day:     release_day
    )[:release_date]
  end
end
