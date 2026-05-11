FactoryBot.define do
  factory :game do
    sequence(:title) { |n| "Game #{n}" }
    # `publisher` and `platforms` are Phase 4 legacy columns. The Phase 14
    # §1 model no longer validates them. New tests should NOT read these;
    # we keep a default `platforms` value so the small number of pre-Phase-14
    # specs (e.g. `spec/requests/projects_spec.rb` reading
    # `game.platforms.first["platform"]`) stay green until the polish window.
    publisher { nil }
    platforms { [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ] }

    trait :with_collection do
      collection
    end

    # Phase 14 §1 — fully-synced row. Stamps every IGDB-sourced column
    # so specs needing a realized post-sync record can `create(:game, :synced)`.
    trait :synced do
      sequence(:igdb_id) { |n| 9_000_000 + n }
      sequence(:igdb_slug) { |n| "synced-game-#{n}" }
      igdb_checksum { "checksum-#{SecureRandom.hex(4)}" }
      summary { "An IGDB-synced game." }
      cover_image_id { "co1u7n" }
      release_date { Date.new(2017, 3, 3) }
      release_year { 2017 }
      igdb_rating { 90.50 }
      igdb_rating_count { 100 }
      aggregated_rating { 92.00 }
      aggregated_rating_count { 50 }
      total_rating { 91.00 }
      total_rating_count { 150 }
      external_steam_app_id { "1086940" }
      ttb_main_seconds { 180_000 }
      ttb_extras_seconds { 360_000 }
      ttb_completionist_seconds { 720_000 }
      igdb_synced_at { Time.current }
    end

    trait :stale do
      synced
      igdb_synced_at { 8.days.ago }
    end

    # Phase 4 legacy attachment. Variant generation is NOT exercised
    # here (libvips not assumed installed in dev).
    trait :with_cover_art do
      after(:build) do |game|
        game.cover_art.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/cover_art.jpg")),
          filename: "cover_art.jpg",
          content_type: "image/jpeg"
        )
      end
    end

    # Phase 28 §01a — edition trait. Creates an unrelated primary on
    # the fly when no `version_parent` association is passed.
    trait :edition do
      association :version_parent, factory: :game
      version_title { "Deluxe" }
    end
  end
end
