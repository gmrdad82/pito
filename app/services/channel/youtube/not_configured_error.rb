# Phase 7 — Step B. Raised by `Channel::Youtube::PublicClient` when it has
# no API key configured and a method is invoked anyway.
class Channel
  module Youtube
    class NotConfiguredError < Error; end
  end
end
