# Wave C4 stub (spec 08 §"Ownership chips") — single `[played]` chip
# for the /games/:id LEFT-pane ownership section. User-confirmed
# 2026-05-17 override: SINGLE chip, not per-platform.
#
# Visual state: colored (active green tone) when `@game.played_at` is
# present; muted gray otherwise. Non-functional in this slice — a
# dedicated toggle endpoint is a follow-up polish slice (the existing
# `Game` form at `/games/:id/edit` is the current edit surface for
# `played_at`).
module Games
  class PlayedChipComponent < ViewComponent::Base
    def initialize(game:)
      @game = game
    end

    attr_reader :game

    def played?
      game.played_at.present?
    end

    def chip_color
      # `--color-active` is the shared bracketed-active tint used
      # across the app (matches `[★]` and friends). Falls back to a
      # green tone for themes that don't define it.
      played? ? "var(--color-active, #228b22)" : "var(--color-muted)"
    end
  end
end
