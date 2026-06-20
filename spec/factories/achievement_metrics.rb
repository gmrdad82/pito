# frozen_string_literal: true

FactoryBot.define do
  factory :achievement_metric do
    association :achievable, factory: :video
    metric { "views" }
    value { 1_234 }
    synced_at { Time.current }
  end
end
