FactoryBot.define do
  factory :youtube_api_call do
    user { nil }
    youtube_connection { nil }
    client_kind { "oauth" }
    endpoint { "channels.list" }
    http_method { "GET" }
    units { 1 }
    outcome { "success" }
    http_status { 200 }
    error_message { nil }
    duration_ms { 42 }
    created_at { Time.current }

    trait :public do
      client_kind { "public" }
      youtube_connection { nil }
    end

    trait :quota_exceeded do
      outcome { "quota_exceeded" }
      http_status { nil }
    end

    trait :auth_failed do
      outcome { "auth_failed" }
      http_status { 401 }
    end
  end
end
