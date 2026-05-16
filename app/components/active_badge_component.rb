# 2026-05-16 (sessions revamp v2). Active status badge.
#
# Thin wrapper around `StatusBadgeComponent` that renders a fixed
# `active` label with green (`:success`) styling. Extracted so the call
# site does not have to remember the label / kind pair when the only
# thing being rendered is the "row is active" affordance.
#
# Usage:
#
#   <%= render(ActiveBadgeComponent.new) %>
#
# Optional `label:` override for callers that prefer a different
# wording (e.g. `"live"`, `"on"`) while keeping the green semantics.
#
# The Security pane's sessions table dropped its `active` column in
# the same dispatch (the visible rows are filtered to active-only, so
# the column is redundant). The component itself is kept ready for
# adoption on other surfaces where an "is this thing alive?" cell is
# meaningful.
class ActiveBadgeComponent < ViewComponent::Base
  def initialize(label: "active")
    @label = label
  end

  def call
    render(StatusBadgeComponent.new(label: @label, kind: :success))
  end
end
