FactoryBot.define do
  factory :google_identity do
    user { Current.user || association(:user) }

    sequence(:google_subject_id) { |n| "1099#{n.to_s.rjust(15, '0')}" }
    sequence(:email) { |n| "google-user-#{n}@example.test" }

    access_token { "ya29.test-access-token-#{SecureRandom.hex(8)}" }
    refresh_token { "1//test-refresh-token-#{SecureRandom.hex(16)}" }
    expires_at { 1.hour.from_now }
    scopes do
      %w[
        openid
        email
        profile
        https://www.googleapis.com/auth/youtube.readonly
        https://www.googleapis.com/auth/yt-analytics.readonly
      ]
    end
    needs_reauth { false }
    last_authorized_at { Time.current }

    trait :expired do
      expires_at { 5.minutes.ago }
    end

    trait :needs_reauth do
      needs_reauth { true }
    end

    trait :no_refresh_token do
      refresh_token { nil }
    end
  end
end
