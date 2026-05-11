# Phase 27 §01b — Filter row.
#
# 2026-05-11 polish — the chip cluster is laid out across TWO rows
# (split via a fixed boundary index). Display-mode switcher rides the
# far right of the SECOND row's right slot.
#
#   Row 1 (status + platform): released scheduled ps5 switch2 steam gog epic xbox
#   Row 2 (ownership/recorded): owned not_owned recorded   ...  [default][grid][list]
#
# Per-platform chip labels are cased canonically (`PS5`, `Switch2`,
# `Steam`, `GoG`, `Epic`, `Xbox`); URL tokens stay lowercase.
#
# Plus a `[clear all]` bracketed link to the right of the first row
# when at least one chip is active. A muted contradiction notice
# (`(owned and not owned together — no matches)`) renders immediately
# under the row when `contradiction == true`.
#
# The component emits NO JavaScript — chip toggling is pure GET-link
# navigation. Active chips carry the `chip--active` modifier; the
# contradiction notice carries `text-muted` (no red).
module Games
  class FilterRowComponent < ViewComponent::Base
    include Games::FiltersHelper

    # 2026-05-11 polish — optional right-aligned slot on the SECOND
    # row. The `/games` index passes the display-mode switcher here so
    # it renders flush-right on row 2.
    renders_one :right_slot

    # 2026-05-11 polish — chips partition into two rows. The boundary
    # is fixed: row 1 carries status (released, scheduled) + every
    # platform token; row 2 carries ownership (owned, not_owned) +
    # `recorded`. The cosmetic split keeps the visual scan compact
    # without changing token semantics — the underlying query reads
    # the same `?filters=` CSV regardless of row.
    ROW_1_TOKENS = %w[released scheduled ps5 switch2 steam gog epic xbox].freeze
    ROW_2_TOKENS = %w[owned not_owned recorded].freeze
    CHIP_ORDER = (ROW_1_TOKENS + ROW_2_TOKENS).freeze

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

    def row_1_tokens
      ROW_1_TOKENS
    end

    def row_2_tokens
      ROW_2_TOKENS
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
