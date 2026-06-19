# Raised when the response cannot be retried:
# 4xx (not 401/403 quota), client-supplied bad-request shapes, etc.
class Channel
  module Youtube
    class PermanentError < Error; end
  end
end
