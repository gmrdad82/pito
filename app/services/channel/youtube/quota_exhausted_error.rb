# Raised when the daily quota budget would be
# exceeded by a pending call (pre-call refusal) OR Google returned
# a `quotaExceeded` / `dailyLimitExceeded` 403. Fail-fast — no
# retry / backoff / queueing (locked decision).
class Channel
  module Youtube
    class QuotaExhaustedError < Error; end
  end
end
