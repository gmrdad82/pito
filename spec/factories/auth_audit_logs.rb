FactoryBot.define do
  factory :auth_audit_log do
    acting_user { User.first || create(:user) }
    source_surface { :web }
    # Post-Phase-25 rollback. The location-tied vocabulary (approve /
    # block / unblock / purge) is gone; default to a still-active
    # action targeting the canonical `User` row.
    action { :totp_enroll }
    target_type { "User" }
    sequence(:target_id) { |n| n }
    metadata { {} }
  end
end
