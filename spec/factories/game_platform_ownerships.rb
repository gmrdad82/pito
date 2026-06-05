# frozen_string_literal: true

FactoryBot.define do
  factory :game_platform_ownership do
    game
    platform_token { GamePlatformOwnership::PLATFORM_TOKENS.sample }
  end
end
