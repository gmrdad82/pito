FactoryBot.define do
  factory :auth_audit_log do
    acting_user { User.first || create(:user) }
    source_surface { :web }
    action { :approve }
    target_type { "LoginAttempt" }
    sequence(:target_id) { |n| n }
    metadata { {} }
  end
end
