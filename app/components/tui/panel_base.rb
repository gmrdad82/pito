module Tui
  # Tui::PanelBase — mixin for Pito::*PanelComponent VCs. Provides the
  # canonical data-attr Hash for the panel root, including:
  #
  #   - tui-panel-cable controller wiring (Pito::PanelChannel subscription)
  #   - tui-cursor panel target registration
  #   - panel name + focusables list + keybinds map for downstream Stimulus
  #
  # Each VC includes this and uses `panel_root_data` in its template:
  #
  #   class Pito::SecurityPanelComponent < ViewComponent::Base
  #     include Tui::PanelBase
  #
  #     def focusables
  #       %w[sessions_table revoke_all_action]
  #     end
  #
  #     def keybinds
  #       { "r" => "bulk_revoke" }
  #     end
  #   end
  #
  #   <%= content_tag :section, class: "pito-panel",
  #         **panel_root_data(name: :security, focusables: focusables, keybinds: keybinds) do %>
  #     <!-- ... panel body ... -->
  #   <% end %>
  #
  # The `screen:` keyword defaults to "home" since this round only wires
  # home panels; videos/games panels pass their own screen.
  #
  # Mixin lives at `app/components/tui/panel_base.rb` matching
  # `Tui::Transitionable` zeitwerk-clean placement (no app/components/concerns/).
  #
  # @contract see docs/architecture.md § Cable channel grammar
  module PanelBase
    DEFAULT_SCREEN = "home".freeze

    # Channel-name builder for backend broadcasters or component-internal
    # references. Returns the canonical `pito:<screen>:<panel>` string.
    #
    # @param name [Symbol, String] panel name
    # @param screen [String, Symbol] screen name (default "home")
    # @return [String] cable channel name
    def cable_channel_for(name, screen: DEFAULT_SCREEN)
      "pito:#{screen}:#{name}"
    end

    # Build the data-attrs Hash for the panel root content_tag. Spread with
    # the `**` operator so the resulting `data:` Hash is merged with any
    # additional caller-provided data attributes.
    #
    # @param name [Symbol, String] panel name (must match Pito::PanelChannel::ALLOWED_PANELS)
    # @param focusables [Array<String, Symbol>] ordered focusable keys for tui_cursor
    # @param keybinds [Hash] panel-scoped keybinds (e.g. { "r" => "bulk_revoke" })
    # @param screen [String, Symbol] screen name (default "home")
    # @param title [String, nil] panel title displayed in the breadcrumb when
    #   this panel is focused; when nil the mixin introspects the including
    #   VC's `#title` method (every Pito::*PanelComponent defines one).
    # @return [Hash{Symbol => Hash}] `{ data: { ... } }` spread into content_tag
    def panel_root_data(name:, focusables: [], keybinds: {}, screen: DEFAULT_SCREEN, title: nil)
      # The cursor controller reads `dataset.panelTitle` (`data-panel-title`)
      # in `emitFocusChange()` to populate the `tui:panel-focus-changed` event
      # detail. The breadcrumb VC listens for that event and renders the
      # focused panel's title. Introspect via the including VC's `#title`
      # when no explicit kwarg is passed.
      resolved_title = title || (respond_to?(:title, true) ? send(:title) : nil)
      data = {
        controller: "tui-panel-cable",
        tui_panel_cable_screen_value: screen.to_s,
        tui_panel_cable_name_value: name.to_s,
        tui_cursor_target: "panel",
        tui_panel_name_value: name.to_s,
        tui_panel_focusables_value: focusables.map(&:to_s).join(","),
        tui_panel_keybinds_value: keybinds.to_json
      }
      data[:panel_title] = resolved_title.to_s if resolved_title
      { data: data }
    end
  end
end
