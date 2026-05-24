class Tui::ScrollIndicatorComponent < ViewComponent::Base
  # Tui::ScrollIndicatorComponent — overlay glyphs that appear at the
  # leading + trailing edges of a scrollable container when content
  # overflows in that axis, plus a thumb glyph showing scroll position.
  #
  # ## Axes
  #
  #   - `:vertical` (default) — ▲ / ▼ + █ on the right border.
  #     Targets emitted: `top`, `bottom`, `handle`.
  #
  #   - `:horizontal` — ◀ / ▶ + ▬ on the bottom border. Targets:
  #     `left`, `right`, `handle`. The same `tui-scroll-indicator`
  #     Stimulus controller handles both axes; the wrapping container
  #     selects the axis via `data-tui-scroll-indicator-axis-value`
  #     (the canonical `Tui::PanelFieldsetComponent` handles this
  #     wiring automatically).
  #
  # Usage:
  #   <div class="scrollable-host"
  #        data-controller="tui-scroll-indicator"
  #        data-tui-scroll-indicator-axis-value="vertical">
  #     <%= render Tui::ScrollIndicatorComponent.new %>
  #     <div class="scrollable-content">…</div>
  #   </div>
  #
  # The scrollable host should have `position: relative` (or absolute)
  # and `overflow-y: auto` / `overflow-x: auto` (hidden scrollbars per
  # project convention). The tui-scroll-indicator Stimulus controller
  # mounts on the host, listens for scroll events, and toggles
  # `is-visible` on the matching axis's children.
  #
  # ## TUI parity
  #
  # The Ratatui sibling renders the same Unicode glyphs (▲ ▼ █ for
  # vertical; ◀ ▶ ▬ for horizontal) on the appropriate panel border
  # row / column. The glyph alphabet is intentionally identical so
  # the web + TUI surfaces read as one design.
  AXES = %i[vertical horizontal].freeze

  def initialize(axis: :vertical)
    @axis = axis.to_sym
    unless AXES.include?(@axis)
      raise ArgumentError,
            "Unknown axis #{axis.inspect} (expected one of #{AXES.inspect})"
    end
  end

  attr_reader :axis

  def vertical?
    @axis == :vertical
  end

  def horizontal?
    @axis == :horizontal
  end
end
