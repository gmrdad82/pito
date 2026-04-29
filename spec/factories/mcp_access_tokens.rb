FactoryBot.define do
  factory :mcp_access_token do
    sequence(:name) { |n| "token-#{n}" }
    token_digest { McpAccessToken.digest(SecureRandom.urlsafe_base64(32)) }
    last_token_preview { "abcd" }
  end
end
