# Phase 7 — Step B. Raised by `Youtube::PublicClient` when it has
# no API key configured and a method is invoked anyway.
module Youtube
  class NotConfiguredError < Error; end
end
