# frozen_string_literal: true

# Where I own the game. Distinct from `Game#platforms` (text[]) which
# reflects where the game ships per IGDB. See model audit P7 §9.
class GamePlatformOwnership < ApplicationRecord
  PLATFORM_TOKENS = %w[ps switch steam].freeze

  belongs_to :game

  validates :platform_token,
            presence: true,
            inclusion: { in: PLATFORM_TOKENS }
  validates :game_id, uniqueness: { scope: :platform_token }
end
