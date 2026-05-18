# 2026-05-18 — Bundles modal CSS-positioned composite cover grid.
#
# Extracted from `app/views/bundles/games_pane.html.erb` (the CSS-
# positioned composite block that previously sat inline above the
# `Bundles::AllGamesTableComponent`). Mirrors the libvips composite-
# cover layout: up to nine games render as percentage-positioned
# anchors over a 3:4 canvas, with each cell's `left/top/width/height`
# computed from `Composite::CellMap.for(n)` — the same source-of-
# truth the libvips renderer uses, so layout edits propagate to both
# surfaces for free.
#
# Empty-bundle case: the component renders nothing. The
# `games_pane.html.erb` parent template still gates on the bundle
# membership to render `Bundles::EmptyCoverPlaceholderComponent`
# (B6, when extracted) for the empty visual; this component is only
# responsible for the populated composite grid.
module Bundles
  class ModalCompositeComponent < ViewComponent::Base
    def initialize(bundle:)
      @bundle = bundle
    end

    attr_reader :bundle

    def render?
      first_nine.any?
    end

    # Up to 9 member games drive the composite grid. The full member
    # list is still rendered by `Bundles::AllGamesTableComponent`
    # immediately below this component in the modal frame.
    def first_nine
      @first_nine ||= bundle.games.first(9)
    end

    # `Composite::CellMap.for(n)` returns `[{ x:, y:, w:, h: }, ...]`
    # in unit-square coordinates (0..1). Identical source of truth
    # used by the libvips composite builder for the JPEG output.
    def cells
      @cells ||= Composite::CellMap.for(first_nine.size)
    end

    # Local `master.jpg` URL when present; falls back to the IGDB
    # `t_cover_big_2x` CDN URL for games whose normalized master has
    # not been generated yet. Returns nil for truly coverless games
    # (no master, no `cover_image_id`).
    def cover_url_for(game)
      game.cover_master_url(fallback_size: "t_cover_big_2x")
    end
  end
end
