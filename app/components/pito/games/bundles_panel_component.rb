module Pito
  module Games
    # Pito::Games::BundlesPanelComponent — games-screen panel listing the
    # owner's game bundles. Occupies the right 40% of Row 2A in the
    # `/games` screen grid.
    #
    # ## Status
    #
    # Placeholder — renders "[ panel content TBD ]". Content (bundle tiles
    # or a list of bundles with member counts and cover art) will be filled
    # by a dedicated dispatch once the layout shell is locked.
    #
    # ## Kwargs
    #
    # None for the placeholder round.
    #
    # ## Focusables
    #
    # [] — empty for the placeholder round; will expand when content lands.
    #
    # ## Cable channel
    #
    # `pito:games:bundles` — canonical grammar for games-screen panels.
    #
    # ## TUI parity
    #
    # The Ratatui sibling reads `data-panel-name="bundles"` from the
    # section root to derive cable subscription + focusable list.
    class BundlesPanelComponent < ViewComponent::Base
      include Tui::PanelBase

      PANEL_NAME = :bundles

      def title
        I18n.t("tui.games.panels.bundles.title", default: "bundles")
      end

      def focusables
        []
      end

      def panel_data
        panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {}, screen: :games)
      end
    end
  end
end
