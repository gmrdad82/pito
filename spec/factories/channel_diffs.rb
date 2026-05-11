FactoryBot.define do
  factory :channel_diff do
    channel
    detected_at { Time.current }
    field_diffs do
      {
        "title" => { "pito" => "local title", "youtube" => "remote title" }
      }
    end
    resolved_at { nil }
    resolution_payload { nil }

    trait :resolved do
      resolved_at { Time.current }
      resolution_payload do
        { "title" => { "decision" => "youtube", "value" => "remote title" } }
      end
    end

    trait :auto_closed do
      resolved_at { Time.current }
      resolution_payload { { "auto_closed" => true } }
    end

    trait :multi_field do
      field_diffs do
        {
          "title"       => { "pito" => "local title", "youtube" => "remote title" },
          "description" => { "pito" => "local body",  "youtube" => "remote body" },
          "country"     => { "pito" => "US",          "youtube" => "GB" }
        }
      end
    end
  end
end
