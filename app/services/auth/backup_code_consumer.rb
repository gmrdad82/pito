# Phase 25 — 01e. Consumes a TOTP backup code.
#
# The login-flow controller calls this AFTER `Auth::TotpVerifier`
# returns `:invalid` — backup codes are the fallback path when the
# user does not have access to their authenticator app. Each code is
# single-use: the row stays for audit, but `used_at` flips on the
# first successful consume and a second consume returns `:already_used`.
#
# Concurrency: a pessimistic row lock prevents two parallel consumes
# of the same plaintext from both succeeding. The lock is held only
# for the duration of the BCrypt compare + stamp, which is fast.
#
# Returns one of `:ok` / `:invalid` / `:already_used`.
module Auth
  class BackupCodeConsumer
    def self.call(user:, code:)
      raise ArgumentError, "user required" if user.nil?

      normalized = code.to_s.strip
      return :invalid if normalized.blank?
      return :invalid if normalized.length < 4

      # First pass: locate any row (used or unused) matching the
      # plaintext. We do the BCrypt compare outside the lock to keep
      # the lock window tight — 10 BCrypt compares at human login rate
      # is cheap.
      candidate = nil
      candidate_already_used = false

      user.totp_backup_codes.find_each do |row|
        next unless row.matches?(normalized)

        candidate = row
        candidate_already_used = row.used?
        break
      end

      return :invalid if candidate.nil?
      return :already_used if candidate_already_used

      consumed = false

      ActiveRecord::Base.transaction do
        # Re-fetch with a row-level lock so a parallel consume
        # cannot stamp `used_at` between our load and our update.
        locked = TotpBackupCode.lock.find(candidate.id)
        if locked.used_at.nil?
          locked.update!(used_at: Time.current)
          consumed = true
        end
      end

      consumed ? :ok : :already_used
    end
  end
end
