# Wave C4 stub (spec 08 §"Ownership chips") — per-platform ownership
# toggle chip rendered in the /games/:id LEFT-pane ownership section.
#
# Renders a `Platforms::ChipComponent` (size :md) tinted by the brand
# color when the user owns the game on this platform, muted gray when
# not. Wraps the chip in a form posting to the existing
# `Games::PlatformOwnershipsController#update` endpoint with the
# toggled platform added to / removed from the flat `platform_owned_ids[]`
# array.
#
# TODO (polish slice): the toggle form currently submits the FULL set
# of owned-platform ids with the target slug flipped, mirroring the
# editor page semantics. A dedicated per-platform toggle endpoint
# would be cleaner; deferred — this stub keeps the visual structure
# in place and re-uses the existing controller without schema work.
class Game
  class PlatformOwnershipChipComponent < ViewComponent::Base
    def initialize(game:, slug:)
      @game = game
      @slug = slug.to_s
    end

    attr_reader :game, :slug

    def render?
      Platforms::ChipComponent::SLUG_BRAND.key?(slug) && platform.present?
    end

    def platform
      @platform ||= Platform.find_by(slug: slug)
    end

    def owned?
      return false unless platform
      owned_platform_ids.include?(platform.id)
    end

    def owned_platform_ids
      @owned_platform_ids ||= game.game_platform_ownerships.pluck(:platform_id)
    end

    # Submitted ids after the toggle: current set ± this platform.
    def toggled_ids
      ids = owned_platform_ids.dup
      if owned?
        ids.delete(platform.id)
      else
        ids << platform.id
      end
      ids
    end

    def label
      Platforms::ChipComponent::SLUG_BRAND.dig(slug, :label)
    end

    def color
      Platforms::ChipComponent::SLUG_BRAND.dig(slug, :color)
    end

    # Muted tone when not owned; brand color when owned.
    def chip_color
      owned? ? color : "var(--color-muted)"
    end
  end
end
