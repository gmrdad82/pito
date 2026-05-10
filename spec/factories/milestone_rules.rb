FactoryBot.define do
  factory :milestone_rule do
    sequence(:name) { |n| "Milestone #{n}" }
    scope_type { :install }
    scope_id { nil }
    metric { "subscriberCount" }
    metric_window { :lifetime }
    threshold { 100 }
    direction { :cross_up }
    enabled { true }

    trait :install do
      scope_type { :install }
      scope_id { nil }
    end

    trait :channel_scope do
      scope_type { :channel }
      scope_id { create(:channel).id }
    end

    trait :video_scope do
      scope_type { :video }
      scope_id { create(:video).id }
    end

    trait :fired do
      fired_at { 1.hour.ago }
    end

    trait :disabled do
      enabled { false }
    end

    trait :cross_down do
      direction { :cross_down }
    end
  end
end
