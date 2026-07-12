# frozen_string_literal: true

require "countries"

module Pito
  # Tiny geo helper over the `countries` gem (ISO 3166-1). Turns the alpha-2
  # country codes the YouTube Analytics API returns (e.g. "US") into friendly
  # display names ("United States") for the geography bar chart, falling back to
  # the iso short name and then the upcased code for anything unrecognised.
  module Geo
    module_function

    # @param code [String] ISO 3166-1 alpha-2 country code (case-insensitive)
    # @return [String] a display name, or the upcased code if unknown
    def country_name(code)
      code    = code.to_s.upcase
      country = ISO3166::Country[code]
      country&.common_name || country&.iso_short_name || code
    end
  end
end
