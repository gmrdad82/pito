module Tui
  # Beta 4 — Phase F2. TUI inline chip primitive. V2 (locked 2026-05-20):
  # a single colored `<span>`, no brackets, no background, no border —
  # just colored text. Variants drive color only.
  #
  # ADR 0016 (TUI design system) locks the 6 variants:
  #
  #   :neutral  -> `ip`, `id`, generic muted tag
  #   :info     -> `connected`, info-state markers (Dracula cyan)
  #   :success  -> `active`, `ok` (Dracula green)
  #   :warn     -> `missing`, `stale`, `deprecated` (Dracula orange —
  #                also the canonical "missing/unhealthy" color)
  #   :danger   -> `revoked`, `failed` (Dracula pink / danger token)
  #   :current  -> `this` for current-session marker (text fg +
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
