FactoryBot.define do
  factory :video_diff do
    video
    detected_at { Time.current }
    payload do
      {
        "title" => { "pito" => "local title", "youtube" => "remote title" }
      }
    end
    resolved_at { nil }
    resolution_payload { nil }

    trait :resolved do
      resolved_at { Time.current }
      resolution_payload { { "title" => "youtube" } }
    end

    trait :multi_field do
      payload do
        {
          "title"        => { "pito" => "local title", "youtube" => "remote title" },
          "description"  => { "pito" => "local body",  "youtube" => "remote body" },
          "tags"         => { "pito" => [ "a", "b" ],   "youtube" => [ "a", "c" ] }
        }
      end
    end
  end
end
