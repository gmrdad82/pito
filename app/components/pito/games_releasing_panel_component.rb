module Pito
  # Pito::GamesReleasingPanelComponent — home-screen panel showing
  # upcoming game releases (sourced via IGDB). Renders a horizontal
  # "shelf" of cover-art tiles with title and a compact "in Nd" countdown.
  #
  # ## Data
  #
  # Reads all games whose `release_date` falls inside the
  # `[today, today + 30 days]` window, ordered by `release_date ASC`.
  # When the window is empty the panel emits a muted hint instead of
  # an empty shelf.
  #
  # ## Focusables
  #
  #   1. `upcoming_<id>` for each tile, in `release_date ASC` order.
  #
  # ## Canonical wiring
  #
  # - Includes `Tui::PanelBase`.
  # - Cable channel: `pito:home:games_releasing`.
  class GamesReleasingPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :games_releasing
    UPCOMING_WINDOW_DAYS = 30

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    # Games releasing within the upcoming window, sorted soonest-first.
    def upcoming_games
      @upcoming_games ||= Game.scheduled
                              .where(release_date: Date.current..(Date.current + UPCOMING_WINDOW_DAYS.days))
                              .order(release_date: :asc)
    end

    def empty?
      upcoming_games.empty?
    end

    def empty_hint
      I18n.t("tui.home.panels.#{PANEL_NAME}.empty")
    end

    # Focusables: one stop per tile (ordered the same way the template
    # renders them so the cursor index matches DOM order).
    def focusables
      upcoming_games.map { |g| "upcoming_#{g.id}" }
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {})
    end
  end
end
