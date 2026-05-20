module Tui
  # Beta 4 — Phase F2. TUI inline chip primitive. Renders a label
  # wrapped in literal `[ ]` brackets (the pito-wide bracketed-link
  # convention; this is the inline tag flavor, not the actionable link
  # flavor). Variants drive color only — the bracket grammar is fixed.
  #
  # ADR 0016 (TUI design system) locks the 6 variants:
  #
  #   :neutral  -> `[ip]`, `[id]`, generic muted tag
  #   :info     -> `[connected]`, info-state markers (Dracula cyan)
  #   :success  -> `[active]`, `[ok]` (Dracula green)
  #   :warn     -> `[stale]`, `[deprecated]` (Dracula orange)
  #   :danger   -> `[revoked]`, `[failed]` (Dracula pink / danger token)
  #   :current  -> `[this]` for current-session marker (text fg +
  #                section-accent 12% bg tint; subtle inverse)
  #
  # The chip is a pure presentational primitive — no events, no state,
  # no JS. Consumers compose it inside table cells, list rows,
  # status-bar segments, etc. Reused across /settings sessions,
  # /channels OAuth status, future tag surfaces.
  class ChipComponent < ViewComponent::Base
    VARIANTS = %i[neutral info success warn danger current].freeze

    def initialize(label:, variant: :neutral)
      @label = label.to_s
      @variant = variant.to_sym
      raise ArgumentError, "unknown variant #{variant}" unless VARIANTS.include?(@variant)
    end

    attr_reader :label, :variant

    def css_class
      "tui-chip tui-chip--#{variant}"
    end
  end
end
