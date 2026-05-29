# Pito auth operator tasks — TOTP enrollment, reset, and backup-code rotation.
#
# These tasks target the singleton-owner model: AppSetting holds the TOTP seed;
# TotpBackupCode rows are standalone (no user_id). All three tasks are
# operator-only shell surfaces; no web equivalent exists.
#
# Usage:
#   bin/rails pito:auth:enroll                          # first-time enroll
#   bin/rails pito:auth:enroll FORCE=yes                # rotate existing enrollment
#   bin/rails pito:auth:reset                           # wipe seed + codes
#   bin/rails pito:auth:backup_codes:regenerate         # rotate codes only
namespace :pito do
  namespace :auth do
    desc "Enroll the singleton owner with a fresh TOTP seed + 10 backup codes. FORCE=yes to rotate existing enrollment."
    task enroll: :environment do
      if AppSetting.totp_enabled? && ENV["FORCE"] != "yes"
        warn "Already enrolled. Re-run with FORCE=yes to rotate the seed + codes."
        exit 1
      end

      # Generate seed
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)

      # Generate 10 backup codes
      TotpBackupCode.delete_all
      plain_codes = 10.times.map { SecureRandom.alphanumeric(8).downcase }
      plain_codes.each do |code|
        TotpBackupCode.create!(code_digest: BCrypt::Password.create(code))
      end

      # Build otpauth URI
      issuer  = "pito"
      account = "owner"
      otpauth_uri = ROTP::TOTP.new(seed, issuer: issuer).provisioning_uri(account)

      puts "TOTP enrolled."
      puts ""
      puts "Paste this into your authenticator app (manual entry, or as URI):"
      puts "  #{otpauth_uri}"
      puts ""
      puts "Or enter the raw secret manually:"
      puts "  #{seed}"
      puts ""
      puts "Backup codes (single-use; store in a password manager):"
      plain_codes.each_with_index { |c, i| puts "  #{i + 1}. #{c}" }
      puts ""
      puts "Done. Hit / in your browser; the TOTP dialog will accept a 6-digit code."
    end

    desc "Reset TOTP enrollment — drops seed + all backup codes."
    task reset: :environment do
      AppSetting.disable_totp!
      TotpBackupCode.delete_all
      puts "TOTP reset. Run pito:auth:enroll to enroll a new device."
    end

    namespace :backup_codes do
      desc "Regenerate 10 new backup codes (drops existing). Requires TOTP already enrolled."
      task regenerate: :environment do
        unless AppSetting.totp_enabled?
          warn "TOTP not enrolled — run pito:auth:enroll first."
          exit 1
        end

        TotpBackupCode.delete_all
        plain_codes = 10.times.map { SecureRandom.alphanumeric(8).downcase }
        plain_codes.each do |code|
          TotpBackupCode.create!(code_digest: BCrypt::Password.create(code))
        end

        puts "10 new backup codes (single-use):"
        plain_codes.each_with_index { |c, i| puts "  #{i + 1}. #{c}" }
      end
    end
  end
end
