# Pito TOTP enrollment — operator tool.
#
# Usage:
#   bin/rails pito:totp   # enroll (or re-enroll) with a fresh seed
#   bin/boot --totp       # shortcut: starts Postgres if needed, then enrolls
namespace :pito do
  desc "Enroll the singleton owner with a fresh TOTP seed (overwrites existing)."
  task totp: :environment do
    seed       = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    otpauth_uri = ROTP::TOTP.new(seed, issuer: "pito").provisioning_uri("owner")
    puts I18n.t("pito.auth.enroll.success", otpauth_uri: otpauth_uri, seed: seed)
  end
end
