# Phase 27 §01f — Per-platform ownership editor.
#
# Renders a checklist of every platform the game is released on (from
# IGDB) plus any platform the user already owns the game on (covers
# manually-added rows whose platform was scrubbed from IGDB later).
# Each row carries:
#
#   - `_own` checkbox (`"yes"` / `"no"` per the project's yes/no
#     boundary rule). Leading hidden field carries the unchecked-value
#     "no" so the controller always sees a value.
#   - `acquired_at` date input (optional metadata).
#   - `store` free-text input (optional metadata).
#   - `notes` text area (optional metadata).
#
# Each row carries a hidden `platform_id` input so the controller can
# locate the platform regardless of whether the row is persisted or
# in-memory. When the row IS persisted, a hidden `id` input carries
# the existing GamePlatformOwnership id so the controller can route
# the row through the nested-attributes update / destroy path.
#
# The component renders raw input elements (not via a FormBuilder)
# because the editor uses indexed nested-attribute names —
# `game[game_platform_ownerships_attributes][N][...]` — which Rails'
# default `fields_for` API doesn't index by an explicit integer
# without extra ceremony.
module Games
  class PlatformOwnershipEditorComponent < ViewComponent::Base
    def initialize(game:, ownerships_by_platform:)
      @game = game
      @ownerships_by_platform = ownerships_by_platform
    end

    attr_reader :game, :ownerships_by_platform

    def any_rows?
      ownerships_by_platform.any?
    end
  end
end
