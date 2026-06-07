# frozen_string_literal: true

FactoryBot.define do
  factory :stat do
    association :entity, factory: :channel
    kind { "views" }
    value { 1_000 }
    synced_at { Time.current }
  end
end
