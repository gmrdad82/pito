# Shared bordered status badge.
#
# Renders a small bordered `<span>` whose border + color encode a status
# (`info` / `success` / `warn` / `urgent` / `neutral` / `yes` / `no` /
# `all_day` / ...). The border IS the visual delimiter — no literal `[` `]`
# characters around the label.
#
# Replaces ad-hoc badge styles that previously lived in
# `.notification-severity-badge` and `.calendar-badge--all-day`. Those CSS
# classes are kept as ALIASES of the canonical `.status-badge` rule so
# external references (specs, third-party copy/paste) keep working until they
# are migrated.
#
# Usage:
#
#   <%= render(StatusBadgeComponent.new(label: "info",    kind: :info)) %>
#   <%= render(StatusBadgeComponent.new(label: "success", kind: :success)) %>
#   <%= render(StatusBadgeComponent.new(label: "all day", kind: :all_day)) %>
#
# Unknown kinds fall back to `:neutral` styling rather than raising — the
# component is intentionally permissive so view code can pass dynamic kinds
# (e.g. `notification.severity.to_sym`) without a defensive `respond_to?` /
# `include?` wrapper at the call site.
class StatusBadgeComponent < ViewComponent::Base
  KINDS = %i[info success warn urgent neutral yes no all_day].freeze

  def initialize(label:, kind: :neutral)
    @label = label
    @kind = kind&.to_sym || :neutral
  end

  attr_reader :label

  def kind
    KINDS.include?(@kind) ? @kind : :neutral
  end

  def css_classes
    "status-badge status-badge--#{kind}"
  end
end
