# Raised by `Channel::Youtube::Quota.cost_for(endpoint)`
# for an endpoint that is not in the cost map. Programming error,
# not runtime condition.
class Channel
  module Youtube
    class UnknownEndpointError < Error; end
  end
end
