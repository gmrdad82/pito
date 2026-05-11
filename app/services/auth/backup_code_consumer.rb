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

      # P25 follow-up — F4. Tighten the length gate from `< 4` to
      # exact-equal `BACKUP_CODE_LENGTH` (8). Backup codes are minted at
      # a single, fixed length; any other length is by construction not
      # one of ours and must short-circuit before the BCrypt compare.
      return :invalid unless normalized.length == Auth::TotpEnroller::BACKUP_CODE_LENGTH

      # P25 follow-up — F4. Reject any character outside the safe
      # alphabet (`A-Z` + `2-9` minus the visually-confusable
      # `O / I / L / B / 8`). A code containing, e.g., a `0` or a `?`
      # cannot match any digest, so we save the BCrypt round-trip and
      # remove that round-trip as a timing-oracle leg.
      return :invalid unless normalized.each_char.all? { |c| Auth::TotpEnroller::BACKUP_CODE_ALPHABET.include?(c) }

      # First pass: locate an UNUSED row matching the plaintext.
      # P25 follow-up — F4. Iterate only `.unused` rows: a used row can
      # never re-validate (the `consumed` transaction below re-checks
      # `used_at` under a row lock anyway), and skipping used rows here
      # removes wasted BCrypt CPU plus eliminates a timing-oracle leg
      # where a "wrong plaintext" path and a "used plaintext" path
      # differ in observable BCrypt invocations.
      candidate = nil

      user.totp_backup_codes.unused.find_each do |row|
        next unless row.matches?(normalized)

        candidate = row
        break
      end

      return :invalid if candidate.nil?

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
