FactoryBot.define do
  factory :production do
    title { Faker::Lorem.sentence(word_count: 4) }
    status { :idea }
    script_hours { Faker::Number.between(from: 0.0, to: 10.0).round(1) }
    filming_hours { Faker::Number.between(from: 0.0, to: 8.0).round(1) }
    editing_hours { Faker::Number.between(from: 0.0, to: 20.0).round(1) }
    thumbnail_hours { Faker::Number.between(from: 0.0, to: 3.0).round(1) }
    other_hours { Faker::Number.between(from: 0.0, to: 5.0).round(1) }
    cost_cents { Faker::Number.between(from: 0, to: 50_000) }

    trait :with_video do
      video
    end
  end
end
