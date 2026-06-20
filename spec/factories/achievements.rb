# frozen_string_literal: true

FactoryBot.define do
  factory :achievement do
    association :achievable, factory: :video
    metric { "views" }
    threshold { 1_000 }
    unlocked_at { Time.current }
  end
end
