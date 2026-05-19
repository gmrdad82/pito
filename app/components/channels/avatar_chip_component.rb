# Phase 37 Wave A1 — channel avatar chip.
#
# A multi-select URL-toggling chip that renders an avatar tile in place
# of the plain text label `FilterChipComponent` ships with. Clicking
# toggles the channel id's membership in the csv `?channels=` URL param
# (the locked multi-channel selection pattern — see
# `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
# §"Wave A1 layout (locked)").
#
# Subcomponent composition — we instantiate a `FilterChipComponent`
# internally and DELEGATE `#checked?` + `#href` to it so the URL toggle
# logic (csv mode, path-pinning, current-params merge) stays in ONE
# place (`app/components/filter_chip_component.rb` L48-L84). The
# template diverges only on the label slot — we swap the plain text
# `<span class="md-check-static-label">` for an avatar tile so the
# checkbox-glyph chrome stays visually consistent with the surrounding
# text chips on the page.
#
# Avatar tile sizing — `calc(1.4em + 4px)` square. 2026-05-19 (chip-row
# consolidation) resize: the chip row collapsed from 2 rows to 1, so the
# avatar now spans ~1 chip row (1.4em body line-height per
# `app/assets/tailwind/application.css` L278) with 2px overflow at both
# the top and the bottom (4px total) plus `margin-top: -3px` (2026-05-19
# follow-up — 1px nudge upward from the prior -2px so the avatar disc
# center sits a hair higher relative to the `[ ]` glyph in the same
# baseline-flex row, per user request) so the `[ ]` checkbox glyph (same
# baseline-flex row, line-height 1.4) aligns with the MIDDLE of the
# avatar disc rather than the top. `border-radius: 50%` (circular) +
# `border: 1px solid var(--color-border)` per design.md §"Channel
# avatars" (L904-L928, 2026-05-19 user lock — creators upload
# transparent circular logos; rendering as a circle hides the JPEG's
# white padding).
class Channels::AvatarChipComponent < ViewComponent::Base
  # @param channel [Hash] one entry from `Channels::MockData.channels`.
  #   Required keys: `:id`, `:display_name`, `:avatar_url` (may be nil
  #   → placeholder square).
  # @param current_params [Hash] request.query_parameters — feeds the
  #   csv toggle so the chip preserves other URL state.
  def initialize(channel:, current_params: {})
    @channel = channel
    @current_params = current_params
  end

  attr_reader :channel

  # The underlying generic chip — we delegate href/checked decisions to
  # it. `csv: true` matches the locked `?channels=id1,id2,id3` URL
  # pattern; `path: "/channels"` pins the chip's href to /channels
  # regardless of where it might be rendered into a Turbo Frame later
  # (same rationale as the notifications-modal chip — see
  # `filter_chip_component.rb` L25-L37).
  def underlying_chip
    @underlying_chip ||= FilterChipComponent.new(
      label: channel[:display_name],
      param: "channels",
      value: channel[:id].to_s,
      current_params: @current_params,
      csv: true,
      path: "/channels"
    )
  end

  def checked?
    underlying_chip.checked?
  end

  def href
    underlying_chip.href
  end

  # Inline avatar tile dimension. 1.4em (one chip line-height per
  # `app/assets/tailwind/application.css` L278) + 4px overflow (2px up,
  # 2px down) — paired with `margin-top: -3px` on the tile (2026-05-19
  # follow-up: 1px nudge upward from -2px per user request) so the
  # avatar's vertical center aligns with the `[ ]` checkbox glyph in
  # the same flex row.
  def avatar_dimension_css
    "calc(1.4em + 4px)"
  end
end
