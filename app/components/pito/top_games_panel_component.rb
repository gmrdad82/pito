module Pito
  # Pito::TopGamesPanelComponent — games-screen panel showing top-rated
  # or most-played games from the owner's library. Right 60% of Row 1
  # on the `/games` screen grid.
  #
  # ## Status
  #
  # Placeholder — renders "[ panel content TBD ]". Content will be
  # filled by a dedicated dispatch once the layout shell is locked.
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
  # `pito:games:top_games` — canonical grammar for games-screen panels.
  #
  # ## TUI parity
  #
  # The Ratatui sibling reads `data-panel-name="top_games"` from the
  # section root to derive cable subscription + focusable list.
  class TopGamesPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :top_games

    def title
      I18n.t("tui.games.panels.top_games.title", default: "top games")
    end

    def focusables
      []
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {}, screen: :games)
    end
  end
end
