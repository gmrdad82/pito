class Game
  # Phase 27 sub-spec 01c (VC slice) — genre sub-shelf tile.
  #
  # Thin wrapper around `Game::CoverComponent` at the `:shelf`
  # variant for use inside `_genre_sub_shelf.html.erb`. Exists so
  # the genre row has one named tile primitive — future tweaks
  # (badge overlays, hover meta, etc.) land here instead of inside
  # the partial.
  #
  # Current behavior mirrors the previous inline render exactly:
  # `CoverComponent` at `:shelf` with its default
  # `link_to_show: true` (which already emits the `<a href=...>`
  # to the game show page). No extra outer wrapper, no extra
  # class, no `data-turbo-frame` — matches the partial as-shipped.
  # The shelf-tile component is intentionally minimal so that the
  # parent partial's flex row layout is unaffected by the
  # extraction.
  class GenreTileComponent < ViewComponent::Base
    # `link_to` and `data` are optional overrides. When `link_to` is
    # `nil` (explicitly passed), the underlying CoverComponent is
    # rendered with `link_to_show: false` — the tile becomes a bare
    # cover suitable for wrapping in an arbitrary click target (e.g.
    # the omnisearch recommendations shelf, where the click POSTs to
    # /bundles/:id/members instead of navigating to /games/:slug).
    # `data` hash is splatted onto the outer wrapper as HTML data-*
    # attributes so consumers can attach Stimulus controllers /
    # actions / values without subclassing the tile.
    def initialize(game:, link_to: :default, data: {})
      @game = game
      @link_to_override = link_to
      @data = data
    end

    def link_to_show?
      @link_to_override != nil
    end

    def data_attrs
      @data || {}
    end

    private

    attr_reader :game
  end
end
