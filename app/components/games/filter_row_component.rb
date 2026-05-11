# Phase 27 §01b — Filter row.
#
# Renders ten canonical chips in the locked left-to-right order:
#
#   recorded released owned not_owned scheduled ps5 switch2 steam gog epic
#
# Plus a `[clear all]` bracketed link to the right when at least one
# chip is active. A muted contradiction notice
# (`(owned and not owned together — no matches)`) renders immediately
# under the row when `contradiction == true`.
#
# The component emits NO JavaScript — chip toggling is pure GET-link
# navigation. Active chips carry the `chip--active` modifier; the
# contradiction notice carries `text-muted` (no red).
module Games
  class FilterRowComponent < ViewComponent::Base
    include Games::FiltersHelper

    # Locked left-to-right chip order from spec §"Goal".
    CHIP_ORDER = %w[
      recorded released owned not_owned scheduled
      ps5 switch2 steam gog epic
    ].freeze

    def initialize(active_tokens:, request_path:, dropped_tokens: [], query_string_overrides: {}, contradiction: false)
      @active_tokens          = Array(active_tokens)
      @dropped_tokens         = Array(dropped_tokens)
      @request_path           = request_path
      @query_string_overrides = (query_string_overrides || {}).to_h
      @contradiction          = contradiction ? true : false
    end

    attr_reader :active_tokens, :dropped_tokens, :request_path, :query_string_overrides

    def contradiction?
      @contradiction
    end

    def chip_tokens
      CHIP_ORDER
    end

    def chip_for(token)
      Games::FilterChipComponent.new(
        token:                  token,
        active:                 active_tokens.include?(token),
        request_path:           request_path,
        active_tokens:          active_tokens,
        query_string_overrides: query_string_overrides
      )
    end

    def any_active?
      active_tokens.any?
    end

    # The `[clear all]` href clears `filters=` and preserves the
    # query-string overrides verbatim (display=, genre=, collection=).
    def clear_all_href
      query = query_string_overrides.to_query
      query.empty? ? request_path : "#{request_path}?#{query}"
    end

    def dev_warning?
      Rails.env.development? && dropped_tokens.any?
    end
  end
end
