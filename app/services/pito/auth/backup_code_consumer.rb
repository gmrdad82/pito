# Z2a (2026-05-25). Consumes a TOTP backup code.
#
# Post-Z1: there is no User model. Backup codes are standalone
# `TotpBackupCode` rows with no `user_id` foreign key. The consumer
# scans unused rows, BCrypt-compares the plaintext, and stamps
# `used_at` on the first match under a pessimistic row lock.
#
# Returns :ok / :invalid / :already_used.
#
# Concurrency: a pessimistic row lock prevents two parallel consumes
# of the same plaintext from both succeeding.
module Pito
  module Auth
    class BackupCodeConsumer
      # @param code [String] 8-char backup code from the login form.
      # @return [:ok, :invalid, :already_used]
      def self.call(code:)
        normalized = code.to_s.strip
        return :invalid if normalized.blank?

        # Exact-length gate before any BCrypt work.
        return :invalid unless normalized.length == Pito::Auth::TotpEnroller::BACKUP_CODE_LENGTH

        # Safe-alphabet gate: any code outside the alphabet cannot match.
        return :invalid unless normalized.each_char.all? { |c| Pito::Auth::TotpEnroller::BACKUP_CODE_ALPHABET.include?(c) }

        candidate = nil

        TotpBackupCode.unused.find_each do |row|
          next unless row.matches?(normalized)

          candidate = row
          break
        end

        return :invalid if candidate.nil?

        consumed = false

        ActiveRecord::Base.transaction do
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
end
