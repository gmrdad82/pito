# frozen_string_literal: true

FactoryBot.define do
  factory :youtube_connection do
    sequence(:google_subject_id) { |n| "google_sub_#{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    access_token { "ya29.test-token" }
    refresh_token { "1//test-refresh" }
    scopes { %w[https://www.googleapis.com/auth/youtube.readonly] }
    expires_at { 1.hour.from_now }
    last_authorized_at { Time.current }
    needs_reauth { false }

    trait :needs_reauth do
      needs_reauth { true }
    end

    trait :with_channels do
      after(:create) do |connection|
        create_list(:channel, 2, youtube_connection: connection)
      end
    end
  end
end
