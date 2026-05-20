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
  class PanelFieldsetComponent < ViewComponent::Base
    def initialize(class_name: nil, data: nil)
      @class_name = class_name
      @data = data
    end

    def fieldset_class
      [ "tui-panel-fieldset", @class_name ].compact.join(" ")
    end

    def data_attrs
      @data || {}
    end
  end
end
