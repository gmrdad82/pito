# Phase 37 Wave A1 — right-side channel avatar shelf on `/channels`.
#
# Thin wrapper that lays out one `Channels::AvatarChipComponent` per
# channel inside a wrapping inline-flex container. Each child chip
# carries its own checkbox + avatar tile + URL-toggle behavior; this
# shelf only concerns itself with horizontal layout + inter-chip gap.
#
# Inter-chip horizontal gap: 6px — matches the chip horizontal gap
# convention used across /channels and /games chrome
# (`Games::FilterRowComponent` filter_row_component.html.erb L23). The
# two stacked filter-chip rows on the left side of the page use the
# same 6px between them, so the visual rhythm is coherent across both
# axes.
#
# The avatar tile's own size (height + width = `calc(2 * 1.4em + 6px)`)
# lives on `Channels::AvatarChipComponent` per the design.md rule
# ("avatar tile height = 2 × chip text line-height + the inter-row
# gap" — `docs/design.md` §"Channel avatars" L828-L831).
class Channels::AvatarShelfComponent < ViewComponent::Base
  # @param channels [Array<Hash>] channel hashes from
  #   `Channels::MockData.channels`. Each hash carries `:id`,
  #   `:display_name`, `:avatar_url` (may be nil → placeholder square).
  # @param current_params [Hash] request.query_parameters — forwarded
  #   to each chip so URL state composes.
  def initialize(channels:, current_params: {})
    @channels = Array(channels)
    @current_params = current_params
  end

  attr_reader :channels, :current_params
end
