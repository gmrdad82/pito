FactoryBot.define do
  factory :oauth_application do
    sequence(:name) { |n| "test-app-#{n}" }
    redirect_uri { "http://127.0.0.1:8765/callback" }
    scopes { Scopes::DEV_READ }
    confidential { false }
  end
end
