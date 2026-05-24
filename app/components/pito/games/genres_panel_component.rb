module Pito
  module Games
    # Pito::Games::GenresPanelComponent — games-screen panel showing the
    # owner's library grouped by genre. Occupies the left 60% of Row 2A
    # in the `/games` screen grid.
    #
    # ## Status
    #
    # Placeholder — renders "[ panel content TBD ]". Content (genre tiles
    # or a sortable table of genres with game counts) will be filled by a
    # dedicated dispatch once the layout shell is locked.
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
    # `pito:games:genres` — canonical grammar for games-screen panels.
    #
    # ## TUI parity
    #
    # The Ratatui sibling reads `data-panel-name="genres"` from the
    # section root to derive cable subscription + focusable list.
    class GenresPanelComponent < ViewComponent::Base
      include Tui::PanelBase

      PANEL_NAME = :genres

      def title
        I18n.t("tui.games.panels.genres.title", default: "genres")
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
