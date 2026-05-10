FactoryBot.define do
  factory :bundle do
    sequence(:name) { |n| "Bundle #{n}" }
    bundle_type { :custom }

    trait :series do
      bundle_type { :series }
      igdb_source_type { :franchise }
      sequence(:igdb_source_id) { |n| 100_000 + n }
    end

    trait :collection do
      bundle_type { :collection }
      igdb_source_type { :source_collection }
      sequence(:igdb_source_id) { |n| 200_000 + n }
    end

    trait :genre do
      bundle_type { :genre }
      igdb_source_type { :source_genre }
      sequence(:igdb_source_id) { |n| 300_000 + n }
    end
  end
end
