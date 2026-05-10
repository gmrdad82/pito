FactoryBot.define do
  factory :game do
    sequence(:title) { |n| "Game #{n}" }
    publisher { nil }
    platforms { [ { "platform" => "PS5", "owned" => true, "recorded_on" => true } ] }

    trait :with_collection do
      collection
    end

    # Attaches the bundled spec/fixtures/files/cover_art.jpg fixture. Variant
    # generation is NOT exercised here (libvips not assumed installed in dev);
    # Phase B's variant tests will install libvips + add a system-test fixture.
    trait :with_cover_art do
      after(:build) do |game|
        game.cover_art.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/cover_art.jpg")),
          filename: "cover_art.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end
