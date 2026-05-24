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
  #
  # ## Top-border chrome contract (panel-level) — LOCKED
  #
  # Every `.pito-pane` panel is a rounded box (`border-radius: 10px`) with
  # a 1px solid border in `var(--color-border)`. The title + optional
  # action slots pierce the top border via a "notch" technique. The rules
  # below are locked and must not be reimplemented via pseudo-elements.
  #
  # ### Title slot
  #
  # The `<legend>` (or `.pito-pane__title` element) is positioned at:
  #
  #   top: -7px; left: 8px; height: 14px;
  #   border-left:  1px solid var(--color-border);
  #   border-right: 1px solid var(--color-border);
  #   padding: 0 6px;
  #   background: var(--section-bg, var(--color-bg));
  #
  # The background cuts through the panel's horizontal top border so the
  # page's section-tinted `--section-bg` colour shows instead of the
  # panel's border. The two `border-left` / `border-right` CSS properties
  # on the slot element ITSELF are the visible "pipe brackets" `│…│`.
  #
  # ### Action slot
  #
  # The top-right action slot (e.g. `[reindex]`, `month [schedule]`) uses
  # class `.pito-pane__title-actions`. Same chrome geometry as the title
  # slot: real `border-left` + `border-right` + `padding: 0 6px` +
  # `background: var(--section-bg, var(--color-bg))`.
  #
  # ### Border radius
  #
  # `border-radius: 10px` on `.pito-pane`, `.pito-sub-panel`, and
  # `.tui-dialog-frame`. Locked — do not change.
  #
  # ### Pipe contract — strict
  #
  # NEVER use `::before` / `::after` with `content: "│"` or
  # `content: ""` + background to render the pipe brackets. The pipes
  # are CSS `border-left` / `border-right` on the slot element itself.
  # Pseudo-element approaches were rejected in three separate polish
  # rounds and must not be reintroduced.
  #
  # ### Scroll indicator chrome
  #
  # All three glyphs (▲ ▼ █) are positioned at `right: -14px` — outside
  # the panel's right border. Color is `var(--section-accent)`. Background
  # is transparent. The █ handle position is pixel-computed in JS by
  # `tui_scroll_indicator_controller` with 20 px reserved zones at the
  # top and bottom so █ never overlaps ▲ or ▼.
  #
  # ### TUI parity
  #
  # The title + action slot pattern maps to Ratatui's
  # `Block::default().title("…").borders(Borders::ALL)` idiom. The
  # horizontal top border meets the vertical title-slot edges at the
  # corners — identical to how CSS `border-left` / `border-right` on the
  # slot element meets the panel's CSS `border-top` at the slot's
  # bounding-box corners.
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
