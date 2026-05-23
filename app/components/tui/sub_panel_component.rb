module Tui
  # Tui::SubPanelComponent — canonical chrome for a single sub-panel
  # inside a `Pito::*PanelComponent` 2x2 grid (Stack / etc.). Renders
  # the `[data-tui-cursor-target="sub-panel"]` root, the title span on
  # the top border, an optional `actions` slot (chip / reindex action /
  # toggle), and the caller-supplied body content.
  #
  # ## Kwargs
  #
  # @param title [String] sub-panel title rendered in the top border.
  # @param class_name [String, nil] optional extra CSS class on the root.
  # @param focusable_key [String, Symbol, nil] when present, emits
  #   `data-tui-focusable=<key>` + `data-tui-focusable-key=<key>` on the
  #   sub-panel root so the cursor can LAND on it during h/l traversal.
  #   Used by inert / action-less sub-panels (e.g. Postgres, Assets)
  #   that would otherwise be skipped by the flat focusables list
  #   (action-bearing sub-panels — Meilisearch, Voyage — keep emitting
  #   focusables on their own `[reindex]` action instead).
  #   FB-187 (2026-05-23).
  class SubPanelComponent < ViewComponent::Base
    renders_one :actions

    def initialize(title:, class_name: nil, focusable_key: nil)
      @title = title
      @class_name = class_name
      @focusable_key = focusable_key
    end

    attr_reader :title, :focusable_key

    def sub_panel_class
      [ "pito-sub-panel", @class_name ].compact.join(" ")
    end

    def root_data
      data = {
        tui_cursor_target: "sub-panel",
        panel_title: title
      }
      if focusable_key
        data[:tui_focusable] = focusable_key.to_s
        data[:tui_focusable_key] = focusable_key.to_s
      end
      data
    end
  end
end
