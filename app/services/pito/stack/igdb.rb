# frozen_string_literal: true

module Pito
  module Stack
    # IGDB API request usage (24h + current month).
    module Igdb
      PROVIDER = "igdb"
      extend ProviderCounts
    end
  end
end
