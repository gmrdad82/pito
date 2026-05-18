class BracketedMutedLinkComponent < ViewComponent::Base
  # App-wide muted bracketed-link primitive. Sibling to BracketedLinkComponent:
  # same bracketed-link markup (`<a class="bracketed bracketed-muted-link">
  # [<span class="bl">label</span>]</a>`) so it inherits the bracketed-link
  # convention, but the `.bracketed-muted-link` CSS modifier overrides the
  # color to muted (--color-muted) at rest and to text (--color-text) on
  # hover. This sits between the link-colored primary action and the red
  # destructive action — it reads as "the lesser / secondary affordance".
  #
  # Originally introduced as `BracketedCancelComponent` for the app-wide
  # `[ cancel ]` exit affordance. Renamed during the 2026-05 webhook-pane
  # polish pass once a second consumer (the `[help]` link next to a primary
  # `[update]` button on Slack + Discord panes) and a third (the footer
  # version SHA link) made the "Cancel" name read misleading. The visual
  # contract is "muted secondary bracketed link with hover-lift"; the
  # default `label: "cancel"` keeps existing Doorkeeper-style call sites
  # short while the renamed primitive accommodates "help", a SHA, "close",
  # "discard", "go back", etc.
  #
  # Naming note — the CSS class is `.bracketed-muted-link` (with the
  # `-link` suffix) to avoid collision with the existing `.bracketed-muted`
  # class, which is a distinct concept: a *non-interactive* disabled-
  # affordance variant (cursor: default; no hover lift) used by the
  # Security pane bulk-revoke header swap. Two different primitives, two
  # different class names.
  #
  # Default label is "cancel"; override via `label:` for any other surface.
  def initialize(href:, label: nil, method: nil, data: {}, target: nil, rel: nil)
    @label = label || I18n.t("common.actions.cancel")
    @href = href
    @method = method
    @data = data
    @target = target
    @rel = rel
  end

  def html_data
    attrs = @data.dup
    attrs[:turbo_method] = @method if @method
    attrs
  end
end
