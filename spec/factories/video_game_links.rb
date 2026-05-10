# Phase 14 §3 — `video_game_link` factory.
#
# Defaults to a `game` link. Use the `:bundle` trait for bundle links.
FactoryBot.define do
  factory :video_game_link do
    video
    link_type { :game }
    game { association(:game) }
    bundle { nil }
    is_primary { false }

    trait :bundle do
      link_type { :bundle }
      game { nil }
      bundle { association(:bundle) }
    end

    trait :primary do
      is_primary { true }
    end
  end
end
