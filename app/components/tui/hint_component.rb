module Tui
  # Tui::HintComponent — inline italic muted hint text.
  #
  # Purpose:
  #   Renders a single-line hint below the element it explains.
  #   Default severity is :muted (color: var(--color-muted), font-style: italic)
  #   per the `.tui-hint` CSS rule.
  #
  #   When severity: :danger, adds `.text-danger` so the hint renders in
  #   `var(--color-danger)` — used for login error messages.
  #
  # Kwargs:
  #   text:      — The hint string. Required.
  #   severity:  — :muted (default) or :danger.
  #
  # Variants: none — severity is a kwarg, not a sub-class.
  #
  # CSS: relies on `.tui-hint` (application.css § Tui::HintComponent) and the
  #   `.text-danger` utility class. No new classes added.
  #
  # Related:
  #   docs/design.md § Hints
  class HintComponent < ViewComponent::Base
    def initialize(text:, severity: :muted)
      @text     = text
      @severity = severity
    end

    attr_reader :text

    def danger?
      @severity == :danger
    end

    def css_classes
      danger? ? "tui-hint text-danger" : "tui-hint"
    end
  end
end
