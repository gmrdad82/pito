module Pito
  module Games
    # Pito::Games::TableSubPanelComponent — games-screen sub-panel
    # rendering the full library as a sortable table. Full width of Row
    # 2B in the `/games` screen grid (below the genres + bundles split).
    #
    # ## Status
    #
    # Placeholder — renders "[ panel content TBD ]". Content (sortable
    # table of all games with title, genre, platform, rating, played-at,
    # and hours-of-footage columns) will be filled by a dedicated dispatch
    # once the layout shell is locked.
    #
    # ## Kwargs
    #
    # None for the placeholder round.
    #
    # ## Focusables
    #
    # [] — empty for the placeholder round; will expand to one `:row`
    # focusable per game row when content lands.
    #
    # ## Cable channel
    #
    # `pito:games:games_table` — canonical grammar for games-screen
    # sub-panels. Sub-panel name follows the
    # `pito:<screen>:<panel>:<sub_panel>` grammar from architecture.md
    # but omits the parent panel prefix since the table is its own
    # scrollable surface.
    #
    # ## TUI parity
    #
    # The Ratatui sibling reads `data-panel-name="games_table"` from the
    # section root to derive cable subscription + focusable list.
    class TableSubPanelComponent < ViewComponent::Base
      include Tui::PanelBase

      PANEL_NAME = :games_table

      def title
        I18n.t("tui.games.panels.games_table.title", default: "library")
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
