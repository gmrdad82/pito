# frozen_string_literal: true

FactoryBot.define do
  factory :game_platform_release do
    game
    platform_token { "ps" }
    release_year   { 2026 }
    release_month  { 7 }
    release_day    { 31 }
  end
end
