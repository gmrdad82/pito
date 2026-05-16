# 2026-05-16 (sessions revamp v2). Yes / no status badge.
#
# Thin wrapper around `StatusBadgeComponent` that renders the boolean
# as `yes` (green via `:yes`) or `no` (muted via `:no`). Extracted so
# the call site does not repeat the `:yes` / `:no` symbol pick around
# every boolean field.
#
# Usage:
#
#   <%= render(YesNoBadgeComponent.new(value: record.remember?)) %>
#
# `value` is the canonical boolean. The project's external-boundary
# rule keeps wire formats as `"yes"` / `"no"` strings; this component
# also accepts the string forms so a render fed directly from a JSON
# blob or MCP response does not need a per-call coercion.
#
# The Security pane's sessions table dropped its `remember` column in
# the same dispatch — but the component itself is kept ready for
# adoption on other surfaces (channels schema, video schema, etc.)
# where a boolean-status column is rendered.
class YesNoBadgeComponent < ViewComponent::Base
  def initialize(value:)
    @value = value
  end

  def yes?
    case @value
    when true, "yes", "true", 1, "1" then true
    else false
    end
  end

  def call
    render(StatusBadgeComponent.new(
      label: yes? ? "yes" : "no",
      kind:  yes? ? :yes  : :no
    ))
  end
end
