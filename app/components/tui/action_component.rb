module Tui
  # Tui::ActionComponent — generic bracketed action for forms and local JS.
  #
  # Purpose:
  #   Renders a `[ label ]` bracketed action in one of three shapes:
  #   - `:submit`  — `<button type="submit" class="bracketed">` (form submit)
  #   - `:button`  — `<button type="button" class="bracketed">` (JS action)
  #   - `:link`    — `<a class="bracketed">` (navigation)
  #
  #   Unlike `Tui::ActionButtonComponent`, this component does NOT require an
  #   ActionRegistry registration. It is the right primitive for auth forms,
  #   code-block copy triggers, and any action wired directly via Stimulus
  #   data-action attrs rather than the global action bus.
  #
  # Kwargs:
  #   label:        — visible text inside the brackets. Required.
  #   as:           — :submit / :button / :link. Defaults to :button.
  #   href:         — URL string. Only relevant when as: :link.
  #   data:         — Hash of Stimulus / HTML data attributes (snake_case keys
  #                   are passed through to `content_tag` which converts them
  #                   to kebab-case automatically).
  #   destructive:  — Boolean. When true, adds `.text-danger` to the element
  #                   so the label renders in `var(--color-danger)`.
  #                   Defaults to false.
  #
  # Variants: none. Destructive state via `destructive: true`.
  #
  # Focusables: consumers wire focusable via `data:` hash if needed.
  #
  # Related:
  #   Tui::ActionButtonComponent — for action-bus registered actions
  #   BracketedLinkComponent     — for navigation-first bracketed links
  #   docs/design.md § Actions   — visual contract
  class ActionComponent < ViewComponent::Base
    def initialize(label:, as: :button, href: nil, data: {}, destructive: false)
      @label       = label
      @as          = as
      @href        = href
      @data        = data || {}
      @destructive = destructive
    end

    attr_reader :label, :as, :href, :data

    def destructive?
      @destructive
    end

    def element_classes
      base = "bracketed"
      destructive? ? "#{base} text-danger" : base
    end

    def inner_html
      "[<span class=\"bl\">#{ERB::Util.h(label)}</span>]".html_safe
    end
  end
end
