module Pito
  # Pito::GamesReleasingPanelComponent — home-screen panel showing
  # upcoming game releases (sourced via IGDB) for games the owner
  # currently owns. Renders a horizontal "shelf" of cover-art tiles
  # with title, platform chips, and a compact "in Nd" countdown.
  #
  # ## Round status
  #
  # 2026-05-25 content round — replaces the prior `[ panel content TBD ]`
  # placeholder with a horizontal shelf of `Pito::GamesReleasing::
  # ShelfTileComponent` tiles. j/k keyboard navigation traverses the
  # shelf left-to-right (focusables in DOM order; flex-row layout
  # preserves left-to-right document order). A bottom-edge scroll
  # indicator (`◀ ▶ ▬`) sits on the panel's bottom border, mirroring
  # the right-edge `▲ ▼ █` vertical indicator used by every other
  # panel.
  #
  # ## Data
  #
  # Reads `Game.owned.where(release_date: today..today + 30.days)
  # .order(release_date: :asc)`. The 30-day window is the locked
  # "upcoming" horizon — anything further out lives in the calendar
  # panel. `.owned` is the canonical Phase 27 §1a scope (at least one
  # `game_platform_ownerships` row).
  #
  # When the window is empty the panel emits a muted hint
  # (`I18n.t("tui.home.panels.games_releasing.empty")`) instead of an
  # empty shelf — the same convention every other home content
  # panel follows.
  #
  # ## Focusables
  #
  # Ordered list:
  #   1. `upcoming_<id>` for each tile, in `release_date ASC` order.
  #
  # j/k walks the list in this order; TAB / Shift-TAB advances /
  # retreats panels at the screen level.
  #
  # ## Canonical wiring
  #
  # - Includes `Tui::PanelBase` for the `panel_root_data` Hash spread
  #   into the section content_tag (controller / cursor target / cable
  #   screen+name values / focusables / keybinds).
  # - Cable channel: `pito:home:games_releasing` (canonical grammar).
  # - Panel fieldset auto-mounts `tui-scroll-indicator` (horizontal
  #   axis — see template, which passes `axis: :horizontal` to
  #   `Tui::PanelFieldsetComponent`).
  #
  # ## TUI parity
  #
  # The Ratatui sibling component reads the same panel data attrs
  # emitted here to derive its focusables list + cable subscription.
  # The horizontal shelf maps to a Ratatui `Table` widget scrolled by
  # column; the bottom-edge `◀ ▶ ▬` glyphs are renderable directly
  # in Ratatui as Unicode chars on the panel's bottom border row.
  class GamesReleasingPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :games_releasing

    # Locked horizon for the "upcoming" definition. Mirrors the value
    # documented in this class's docblock + in the panel's i18n
    # subtree (where the empty-state copy references "30 days").
    UPCOMING_WINDOW_DAYS = 30

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    # Owned games whose `release_date` falls inside the
    # `[today, today + UPCOMING_WINDOW_DAYS]` window. Sorted by
    # `release_date ASC` so the leftmost tile is the soonest release.
    # `.owned` dedupes games owned across multiple platforms (DISTINCT
    # in the scope itself).
    def upcoming_games
      @upcoming_games ||= Game.owned
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
