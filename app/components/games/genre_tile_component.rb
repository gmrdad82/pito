module Games
  # Phase 27 sub-spec 01c (VC slice) — genre sub-shelf tile.
  #
  # Thin wrapper around `Games::CoverComponent` at the `:shelf`
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
    def initialize(game:)
      @game = game
    end

    private

    attr_reader :game
  end
end
