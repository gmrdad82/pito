module Tui
  # Tui::PanelFieldsetComponent — wraps panel body content in a chromeless
  # `<fieldset>` shell with vertical-only padding. Replaces the inline
  # `<fieldset style="padding: 8px; border: none;">` spaghetti that the
  # settings panes (notifications / security / stack) previously carried.
  #
  # The vertical-only padding (`8px 0`) is locked by user feedback (FB-78
  # / FB-105 — drop L/R padding from the fieldset shell so the panel's
  # outer border governs horizontal inset). The `tui-panel-fieldset`
  # class lives in `app/assets/tailwind/application.css`.
  #
  # Optional `class_name:` appends extra classes to the fieldset.
  # Optional `data:` hash carries Stimulus / data-* attributes (e.g., the
  # security pane needs `data-controller="sessions-bulk-revoke"`).
  #
  # FB-SCROLL-INDICATOR (2026-05-23) — every panel fieldset auto-mounts
  # the `tui-scroll-indicator` Stimulus controller and yields the
  # `Tui::ScrollIndicatorComponent` ▲/▼ glyphs from the template. The
  # fieldset itself owns `position: relative` + `overflow-y: auto` (via
  # `.tui-panel-fieldset` in application.css), so the absolutely-positioned
  # indicator glyphs anchor to the right edge of the scrollable surface.
  # Any caller-supplied `data: { controller: "..." }` is MERGED with
  # `tui-scroll-indicator` rather than overwritten — multiple controllers
  # ride the fieldset side-by-side (e.g., the security panel's
  # `sessions-bulk-revoke` + `tui-scroll-indicator`).
  class PanelFieldsetComponent < ViewComponent::Base
    SCROLL_INDICATOR_CONTROLLER = "tui-scroll-indicator".freeze

    def initialize(class_name: nil, data: nil)
      @class_name = class_name
      @data = data
    end

    def fieldset_class
      [ "tui-panel-fieldset", @class_name ].compact.join(" ")
    end

    # Merge the caller-supplied `data:` hash with the auto-mount
    # `tui-scroll-indicator` controller. Stimulus `data-controller`
    # accepts a space-separated list — appending preserves any caller
    # controllers (string or symbol keys both honored).
    def data_attrs
      base = (@data || {}).dup
      key = base.key?("controller") ? "controller" : :controller
      existing = base[key].to_s.strip
      base[key] = existing.empty? ? SCROLL_INDICATOR_CONTROLLER : "#{existing} #{SCROLL_INDICATOR_CONTROLLER}"
      base
    end
  end
end
