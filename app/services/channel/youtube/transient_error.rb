# Phase 7 — Step B. Raised when a 5xx, 429, or network error
# survived all retries. Callers may queue-and-try-tomorrow;
# Phase 8 owns that policy.
class Channel
  module Youtube
    class TransientError < Error; end
  end
end
