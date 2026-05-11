# Phase 27 §01b — Filter row chip.
#
# Renders a single bracketed link `[label]` whose href toggles `token`
# in or out of the comma-separated `?filters=` URL param. Active chips
# carry the `chip--active` modifier (no red — red is reserved for
# destructive actions). The component emits a single `<a>` element;
# no buttons, no forms, no JS.
#
# On-screen label boundary: `not_owned` → `not owned` (space); all
# other canonical tokens render verbatim.
module Games
  class FilterChipComponent < ViewComponent::Base
    include Games::FiltersHelper

    def initialize(token:, active:, request_path:, active_tokens:, query_string_overrides: {})
      unless Games::Filter::CANONICAL_TOKENS.include?(token)
        raise ArgumentError, "FilterChipComponent token must be canonical: got #{token.inspect}"
      end
      raise ArgumentError, "FilterChipComponent request_path must be present" if request_path.to_s.empty?

      @token                  = token
      @active                 = active
      @request_path           = request_path
      @active_tokens          = Array(active_tokens)
      @query_string_overrides = (query_string_overrides || {}).to_h
    end

    attr_reader :token, :request_path, :active_tokens, :query_string_overrides

    def active?
      @active ? true : false
    end

    def label
      chip_label(token)
    end

    # Builds the chip href. If the toggled-into set is empty, `filters`
    # is omitted entirely (no trailing `?filters=` dangle).
    def href
      next_tokens = toggle_filter(active_tokens, token)
      params = query_string_overrides.dup
      params[:filters] = next_tokens.join(",") if next_tokens.any?
      query = params.to_query
      query.empty? ? request_path : "#{request_path}?#{query}"
    end

    def css_classes
      classes = [ "bracketed", "filter-chip" ]
      classes << "chip--active" if active?
      classes.join(" ")
    end
  end
end
