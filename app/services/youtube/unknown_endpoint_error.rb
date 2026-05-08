# Phase 7 — Step B. Raised by `Youtube::Quota.cost_for(endpoint)`
# for an endpoint that is not in the cost map. Programming error,
# not runtime condition.
module Youtube
  class UnknownEndpointError < Error; end
end
