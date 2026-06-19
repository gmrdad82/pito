# Raised when a 5xx, 429, or network error survived all retries.
# Callers may queue-and-try-tomorrow.
class Channel
  module Youtube
    class TransientError < Error; end
  end
end
