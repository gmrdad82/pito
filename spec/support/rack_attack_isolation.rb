# Phase 3 — Step B (5b-token-and-auth-concern.md). The rack-attack
# initializer points `Rack::Attack.cache.store` at a shared MemoryStore
# in the test environment. Without isolation, failed-auth counters from
# one spec leak into the next, causing 429s where 401s are expected.
#
# Reset the throttle store before every example so each example starts
# with a clean bucket.
RSpec.configure do |config|
  config.before(:each) do
    Rack::Attack.cache.store.clear if defined?(Rack::Attack)
  end
end
