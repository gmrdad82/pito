# Phase 27 §01f — Per-platform ownership editor.
#
# Editor revamp (2026-05-12): renders a single bracketed-checkbox row
# (`[ ] <Platform Name>`) per platform. Every platform the game is
# released on (from IGDB) plus any platform the user already owns the
# game on (covers manually-added rows whose platform was scrubbed from
# IGDB later) gets one entry. The form posts a flat
# `platform_owned_ids[]` array; absent platforms are treated as not
# owned. No per-row metadata inputs.
#
# Uses the project's `.md-check` bracketed-checkbox pattern: a real
# `<input type="checkbox">` (visually hidden via CSS) plus
# `<span class="md-check-indicator">` rendered as `[ ]` / `[x]` via
# CSS pseudo-elements — never a bare browser checkbox.
module Games
  class PlatformOwnershipEditorComponent < ViewComponent::Base
    def initialize(game:, platforms:, owned_platform_ids:)
      @game = game
      @platforms = platforms
      @owned_platform_ids = owned_platform_ids.to_a
    end

    attr_reader :game, :platforms, :owned_platform_ids

    def any_platforms?
      platforms.any?
    end

    def owned?(platform)
      owned_platform_ids.include?(platform.id)
    end
  end
end
