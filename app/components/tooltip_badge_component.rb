# 2026-05-16 (sessions revamp v2). Generic tooltip badge primitive.
#
# Renders a bordered `.status-badge` whose short visible `label:` reveals
# a longer `tooltip:` string on hover (or keyboard focus). The
# tooltip is a CSS-only `::after` pseudo-element keyed off
# `data-tooltip` — same pattern as `viewer-time-heatmap__cell` so a
# second tooltip mechanism does not enter the codebase. No JS, no
# Stimulus, no native `title="…"` (which has a 1-2s hover delay and is
# keyboard-inaccessible).
#
# Usage:
#
#   <%= render(TooltipBadgeComponent.new(label: "ip", tooltip: session.ip)) %>
#   <%= render(TooltipBadgeComponent.new(label: "fp", tooltip: hash, variant: :warn)) %>
#
# - `label:` — short visible text (e.g. `"ip"`). Rendered as plain
#   text inside the badge `<span>` (no `[` / `]` characters — the
#   border IS the visual delimiter, matching `StatusBadgeComponent`).
# - `tooltip:` — content revealed on hover. Coerced via `to_s`; an
#   empty / nil tooltip falls back to an em-dash so the surface still
#   reads "no value" rather than "tooltip vanished".
# - `variant:` — one of the `StatusBadgeComponent::KINDS` (default
#   `:neutral`). Unknown variants degrade to `:neutral` so dynamic
#   call sites (e.g. severity from JSON) do not have to defend.
#
# Accessibility:
#
# - The host element is the badge `<span>` itself; it carries
#   `tabindex="0"` so keyboard users can land on it. The CSS reveals
#   the tooltip on `:hover` AND `:focus`.
# - The hidden tooltip text lives in a sibling `<span role="tooltip">`
#   (visually positioned by the same `::after` rule? — no: a real
#   `<span>` is used so screen readers can announce it via
#   `aria-describedby`). The badge `<span>` references that sibling
#   via `aria-describedby`.
# - A per-instance DOM id is generated so multiple tooltip badges on
#   the same page (one per session row) do not collide.
class TooltipBadgeComponent < ViewComponent::Base
  def initialize(label:, tooltip:, variant: :neutral)
    @label = label
    @tooltip = tooltip
    @variant = variant&.to_sym || :neutral
  end

  attr_reader :label

  def variant
    StatusBadgeComponent::KINDS.include?(@variant) ? @variant : :neutral
  end

  def tooltip_text
    text = @tooltip.to_s
    text.empty? ? "—" : text
  end

  def tooltip_id
    @tooltip_id ||= "tooltip-#{SecureRandom.hex(4)}"
  end

  def badge_classes
    "status-badge status-badge--#{variant} tooltip-host"
  end
end
